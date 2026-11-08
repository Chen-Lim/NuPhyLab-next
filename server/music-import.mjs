import {readFile,readdir,lstat,mkdir,writeFile,link,unlink} from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {createHash,randomUUID} from 'node:crypto';
import {checkSession,validID,safeMusicDirectories} from './music-library.mjs';
const digest=x=>createHash('sha256').update(x).digest('hex');
const legacyID=x=>'legacy-'+digest(x).slice(0,24);
const rootName='music-works';
async function regular(file,optional=false,maxBytes=48*1024*1024){
 try{const st=await lstat(file);if(!st.isFile()||st.size>maxBytes)throw Error('无法安全读取音乐作品，原文件已保留');return await readFile(file);}
 catch(e){if(optional&&e.code==='ENOENT')return null;throw e;}
}
async function directory(dir,optional=false){
 try{if(!(await lstat(dir)).isDirectory())throw Error('音乐作品目录无效，原文件已保留');}
 catch(e){if(optional&&e.code==='ENOENT')return false;throw e;}return true;
}
async function snapshot(source){
 if(!await directory(source,true))return null;
 const files=new Map();const current=await regular(path.join(source,'music-session.json'),true);
 if(current)files.set('music-session.json',current);
 for(const sub of [rootName,rootName+'/deleted']){
  if(!await directory(path.join(source,sub),true))continue;
  for(const n of (await readdir(path.join(source,sub))).sort())if(n.endsWith('.json')&&validID(n.slice(0,-5)))files.set(sub+'/'+n,await regular(path.join(source,sub,n)));
 }
 if([...files.values()].reduce((n,b)=>n+b.length,0)>256*1024*1024)throw Error('音乐作品过大，自动导入已暂停');
 return files;
}
const fingerprint=files=>files&&digest(JSON.stringify([...files].map(([p,b])=>[p,digest(b)])));
// Hard-link promotion is atomic and exclusive: existing user files are never replaced.
async function exclusive(file,bytes){
 await mkdir(path.dirname(file),{recursive:true});await directory(path.dirname(file));
 const temp=file+'.'+randomUUID()+'.tmp';
 try{await writeFile(temp,bytes,{flag:'wx',mode:0o600});try{await link(temp,file);return true;}catch(e){if(e.code==='EEXIST')return false;throw e;}}
 finally{await unlink(temp).catch(e=>{if(e.code!=='ENOENT')throw e;});}
}
/** Import only musical works/current/deleted. Never import settings, API keys, TCC or lighting data. */
export async function importLegacyMusic(destination,{source=path.join(os.homedir(),'Library/Application Support/NuPhy Lab Music'),afterSnapshot,afterRecord}={}){
 if(!source)return {skipped:true};
 if(path.resolve(source)===path.resolve(destination))return {skipped:true};
 await safeMusicDirectories(destination);
 const marker=path.join(destination,rootName,'formal-import-v1.json');
 if(await regular(marker,true))return {complete:true};
 const journal=path.join(destination,rootName,'formal-import-plan-v1');
 let plan;const savedPlan=await regular(journal,true,256*1024*1024);
 if(savedPlan){plan=JSON.parse(savedPlan);if(plan.version!==1||!Array.isArray(plan.entries))throw Error('音乐导入记录无效，原文件已保留');}
 else {
 const files=await snapshot(source);if(!files||files.size===0)return {empty:true};
 // A live experimental app may be autosaving. Validate a complete stable snapshot before any writes.
 await afterSnapshot?.();if(fingerprint(files)!==fingerprint(await snapshot(source)))throw Error('音乐作品正在保存，请稍后重试导入');
 const records=[];let current=null;
 for(const [name,raw] of files){const value=JSON.parse(raw.toString('utf8'));
  if(name==='music-session.json'){checkSession(value);current=value;continue;}
  if(!validID(value.id)||value.id!==path.basename(name,'.json')||value.session?.projectId!==value.id)throw Error('音乐作品编号不一致，原文件已保留');
  checkSession(value.session);records.push({record:value,deleted:name.includes('/deleted/'),raw});
 }
 if(current){
  const matching=records.find(x=>x.record.id===current.projectId&&!x.deleted&&JSON.stringify(x.record.session)===JSON.stringify(current));
  const deleted=records.some(x=>x.record.id===current.projectId&&x.deleted);
  if(!matching&&!deleted){const id=legacyID('current:'+JSON.stringify(current));const now=(await lstat(path.join(source,'music-session.json'))).mtime.toISOString();const record={id,session:{...current,projectId:id},createdAt:now,updatedAt:now};records.push({record,deleted:false,raw:Buffer.from(JSON.stringify(record))});current=record.session;}
  if(deleted)current=null;
 }

 const entries=[],reservedIDs=new Set();
 for(const {record,deleted,raw} of records){
  let id=record.id;const sub=deleted?rootName+'/deleted':rootName,opposite=deleted?rootName:rootName+'/deleted';
  for(let attempt=0;attempt<100;attempt++){
   const existing=await regular(path.join(destination,sub,id+'.json'),true),other=await regular(path.join(destination,opposite,id+'.json'),true);
   if(!existing&&!other&&!reservedIDs.has(id))break;
   if(existing&&existing.equals(raw)&&id===record.id&&!other&&!reservedIDs.has(id))break;
   id=legacyID(`${deleted}:${record.id}:${digest(raw)}:${attempt}`);
   if(attempt===99)throw Error('音乐作品导入发生冲突，原文件已保留');
  }
  reservedIDs.add(id);entries.push({sourceId:record.id,id,deleted,record:{...record,id,session:{...record.session,projectId:id}}});
 }
 plan={version:1,sourceFingerprint:fingerprint(files),entries,currentId:current?.projectId??null};
 const encoded=Buffer.from(JSON.stringify(plan));if(encoded.length>256*1024*1024)throw Error('音乐作品过大，自动导入已暂停');
 await safeMusicDirectories(destination,true);if(!await exclusive(journal,encoded))plan=JSON.parse(await regular(journal,false,256*1024*1024));
 }
 const ids=new Set();
 if(plan.currentId!==null&&!validID(plan.currentId))throw Error('音乐导入记录无效，原文件已保留');
 for(const e of plan.entries){if(!validID(e.sourceId)||!validID(e.id)||ids.has(e.id)||typeof e.deleted!=='boolean'||e.record?.id!==e.id||e.record?.session?.projectId!==e.id)throw Error('音乐导入记录无效，原文件已保留');checkSession(e.record.session);ids.add(e.id);}
 await mkdir(destination,{recursive:true});await directory(destination);
 for(const dir of [rootName,rootName+'/deleted']){await mkdir(path.join(destination,dir),{recursive:true});await directory(path.join(destination,dir));}
 let imported=0;
 // The durable source→target plan was written before any record. On retry an
 // edited/deleted/restored target still owns that identity; never recreate it.
 for(const entry of plan.entries){
  if(!validID(entry.id))throw Error('作品编号无效');checkSession(entry.record.session);
  const active=path.join(destination,rootName,entry.id+'.json'),deletedFile=path.join(destination,rootName,'deleted',entry.id+'.json');
  if(!await regular(active,true)&&!await regular(deletedFile,true)){
   if(await exclusive(entry.deleted?deletedFile:active,Buffer.from(JSON.stringify(entry.record))))imported++;
  }
  await afterRecord?.(entry);
 }
 let currentImported=false;
 const entry=plan.entries.find(e=>e.sourceId===plan.currentId&&!e.deleted);
 if(entry&&!await regular(path.join(destination,rootName,'deleted',entry.id+'.json'),true)){
  const currentRecord=JSON.parse(await regular(path.join(destination,rootName,entry.id+'.json')));checkSession(currentRecord.session);
  currentImported=await exclusive(path.join(destination,'music-session.json'),Buffer.from(JSON.stringify(currentRecord.session)));
 }
 await exclusive(marker,Buffer.from(JSON.stringify({version:1,sourceFingerprint:plan.sourceFingerprint,imported,currentImported,at:new Date().toISOString()})));
 return {complete:true,imported,currentImported};
}
