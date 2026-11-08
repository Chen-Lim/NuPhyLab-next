import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {Readable,PassThrough} from 'node:stream';
import {MusicRoutes} from '../server/music-routes.mjs';
import {initialSession,demoEvents} from '../ui/src/music/model.ts';
const project=()=>({...initialSession(),projectId:randomUUID(),name:'Synthetic race fixture',events:demoEvents()});
async function setup(t,options={}){
 const dir=await mkdtemp(path.join(tmpdir(),'music-race-'));const routes=new MusicRoutes(dir,{source:null,...options});
 t.after(async()=>{await routes.drain();await rm(dir,{recursive:true,force:true});});
 const invoke=(suffix,method='GET',value)=>{const req=Readable.from(value?[Buffer.from(JSON.stringify(value))]:[]);req.method=method;return routes.handle(req,new URL('http://127.0.0.1/api/music/'+suffix));};
 const delayed=(suffix,method,value)=>{const body=JSON.stringify(value),req=new PassThrough();req.method=method;const result=routes.handle(req,new URL('http://127.0.0.1/api/music/'+suffix));req.write(body.slice(0,1));return {result,finish:()=>req.end(body.slice(1)),req};};
 return {routes,invoke,delayed};
}
const bytes=async(routes,id)=>Promise.all([routes.library.file(id),routes.library.file(id)+'.meta',routes.library.current].map(p=>readFile(p)));
for(const [label,method,target] of [['current','POST',()=> 'session'],['library','POST',()=> 'works'],['rename','PUT',id=>'works/'+id]]){
 test(`late ${label} write across delete/restore is rejected without changing any restored bytes`,{timeout:5000},async t=>{
  const {routes,invoke,delayed}=await setup(t);const s=project();assert.equal((await invoke('session','POST',s)).status,200);
  const old=delayed(target(s.projectId),method,{...s,events:[]});
  assert.equal((await invoke('session')).status,200,'an incomplete upload must not block reads');
  assert.equal((await invoke('works/'+s.projectId,'DELETE')).status,200);
  assert.equal((await invoke('works/'+s.projectId+'/restore','POST')).status,200);
  const before=await bytes(routes,s.projectId);old.finish();const response=await old.result;
  assert.equal(response.status,409);assert.equal(response.body.code,'MUSIC_WORK_CHANGED');assert.deepEqual(await bytes(routes,s.projectId),before);
  assert.deepEqual((await invoke('session')).body.session,s);
  const fresh={...s,name:'Fresh after restore'};assert.equal((await invoke('session','POST',fresh)).status,200);assert.deepEqual((await routes.library.get(s.projectId)).session,fresh);
  assert.equal(routes.pendingWrites.size,0);assert.equal(routes.workChanges.size,0);
 });
}
test('a body admitted while deleted cannot overwrite a subsequent restore',{timeout:5000},async t=>{
 const {routes,invoke,delayed}=await setup(t),s=project();await invoke('session','POST',s);await invoke('works/'+s.projectId,'DELETE');
 const old=delayed('session','POST',{...s,events:[]});await invoke('works/'+s.projectId+'/restore','POST');old.finish();assert.equal((await old.result).status,409);assert.deepEqual((await routes.library.get(s.projectId)).session,s);
});
for(const fail of [false,true])test(`an upload admitted during an in-progress restore is rejected (late failure=${fail})`,{timeout:5000},async t=>{
 const {routes,invoke,delayed}=await setup(t),s=project();await invoke('session','POST',s);await invoke('works/'+s.projectId,'DELETE');
 let enter,release;const entered=new Promise(r=>enter=r),gate=new Promise(r=>release=r),restore=routes.library.restore.bind(routes.library);
 routes.library.restore=async id=>{enter();await gate;const value=await restore(id);if(fail)throw Error('synthetic metadata completion failure');return value;};
 const restoring=invoke('works/'+s.projectId+'/restore','POST');await entered;
 const old=delayed('session','POST',{...s,events:[]});old.finish();release();assert.equal((await restoring).status,fail?400:200);
 assert.equal((await old.result).status,409);assert.deepEqual((await routes.library.get(s.projectId)).session,s);assert.equal(routes.pendingWrites.size,0);assert.equal(routes.workChanges.size,0);
});
test('deleting another work does not reject an unrelated slow upload',{timeout:5000},async t=>{
 const {routes,invoke,delayed}=await setup(t),a=project(),b=project();await invoke('session','POST',a);await invoke('works','POST',b);
 const next={...a,name:'Unrelated edit'},upload=delayed('session','POST',next);await invoke('works/'+b.projectId,'DELETE');await invoke('works/'+b.projectId+'/restore','POST');upload.finish();assert.equal((await upload.result).status,200);assert.deepEqual((await routes.library.get(a.projectId)).session,next);assert.equal(routes.workChanges.size,0);
});
test('two pending generations stay guarded until both complete',{timeout:5000},async t=>{
 const {routes,invoke,delayed}=await setup(t),s=project();await invoke('session','POST',s);const first=delayed('session','POST',{...s,events:[]});await invoke('works/'+s.projectId,'DELETE');const second=delayed('works','POST',{...s,events:[]});await invoke('works/'+s.projectId+'/restore','POST');
 first.finish();assert.equal((await first.result).status,409);second.finish();assert.equal((await second.result).status,409);assert.deepEqual((await routes.library.get(s.projectId)).session,s);assert.equal(routes.pendingWrites.size,0);assert.equal(routes.workChanges.size,0);
});
test('shutdown cancels slow uploads without waiting for their bodies or writing late data',{timeout:5000},async t=>{
 const {routes,invoke,delayed}=await setup(t),s=project();await invoke('session','POST',s);const old=delayed('session','POST',{...s,events:[]});await invoke('works/'+s.projectId,'DELETE');await invoke('works/'+s.projectId+'/restore','POST');
 await routes.drain();assert.equal((await old.result).status,503);old.finish();assert.deepEqual((await routes.library.get(s.projectId)).session,s);assert.equal(routes.pendingWrites.size,0);assert.equal(routes.workChanges.size,0);
});
test('body timeout cleans up guards without writing late data',{timeout:5000},async t=>{
 const {routes,invoke,delayed}=await setup(t,{bodyTimeoutMs:100}),s=project();await invoke('session','POST',s);const old=delayed('session','POST',{...s,events:[]});assert.equal((await old.result).status,400);old.finish();assert.deepEqual((await routes.library.get(s.projectId)).session,s);assert.equal(routes.pendingWrites.size,0);assert.equal(routes.workChanges.size,0);
});
