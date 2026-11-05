// A local UI review surface. Never starts a native host or HID binary.
import http from 'node:http';
import {spawn} from 'node:child_process';
import {randomBytes,randomUUID} from 'node:crypto';
import {mkdtemp,mkdir,readFile,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

process.umask(0o077);
const root=fileURLToPath(new URL('../',import.meta.url));
const baseEnvironment={PATH:'/usr/bin:/bin:/usr/sbin:/sbin',LANG:'zh_CN.UTF-8',TZ:'Asia/Shanghai'};
// Re-exec before importing any application or fixture modules.
if(!process.argv.includes('--isolated-worker')) {
  const worker=spawn(process.execPath,[fileURLToPath(import.meta.url),...process.argv.slice(2),'--isolated-worker'],{cwd:root,env:baseEnvironment,stdio:'inherit'});
  for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>worker.kill(signal));
  const code=await new Promise((resolve,reject)=>{worker.on('error',reject);worker.on('exit',resolve);});
  process.exit(code??1);
}
const check=process.argv.includes('--check');
const previews=path.join(root,'backups/ui-previews');
if(!check)await mkdir(previews,{recursive:true,mode:0o700});
const dir=await mkdtemp(path.join(check?tmpdir():previews,'nuphylab-isolated-preview-'));
const home=path.join(dir,'home'),uiDir=path.join(dir,'ui');
await mkdir(home);await mkdir(path.join(dir,'tmp'));
// No inherited Host keys, parent PID, node loaders, CLI credentials or data paths.
const environment={PATH:'/usr/bin:/bin:/usr/sbin:/sbin',HOME:home,TMPDIR:path.join(dir,'tmp'),LANG:'zh_CN.UTF-8',TZ:'Asia/Shanghai'};
Object.assign(process.env,environment);
const {fakeService}=await import('../tests/helpers/fake-service.mjs');
const {KEYBOARD_MODELS,isKeyboardModel,getKeyboardProfile}=await import('../shared/keyboard-models.mjs');
async function run(args,cwd=root) {
  await new Promise((resolve,reject)=>{
    const child=spawn(process.execPath,args,{cwd,env:environment,stdio:['ignore','pipe','pipe']});
    let output='';for(const pipe of [child.stdout,child.stderr])pipe.on('data',b=>{output=(output+b).slice(-8000);});
    child.on('error',reject);child.on('exit',code=>code===0?resolve():reject(new Error(output)));
  });
}
const cleanup=[];let service,server,closing=false;
async function close() {
  if(closing)return;closing=true;
  if(server)await new Promise(resolve=>server.close(resolve));
  for(const stop of cleanup.reverse())await stop();
  if(check)await rm(dir,{recursive:true,force:true});
}
process.on('SIGTERM',()=>void close().then(()=>process.exit(0)));
process.on('SIGINT',()=>void close().then(()=>process.exit(0)));
const token=randomBytes(32).toString('hex');
const previewID=randomUUID();
const allowed=new Set(['connect','disconnect','settings','preview','play','pause','stop','saveScene','deleteScene','importScenes','lightActivity','lightWake','readColors','readBoardSleep','verifyColors','refresh']);
const settingKeys=new Set(['airTopRightModule','language','brightness','outputColorProfile','lightDurationMs','lightIdleMs','quotaSideEnabled','canvasBrightness','codexCommandIds']);
const banner=`<style>
#isolated-preview{position:fixed;inset:0 0 auto;z-index:10000;min-height:64px;padding:10px 20px;background:#edf5f1;border-bottom:1px solid #c4d8cc;display:flex;align-items:center;gap:16px;box-sizing:border-box;font:12px/1.6 -apple-system,BlinkMacSystemFont,sans-serif;color:#254637}
#isolated-preview strong{font-size:13px}#isolated-preview label{margin-left:auto;white-space:nowrap}#isolated-preview select{margin-left:8px;padding:5px;border:1px solid #b4cabc;border-radius:6px;background:white}
body{padding-top:68px!important}.lab-v5.app-shell{min-height:calc(100vh - 68px)!important}.lab-v5 .sidebar{top:68px!important;height:calc(100vh - 68px)!important}
@media(max-width:700px){#isolated-preview{font-size:10px;gap:8px;padding:8px}#isolated-preview strong{font-size:11px}}
</style><section id="isolated-preview" aria-label="隔离预览"><div><strong>多键盘界面预览 · 模拟设备</strong><div>作品保存在独立预览目录；旋钮、听写、命令键与账户信息均为演示。</div></div><label>模拟连接<select id="preview-device" aria-label="模拟连接">${Object.entries(KEYBOARD_MODELS).map(([id,p])=>`<option value="${id}">${p.name}</option>`).join('')}<option value="disconnected">未连接</option></select></label></section><script src="/preview-controls.js"></script>`;
try {
  await run([path.join(root,'ui/node_modules/vite/bin/vite.js'),'build','--outDir',uiDir,'--emptyOutDir'],path.join(root,'ui'));
  const index=path.join(uiDir,'index.html');
  await writeFile(index,(await readFile(index,'utf8')).replace('<head>',`<head><script>window.__AIR_ISOLATED_PREVIEW__=true;window.__AIR_PREVIEW_ID__=${JSON.stringify(path.basename(dir))}</script>`).replace('<body>',`<body>${banner}`));
  service=await fakeService({after:fn=>cleanup.push(fn)},{freshLibrary:true,firmwareVersion:'1.0.23.6',latestFirmware:'1.0.23.6',firmwareOffline:true,functionKeyAdaptation:false,storedSettings:{autoConnect:false,codexEnabled:false,claudeEnabled:false,codexRotaryDepth:false,airTopRightModule:'keycap'}},{environment,token:randomBytes(32).toString('hex'),uiDir,directory:path.join(dir,'fixture'),keepData:!check});
  if(!(await readFile(path.join(dir,'fixture/fake-hid.mjs'),'utf8')).startsWith(`#!${process.execPath}\n`))throw Error('Fake device fixture missing');
  function json(res,status,value){res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(value));}
  let model='air75-v3',queue=Promise.resolve();
  server=http.createServer(async(req,res)=>{
    res.setHeader('X-Content-Type-Options','nosniff');res.setHeader('X-Frame-Options','DENY');res.setHeader('Referrer-Policy','no-referrer');
    const origin=`http://127.0.0.1:${server.address().port}`;
    if(req.headers.host!==new URL(origin).host)return json(res,403,{ok:false,error:'仅允许本机预览'});
    if(!req.url.startsWith('/')||req.url.startsWith('//'))return json(res,403,{ok:false});
    const pathname=new URL(req.url,origin).pathname;
    try {
      if(pathname==='/preview-controls.js') {
        res.writeHead(200,{'Content-Type':'text/javascript','Cache-Control':'no-store'});
        return res.end(`document.addEventListener('click',event=>{const link=event.target.closest?.('a[href]');if(link&&new URL(link.href,location.href).origin!==location.origin){event.preventDefault();event.stopImmediatePropagation();alert('隔离预览不打开外部驱动或更新页面。');}},true);document.querySelector('#preview-device').addEventListener('change',async event=>{const select=event.target;select.disabled=true;try{const response=await fetch('/api/preview-device',{method:'POST',headers:{'Content-Type':'application/json','X-Air-Token':window.__AIR_TOKEN__},body:JSON.stringify({model:select.value})});if(!response.ok)throw Error();location.reload();}catch{select.disabled=false;alert('模拟连接切换失败，请重试。');}});`);
      }
      let body;
      if(pathname.startsWith('/api/')) {
        if(req.headers['x-air-token']!==token||req.headers.origin&&req.headers.origin!==origin)return json(res,403,{ok:false,error:'预览连接已过期'});
        if(req.method==='POST') {
          let text='';for await(const chunk of req){text+=chunk;if(text.length>8*1024*1024)return json(res,413,{ok:false,error:'文件过大'});}
          body=JSON.parse(text);
        }
        if(pathname==='/api/preview-device'&&req.method==='POST') {
          if(!isKeyboardModel(body?.model)&&body?.model!=='disconnected')return json(res,400,{ok:false});
          const next=body.model;
          const switchDevice=async()=>{
            const disconnected=await service.command({op:'disconnect'});if(!disconnected.ok)throw Error('模拟断开失败');
            await service.configure({present:next!=='disconnected',modelId:next==='disconnected'?model:next,firmwareVersion:getKeyboardProfile(next==='disconnected'?model:next).qualifiedFirmware});
            if(next!=='disconnected'){model=next;const connected=await service.command({op:'connect'});if(!connected.ok)throw Error('模拟连接失败');}
          };
          queue=queue.catch(()=>{}).then(switchDevice);await queue;
          return json(res,200,{ok:true});
        }
        if(!((req.method==='GET'&&['/api/state','/api/layout'].includes(pathname))||(req.method==='POST'&&pathname==='/api/command')))return json(res,403,{ok:false,error:'预览不支持此操作'});
        if(body&&(!allowed.has(body.op)||body.op==='settings'&&(!body.settings||Object.keys(body.settings).some(key=>!settingKeys.has(key)))))return json(res,403,{ok:false,error:'当前为界面预览，此功能未连接实机。'});
      } else if(req.method!=='GET'||!(['/','/index.html','/nuphy-studio.png'].includes(pathname)||/^\/assets\/[\w.-]+$/.test(pathname)))return json(res,404,{ok:false});
      const upstream=await fetch(new URL(pathname,service.url),{method:req.method,headers:{'X-Air-Token':service.token,...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(12000)});
      let bytes=Buffer.from(await upstream.arrayBuffer());
      const contentType=upstream.headers.get('content-type')??'application/octet-stream';
      if(contentType.startsWith('text/html')){const connected=(await service.state()).device.connected;bytes=Buffer.from(bytes.toString().replace(`window.__AIR_TOKEN__=${JSON.stringify(service.token)}`,`window.__AIR_TOKEN__=${JSON.stringify(token)}`).replace(`<option value="${connected?model:'disconnected'}">`,`<option value="${connected?model:'disconnected'}" selected>`));}
      if(pathname==='/api/state'&&upstream.ok){const state=JSON.parse(bytes);state.preview={previewID,isolated:true,simulatedDevice:true,physicalControls:false};state.codex.rotary={status:'off',enabled:false};state.codex.keys.enabled=false;bytes=Buffer.from(JSON.stringify(state));}
      res.writeHead(upstream.status,{'Content-Type':contentType,'Cache-Control':'no-store','Content-Security-Policy':"default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'none'"});res.end(bytes);
    }catch {json(res,400,{ok:false,error:'预览操作未完成，请重试。'});}
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const url=`http://127.0.0.1:${server.address().port}`;
  const nativePreviewRoot=path.join(dir,'native-host');await mkdir(nativePreviewRoot,{mode:0o700});
  await writeFile(path.join(nativePreviewRoot,'native-preview.json'),JSON.stringify({kind:'isolated-native-preview-v1',url,token,previewID}),{mode:0o600});
  const info={url,previewID,nativePreviewRoot,pid:process.pid,servicePid:service.child.pid,dir,dataDir:service.dataDir,uiDir,isolated:true,simulatedDevice:true,nativeHostStarted:false};
  await writeFile(path.join(dir,'PREVIEW.json'),JSON.stringify(info,null,2));
  console.log(JSON.stringify({event:'previewReady',...info}));
  if(check) {
    const headers={'X-Air-Token':token,'Content-Type':'application/json'};
    const request=async(route,body)=>{const response=await fetch(url+route,{headers,...(body?{method:'POST',body:JSON.stringify(body)}:{})});return {status:response.status,value:await response.json()};};
    const state=await request('/api/state');
    if(!state.value.preview?.isolated||state.value.settings.codexRotaryDepth||state.value.codex.keys.enabled)throw Error('Preview isolation state failed');
    for(const op of ['codexRotary','codexKey','codexAction','openPermissionSettings','prepareAppUpdate','confirmFunctionKeyRecovery','claudeHookInstall','audioStart','nativePermissions','unexpectedOperation'])if((await request('/api/command',{op})).status!==403)throw Error('Unsafe preview command accepted');
    if((await request('/api/command',{op:'settings',settings:{codexRotaryDepth:true}})).status!==403)throw Error('Rotary enable accepted');
    if((await request('/api/command',{op:'settings',settings:{brightness:50,codexEnabled:true}})).status!==403)throw Error('Mixed unsafe settings accepted');
    if((await request('/api/command',{op:'settings',settings:{airTopRightModule:'rotary'}})).value.ok!==true)throw Error('Module preview failed');
    for(const device of ['disconnected',...Object.keys(KEYBOARD_MODELS)])if((await request('/api/preview-device',{model:device})).value.ok!==true)throw Error('Device preview failed');
    console.log(JSON.stringify({event:'previewChecksPassed',blockedCommands:12,simulatedSwitches:9,sourceService:true,nativeHostStarted:false}));
    await close();
  }
}catch(error){console.error(error.message);await close();process.exitCode=1;}
