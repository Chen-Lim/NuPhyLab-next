import {stat} from 'node:fs/promises';
import {CodexShortcutSetup} from './codex-shortcut-setup.mjs';
import {resolveCodexShortcut} from './codex-shortcuts.mjs';

export const BRIDGE_TARGETS=Object.freeze([
  {id:'approve',command:'approval.approve',label:'批准',preferred:13},
  {id:'decline',command:'approval.decline',label:'拒绝',preferred:14},
  {id:'sendPrompt',command:'composer.submit',label:'发送',preferred:16},
].map(row=>Object.freeze({...row,dedicated:true,allowAdditionalBinding:true})));

// Public OS process metadata only. A fresh launch is a prerequisite for using
// external bindings, never proof that a command ran or was accepted by Codex.
export function freshCodexProcess(value,mtimeMs,now=Date.now()) {
  return value?.installed===true&&value.running===true&&value.processCount===1
    &&Number.isSafeInteger(value.pid)&&value.pid>0&&Number.isFinite(value.launchedAtMs)
    &&value.launchedAtMs>mtimeMs&&value.launchedAtMs<=now+1000;
}
const failure=(code,message)=>Object.assign(new Error(message),{code});
export class CodexCommandBridge {
  constructor({codexHome,backupDir,processInfo,blockedCodes=()=>[],enabled=()=>true,now=Date.now}) {
    this.home=codexHome;this.processInfo=processInfo;this.enabled=enabled;this.now=now;this.blockedCodes=blockedCodes;
    this.setup=new CodexShortcutSetup({codexHome,backupDir,blockedCodes,managedTargets:BRIDGE_TARGETS,readLegacy:false});
    this.current={status:'idle',message:'开启 Codex 模式后自动准备命令键。',actions:{},activationConfirmed:false};
  }
  snapshot() {return structuredClone(this.current);}
  async close() {this.closed=true;await this.pending;}
  resume() {this.closed=false;}
  async inspect() {
    if(this.pending)return this.pending;
    this.pending=this.refresh().catch(error=>{
      this.current={status:'error',message:error.message,actions:{},activationConfirmed:false};
      return this.snapshot();
    }).finally(()=>{this.pending=null;});
    return this.pending;
  }
  async refresh() {
    if(this.closed||!this.enabled()) {
      this.current={status:'idle',message:'开启 Codex 模式后自动准备命令键。',actions:{},activationConfirmed:false};
      return this.snapshot();
    }
    const process=await this.processInfo();
    if(process?.installed!==true) {
      this.current={status:'missing-app',message:'请先安装并打开 Codex。',actions:{},activationConfirmed:false};
      return this.snapshot();
    }
    let plan=await this.setup.plan();
    let mtime=(await stat(this.setup.keymapFile).catch(error=>{if(error.code!=='ENOENT')throw error;return {mtimeMs:Infinity};})).mtimeMs;
    if(plan.requiresReload&&freshCodexProcess(process,mtime,this.now()))plan=await this.setup.confirmReload({confirmed:true});
    // Called only while the user has enabled Codex mode. No per-key setup UI,
    // forced restart, automatic approval, or real action is part of provisioning.
    if(plan.canApply&&!this.closed&&this.enabled())plan=await this.setup.apply({revision:plan.revision,confirmed:true});
    if(this.closed)return this.snapshot();
    mtime=(await stat(this.setup.keymapFile)).mtimeMs;
    const fresh=freshCodexProcess(process,mtime,this.now());
    const actions=Object.fromEntries(plan.rows.map(row=>[row.id,{available:row.status==='ready'&&fresh,
      accelerator:row.accelerator,...(row.status==='blocked'?{reason:row.reason}:!fresh?{reason:'命令键已准备，请退出并重新打开 Codex。'}:{})}]));
    const blocked=plan.rows.filter(row=>row.status==='blocked');
    const status=!process.running?'open-app':!fresh?'restart-required':blocked.length?'partial':'prepared';
    const message=status==='open-app'?'命令键已准备，打开 Codex 后即可测试。':status==='restart-required'
      ?'命令键已准备，请退出并重新打开 Codex；软件会自动检查。':blocked.length
      ?'部分命令在 Codex 中已停用或不可配置；原设置已保留。':'命令键已准备，可在 Codex 中按实体键测试。';
    this.current={status,message,actions,activationConfirmed:false,processRestartObserved:fresh,
      targetVersion:typeof process.version==='string'?process.version:'',blocked:blocked.map(row=>({id:row.id,label:row.label,reason:row.reason}))};
    return this.snapshot();
  }
  async availability(action) {
    const status=await this.inspect(),availability=status.actions[action.id];
    if(this.closed)throw failure('CODEX_BRIDGE_CLOSED','命令键接入已暂停。');
    if(!availability?.available)throw failure('CODEX_BRIDGE_NOT_READY',availability?.reason??status.message);
    return {accelerator:availability.accelerator};
  }
  async resolve(action) {
    await this.availability(action);
    // Re-read both the file and process for each real press. The native helper
    // rechecks this identity immediately before posting to prevent restart races.
    const before=await stat(this.setup.keymapFile);
    if(this.closed)throw failure('CODEX_BRIDGE_CLOSED','命令键接入已暂停。');
    const process=await this.processInfo();
    const shortcut=await resolveCodexShortcut({...action,requiresDedicatedShortcut:true},
      {codexHome:this.home,blockedCodes:this.blockedCodes()});
    const after=await stat(this.setup.keymapFile);
    if(before.ino!==after.ino||before.mtimeMs!==after.mtimeMs||before.size!==after.size
      ||!freshCodexProcess(process,after.mtimeMs,this.now()))
      throw failure('CODEX_BRIDGE_NOT_READY','Codex 或快捷键配置已变化，请重新打开 Codex 后重试。');
    return {...shortcut,expectedPID:process.pid,expectedLaunchMs:process.launchedAtMs};
  }
}
