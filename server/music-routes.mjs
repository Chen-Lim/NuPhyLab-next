import {MusicLibrary,validID} from './music-library.mjs';
import {importLegacyMusic} from './music-import.mjs';
// Music disk operations have no lighting busy flag, frame cancellation or HID recovery.
export class MusicRoutes {
 constructor(dataDir,{source,importer,bodyTimeoutMs=12000}={}){this.library=new MusicLibrary(dataDir);this.importer=importer??(()=>importLegacyMusic(dataDir,source===undefined?{}:{source}));this.tail=Promise.resolve();this.stopping=false;this.readers=new Set();this.bodyTimeoutMs=bodyTimeoutMs;this.importAttempted=false;this.importWarning=false;this.workChangeClock=0;this.workChanges=new Map();this.pendingWrites=new Set();}
 run(fn){const result=this.tail.catch(()=>{}).then(fn);this.tail=result.catch(()=>{});return result;}
 // Bodies stay outside the disk queue. Remember the lifecycle at admission so
 // an unfinished upload cannot cross deletion/restoration and overwrite it.
 // Requests cannot survive a worker restart; this is not a cross-client ETag.
 noteWorkChange(id){if(!validID(id))return;const epoch=++this.workChangeClock;if(this.pendingWrites.size)this.workChanges.set(id,epoch);}
 finishWrite(ticket){
  this.pendingWrites.delete(ticket);
  let oldest=Infinity;for(const pending of this.pendingWrites)oldest=Math.min(oldest,pending.epoch);
  for(const [id,epoch] of this.workChanges)if(epoch<=oldest)this.workChanges.delete(id);
 }
 async drain(){this.stopping=true;for(const cancel of [...this.readers])cancel();await this.tail;}
 async attemptImport(){this.importAttempted=true;try{await this.importer();this.importWarning=false;}catch{this.importWarning=true;}}
 async readBody(req){return new Promise((resolve,reject)=>{
  const chunks=[];let size=0,done=false;
  const finish=(error)=>{if(done)return;done=true;clearTimeout(timer);this.readers.delete(cancel);req.off('data',data);req.off('end',end);req.off('error',fail);req.off('aborted',abort);if(error){req.once('error',()=>{});req.resume?.();reject(error);}else{try{resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));}catch(e){reject(e);}}};
  const cancel=()=>finish(Error('应用正在退出，请稍后重试')),fail=e=>finish(e),abort=()=>finish(Error('作品请求已中断'));
  const data=chunk=>{size+=chunk.length;if(size>48*1024*1024)finish(Error('演奏文件过大'));else chunks.push(Buffer.from(chunk));};
  const end=()=>finish(),timer=setTimeout(()=>finish(Error('读取作品请求超时，请重试')),this.bodyTimeoutMs);
  this.readers.add(cancel);req.on('data',data);req.once('end',end);req.once('error',fail);req.once('aborted',abort);
 });}
 async handle(req,url){
  const unavailable=()=>({status:503,body:{ok:false,error:'应用正在退出，请稍后重试',importWarning:this.importWarning}});
  if(this.stopping)return unavailable();
  const needsBody=(req.method==='POST'&&['/api/music/session','/api/music/works'].includes(url.pathname))||(req.method==='PUT'&&/^\/api\/music\/works\/[^/]+$/.test(url.pathname));
  const ticket=needsBody?{epoch:this.workChangeClock}:null;
  if(ticket)this.pendingWrites.add(ticket);
  try{
  let value;try{if(needsBody)value=await this.readBody(req);}catch(e){return this.stopping?unavailable():{status:400,body:{ok:false,error:e.message,importWarning:this.importWarning}};}
  if(this.stopping)return unavailable();
  return await this.run(async()=>{
  if(!this.importAttempted)await this.attemptImport();
  const response=(status,body)=>({status,body:{...body,importWarning:this.importWarning}}),ok=value=>response(200,{ok:true,...value});

  try{
   const {pathname:p}=url,m=req.method,l=this.library;
   const save=async current=>{
    if((this.workChanges.get(value?.projectId)??0)>ticket.epoch)return response(409,{ok:false,code:'MUSIC_WORK_CHANGED',error:'作品在保存期间已删除或恢复，请重新打开后再保存'});
    return ok({work:await l.save(value,current)});
   };
   if(p==='/api/music/import'&&m==='POST'){await this.attemptImport();return ok({});}
   if(p==='/api/music/session'&&m==='GET')return ok({session:await l.readCurrent()});
   if(p==='/api/music/session'&&m==='POST')return await save(true);
   if(p==='/api/music/works'&&m==='GET')return ok(await l.list(url.searchParams.get('deleted')==='1'));
   if(p==='/api/music/works'&&m==='POST')return await save(false);
   const match=p.match(/^\/api\/music\/works\/([^/]+)(\/restore)?$/);
   if(match){const id=match[1];if(m==='GET'&&!match[2])return ok({work:await l.get(id)});
    // Invalidate at completion, still inside the disk queue. This also covers
    // uploads admitted while the move is pending and partial disk failures.
    if(m==='DELETE'&&!match[2]){try{return ok({work:await l.remove(id)});}finally{this.noteWorkChange(id);}}
    if(m==='POST'&&match[2]){try{return ok({work:await l.restore(id)});}finally{this.noteWorkChange(id);}}
    if(m==='PUT'&&!match[2]){if(value.projectId!==id)throw Error('作品编号不一致');return await save(false);}}
   return response(405,{ok:false,error:'不支持的作品操作'});
  }catch(e){return response(400,{ok:false,error:e.message});}
 });
  }finally{if(ticket)this.finishWrite(ticket);}
 }
}
