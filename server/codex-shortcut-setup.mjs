import {constants} from 'node:fs';
import {lstat,mkdir,open,rename,unlink} from 'node:fs/promises';
import {createHash,randomBytes} from 'node:crypto';
import path from 'node:path';
import {parseMacShortcut,resolveCodexShortcut} from './codex-shortcuts.mjs';
import {describeAction} from './codex.mjs';

const targets=[
  {id:'approve',command:'approval.approve',label:'批准当前请求',preferred:13},
  {id:'decline',command:'approval.decline',label:'拒绝当前请求',preferred:14},
  {id:'newWindow',command:'newWindow',label:'新建任务窗口',preferred:15},
  {id:'dictation',command:'globalDictationHold',label:'听写',preferred:17},
  {id:'sendPrompt',command:'composer.submit',label:'发送任务指令',preferred:16},
];
const stateName='codex-shortcut-setup-state.json';
const queues=new Map();
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const changed=()=>new Error('Codex 快捷键文件或按键设置已更改，请重新查看方案。');
const unknownLock=()=>new Error('锁记录无法确认，请保留备份并重新检查快捷键设置。');
const busyLock=()=>new Error('另一个快捷键设置操作正在进行，请稍后重新检查。');
const changedLock=()=>new Error('快捷键设置锁已更改，请稍后重新检查。');

async function directory(dir,create=false) {
  try {
    const info=await lstat(dir);
    if(info.isSymbolicLink())throw new Error('快捷键设置目录不能是符号链接。');
    if(!info.isDirectory())throw new Error('快捷键设置路径不是文件夹。');
  } catch(error) {
    if(error.code!=='ENOENT')throw error;
    if(create) {await mkdir(dir,{recursive:true,mode:0o700});await directory(dir);}
  }
}
async function optionalFile(file,limit) {
  let handle;
  try {
    const info=await lstat(file);
    if(info.isSymbolicLink())throw new Error('快捷键设置文件不能是符号链接。');
    if(!info.isFile()||info.size>limit)throw new Error('快捷键设置文件格式无效或过大。');
    handle=await open(file,constants.O_RDONLY|constants.O_NOFOLLOW);
    const actual=await handle.stat();
    if(!actual.isFile()||actual.size>limit||actual.ino!==info.ino||actual.dev!==info.dev)throw changed();
    const bytes=await handle.readFile();
    if(bytes.length>limit)throw new Error('快捷键设置文件过大。');
    return {exists:true,bytes,hash:sha(bytes),mode:actual.mode&0o777,ino:actual.ino,dev:actual.dev};
  } catch(error) {
    if(error.code==='ENOENT')return {exists:false,hash:null,mode:0o600};
    if(error.code==='ELOOP')throw new Error('快捷键设置文件不能是符号链接。');
    throw error;
  } finally {await handle?.close();}
}
function json(file,label,fallback) {
  if(!file.exists)return fallback;
  try {return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(file.bytes));}
  catch {throw new Error(`无法读取 ${label}，原文件未修改。`);}
}
function token(file) {return {exists:file.exists,hash:file.hash,mode:file.mode,ino:file.ino,dev:file.dev};}
function chord(value) {
  if(typeof value!=='string')return null;
  const parts=value.split('+'),key=parts.pop().trim();
  const aliases={printscreen:'F13',scrolllock:'F14',pause:'F15'};
  const normalized=aliases[key.toLowerCase()]??(/^f\d+$/i.test(key)?key.toUpperCase():key);
  const parsed=parseMacShortcut([...parts,normalized].join('+'),{allowBareModifiers:true});
  return parsed?JSON.stringify([Boolean(parsed.modifierOnly),parsed.modifierOnly?null:parsed.keyCode,[...parsed.modifiers].sort()]):null;
}
async function exclusive(file,bytes,mode=0o600) {
  const handle=await open(file,constants.O_WRONLY|constants.O_CREAT|constants.O_EXCL|constants.O_NOFOLLOW,mode);
  try {await handle.writeFile(bytes);await handle.chmod(mode);await handle.sync();}
  finally {await handle.close();}
}
async function atomic(file,bytes,mode,beforeRename=async()=>{}) {
  const temp=path.join(path.dirname(file),`.${path.basename(file)}.tmp-${randomBytes(8).toString('hex')}`);
  try {await exclusive(temp,bytes,mode);await beforeRename();await rename(temp,file);}
  finally {await unlink(temp).catch(error=>{if(error.code!=='ENOENT')throw error;});}
}
async function serial(key,operation) {
  const previous=queues.get(key)??Promise.resolve();
  const next=previous.catch(()=>{}).then(operation);queues.set(key,next);
  try {return await next;} finally {if(queues.get(key)===next)queues.delete(key);}
}
function lockOwner(file) {
  if(!file.exists)return null;
  let record;
  try {record=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(file.bytes));}
  catch {throw unknownLock();}
  if(!record||record.version!==1||!Number.isSafeInteger(record.pid)||record.pid<=0
    ||typeof record.owner!=='string'||!/^[a-f0-9]{32}$/.test(record.owner))throw unknownLock();
  return record;
}
function sameLock(left,right) {
  return left.exists&&right.exists&&left.ino===right.ino&&left.dev===right.dev&&left.bytes.equals(right.bytes);
}
async function lockFile(file) {
  try {return await optionalFile(file,4096);} catch {throw unknownLock();}
}
async function acquireLock(file) {
  for(let attempt=0;attempt<3;attempt++) {
    let handle;
    try {
      handle=await open(file,constants.O_WRONLY|constants.O_CREAT|constants.O_EXCL|constants.O_NOFOLLOW,0o600);
    } catch(error) {
      if(error.code!=='EEXIST')throw error;
      const previous=await lockFile(file),owner=lockOwner(previous);
      if(!owner)continue;
      try {process.kill(owner.pid,0);} catch(error) {
        if(error.code!=='ESRCH')throw unknownLock();
        const current=await lockFile(file);
        if(!sameLock(previous,current))throw changedLock();
        await unlink(file).catch(error=>{if(error.code!=='ENOENT')throw error;});
        continue;
      }
      throw busyLock();
    }
    const owner={version:1,pid:process.pid,owner:randomBytes(16).toString('hex')};
    const bytes=Buffer.from(JSON.stringify(owner)+'\n');
    try {
      await handle.writeFile(bytes);await handle.sync();
      const info=await handle.stat();
      return {handle,owner,file:{exists:true,bytes,ino:info.ino,dev:info.dev}};
    } catch(error) {await handle.close();throw error;}
  }
  throw changedLock();
}
async function releaseLock(file,held) {
  await held.handle.close();
  // A later owner may have replaced this path. Preserve every record that is
  // not still this operation's exact inode, bytes and random owner token.
  let current,owner;
  try {current=await lockFile(file);owner=lockOwner(current);} catch {return;}
  if(sameLock(held.file,current)&&owner?.pid===held.owner.pid&&owner?.owner===held.owner.owner)
    await unlink(file).catch(error=>{if(error.code!=='ENOENT')throw error;});
}

// This is a normal, user-confirmed product configuration workflow. Planning is
// read-only; applying never starts Codex, posts an event, or edits global state.
export class CodexShortcutSetup {
  constructor({codexHome,backupDir,blockedCodes=[],codexDesktopVersion=process.env.AIR_STUDIO_CODEX_DESKTOP_VERSION,managedTargets=targets,readLegacy=true}) {
    if(typeof codexHome!=='string'||!codexHome||typeof backupDir!=='string'||!backupDir)throw new Error('快捷键设置缺少独立配置或备份目录。');
    this.codexHome=path.resolve(codexHome);this.backupDir=path.resolve(backupDir);
    if(this.codexHome===this.backupDir)throw new Error('快捷键备份必须使用独立文件夹。');
    this.blockedCodes=blockedCodes;this.version=codexDesktopVersion;
    this.targets=managedTargets;this.readLegacy=readLegacy;
    this.keymapFile=path.join(this.codexHome,'keybindings.json');
    this.stateFile=path.join(this.backupDir,stateName);
  }
  async snapshot() {
    await Promise.all([directory(this.codexHome),directory(this.backupDir)]);
    const [keymap,legacy,state]=await Promise.all([
      optionalFile(this.keymapFile,262144),this.readLegacy?optionalFile(path.join(this.codexHome,'.codex-global-state.json'),8*1024*1024):Promise.resolve({exists:false}),
      optionalFile(this.stateFile,65536),
    ]);
    const entries=json(keymap,'Codex keybindings.json',[]),legacyValue=json(legacy,'Codex 听写设置',{});
    if(!Array.isArray(entries)||entries.some(entry=>!entry||typeof entry!=='object'||Array.isArray(entry)||typeof entry.command!=='string'
      ||!(entry.key===null||typeof entry.key==='string')||(Object.hasOwn(entry,'version')&&entry.version!==1)))
      throw new Error('无法读取 Codex keybindings.json，原文件未修改。');
    if(!legacyValue||typeof legacyValue!=='object'||Array.isArray(legacyValue)
      ||['globalDictationHotkey','globalDictationToggleHotkey'].some(name=>legacyValue[name]!=null&&typeof legacyValue[name]!=='string'))
      throw new Error('无法读取 Codex 听写设置，原文件未修改。');
    const reload=json(state,'快捷键设置记录',{version:1,requiresReload:false});
    if(!reload||reload.version!==1||typeof reload.requiresReload!=='boolean'
      ||(reload.backupFile!==undefined&&(typeof reload.backupFile!=='string'||!/^[A-Za-z0-9._-]+$/.test(reload.backupFile))))
      throw new Error('无法读取快捷键设置记录，请保留备份并重新检查。');
    const blocked=typeof this.blockedCodes==='function'?this.blockedCodes():this.blockedCodes;
    if(!Array.isArray(blocked)||blocked.some(code=>typeof code!=='string'))throw new Error('键盘按键配置无效，请重新检查。');
    // Codex saves unrelated chat/window state frequently. Only these two
    // documented dictation fields affect a setup preview's validity.
    const legacyBindings=Object.fromEntries(['globalDictationHotkey','globalDictationToggleHotkey'].map(name=>
      [name,{present:Object.hasOwn(legacyValue,name),value:Object.hasOwn(legacyValue,name)?legacyValue[name]:null}]));
    const input={keymap:token(keymap),legacy:legacyBindings,blocked:[...blocked],version:this.version??null};
    return {keymap,legacy,state,entries,legacyValue,reload,blocked:[...blocked],input,
      contentRevision:sha(JSON.stringify(input)),revision:sha(JSON.stringify({...input,state:token(state)}))};
  }
  async plan() {
    const snapshot=await this.snapshot();
    const rows=await Promise.all(this.targets.map(async target=>{
      let configured=snapshot.entries.some(entry=>entry.command===target.command);
      if(target.id==='dictation')configured=configured||snapshot.entries.some(entry=>entry.command==='globalDictationSingleTap')
        ||Object.hasOwn(snapshot.legacyValue,'globalDictationHotkey')||Object.hasOwn(snapshot.legacyValue,'globalDictationToggleHotkey');
      // A setup plan must not claim that the retired composer's unversioned
      // fallback establishes a configured global dictation listener.
      if(target.id==='dictation'&&!configured)
        return {id:target.id,command:target.command,label:target.label,status:'add'};
      if(target.dedicated&&!configured)return {id:target.id,command:target.command,label:target.label,status:'add'};
      try {
        const shortcut=await resolveCodexShortcut({...describeAction(target.id),...(target.dedicated?{requiresDedicatedShortcut:true}:{})},{codexHome:this.codexHome,blockedCodes:snapshot.blocked,codexDesktopVersion:this.version});
        return {id:target.id,command:target.command,label:target.label,status:'ready',accelerator:shortcut.accelerator};
      } catch(error) {
        if(/无法读取/.test(error.message))throw error;
        const disabled=snapshot.entries.some(entry=>entry.command===target.command&&entry.key===null);
        const blocked=disabled||configured&&!target.allowAdditionalBinding||/停用/.test(error.message);
        return {id:target.id,command:target.command,label:target.label,status:blocked?'blocked':'add',
          ...(blocked?{reason:error.message}:{})};
      }
    }));
    const reserved=new Set([...snapshot.entries.map(entry=>chord(entry.key)),
      chord(snapshot.legacyValue.globalDictationHotkey),chord(snapshot.legacyValue.globalDictationToggleHotkey)].filter(Boolean));
    const changes=[];
    for(const [index,row] of rows.entries())if(row.status==='add') {
      const preferred=this.targets[index].preferred;
      const candidates=[`Control+Shift+F${preferred}`,...['Control+Shift','Control+Option','Control+Shift+Option','Control+Shift+Option+Command']
        .flatMap(modifiers=>Array.from({length:8},(_,offset)=>`${modifiers}+F${offset+13}`))];
      const blockedKeyCodes=new Set(snapshot.blocked.map(value=>parseMacShortcut(value)?.keyCode));
      const accelerator=candidates.find(value=>!reserved.has(chord(value))&&!blockedKeyCodes.has(parseMacShortcut(value)?.keyCode));
      if(!accelerator) {row.status='blocked';row.reason='没有可安全添加的空闲专用快捷键，请在 Codex 中手动配置。';}
      else {row.accelerator=accelerator;row.reason='将添加此快捷键，保留现有配置。';reserved.add(chord(accelerator));changes.push({command:row.command,key:accelerator});}
    }
    if((await this.snapshot()).revision!==snapshot.revision)throw changed();
    const result={revision:snapshot.revision,rows,changes,canApply:changes.length>0&&!snapshot.reload.requiresReload,
      requiresReload:snapshot.reload.requiresReload,...(snapshot.reload.backupFile?{backupPath:path.join(this.backupDir,snapshot.reload.backupFile)}:{})};
    this.latest=structuredClone(result);return result;
  }
  async status() {return this.latest?structuredClone(this.latest):this.plan();}
  async withLock(operation) {
    return serial(this.keymapFile,async()=>{
      await directory(this.backupDir,true);
      const lock=path.join(this.backupDir,'codex-shortcut-setup.lock'),held=await acquireLock(lock);
      try {return await operation();} finally {await releaseLock(lock,held);}
    });
  }
  async apply({revision,confirmed}={}) {
    if(confirmed!==true)throw new Error('请先查看方案并确认添加快捷键。');
    return this.withLock(async()=>{
      const plan=await this.plan(),snapshot=await this.snapshot();
      if(typeof revision!=='string'||revision!==plan.revision||revision!==snapshot.revision)throw changed();
      if(plan.requiresReload)throw new Error('请先手动重启 Codex，再点击「已重启，重新检查」。');
      if(!plan.canApply)throw new Error('当前没有可添加的快捷键，请先处理标明的问题。');
      await directory(this.codexHome,true);
      const name=`codex-keybindings-${Date.now()}-${randomBytes(6).toString('hex')}`;
      const metadataFile=name+'.metadata.json',originalFile=name+'.original.json';
      if(snapshot.keymap.exists)await exclusive(path.join(this.backupDir,originalFile),snapshot.keymap.bytes);
      const metadata={version:1,createdAt:new Date().toISOString(),originalExisted:snapshot.keymap.exists,
        originalMode:snapshot.keymap.mode,originalSha256:snapshot.keymap.hash,originalFile:snapshot.keymap.exists?originalFile:null};
      await exclusive(path.join(this.backupDir,metadataFile),JSON.stringify(metadata,null,2)+'\n');
      const marker=Buffer.from(JSON.stringify({version:1,requiresReload:true,backupFile:metadataFile},null,2)+'\n');
      let marked=false,written=false;
      try {
        const bytes=JSON.stringify([...snapshot.entries,...plan.changes],null,2)+'\n';
        await atomic(this.keymapFile,bytes,snapshot.keymap.exists?snapshot.keymap.mode:0o600,async()=>{
          if((await this.snapshot()).revision!==snapshot.revision)throw changed();
          await atomic(this.stateFile,marker,0o600);marked=true;
          if((await this.snapshot()).contentRevision!==snapshot.contentRevision)throw changed();
        });
        written=true;
      } catch(error) {
        if(marked&&!written) {
          const current=await optionalFile(this.stateFile,65536);
          if(current.hash===sha(marker)) {
            if(snapshot.state.exists)await atomic(this.stateFile,snapshot.state.bytes,snapshot.state.mode);
            else await unlink(this.stateFile);
          }
        }
        throw error;
      }
      return this.plan();
    });
  }
  async confirmReload({confirmed}={}) {
    if(confirmed!==true)throw new Error('请先手动重启 Codex，再确认重新检查。');
    return this.withLock(async()=>{
      const snapshot=await this.snapshot();
      if(snapshot.reload.requiresReload) {
        const next={...snapshot.reload,requiresReload:false};
        await atomic(this.stateFile,JSON.stringify(next,null,2)+'\n',0o600,async()=>{
          if((await this.snapshot()).revision!==snapshot.revision)throw changed();
        });
      }
      // User acknowledgement clears the reminder; it does not verify that the
      // target application loaded its bindings or that an action executed.
      return this.plan();
    });
  }
}
