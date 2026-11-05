import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,readFile,writeFile,rm,stat,utimes,symlink} from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {CodexCommandBridge,freshCodexProcess} from '../server/codex-command-bridge.mjs';
import {describeAction} from '../server/codex.mjs';

async function fixture(t,entries) {
  const root=await mkdtemp(path.join(os.tmpdir(),'ncb-')),home=path.join(root,'codex'),backups=path.join(root,'backups');
  t.after(()=>rm(root,{recursive:true,force:true}));await mkdir(home);
  const file=path.join(home,'keybindings.json');
  if(entries)await writeFile(file,JSON.stringify(entries));
  let process={installed:true,running:true,processCount:1,pid:42,launchedAtMs:1,version:'26.1027.61615'},enabled=true;
  const bridge=new CodexCommandBridge({codexHome:home,backupDir:backups,processInfo:async()=>process,enabled:()=>enabled});
  return {bridge,file,home,root,backups,setProcess:value=>{process={...process,...value};},disable:()=>{enabled=false;},
    restart:async()=>{const time=Date.now()-5000;await utimes(file,time/1000,time/1000);process={...process,pid:43,launchedAtMs:time+1000};}};
}
test('empty new-user profile is automatically prepared, blocked until restart, and resolves dedicated controls afterwards',async t=>{
  const f=await fixture(t);const first=await f.bridge.inspect();
  assert.equal(first.status,'restart-required');assert.equal(first.actions.approve.available,false);
  const entries=JSON.parse(await readFile(f.file,'utf8'));assert.equal(entries.length,3);
  assert.ok(entries.every(entry=>/F1[3-8]$/.test(entry.key)));
  await assert.rejects(f.bridge.resolve(describeAction('approve')),/重新打开/);
  await f.restart();const ready=await f.bridge.inspect();
  assert.equal(ready.status,'prepared');assert.equal(ready.activationConfirmed,false);
  for(const id of ['approve','decline','sendPrompt']) {
    const shortcut=await f.bridge.resolve(describeAction(id));
    assert.equal(shortcut.expectedPID,43);assert.match(shortcut.code,/^F1[3-8]$/);
  }
});
test('preserves normal bindings, unknown fields and conflicting chords while appending a safe alternative',async t=>{
  const existing=[{command:'approval.approve',key:'Enter',version:1,custom:{keep:true}},
    {command:'custom.command',key:'Shift+Ctrl+F13',version:1}];
  const f=await fixture(t,existing);await f.bridge.inspect();
  const entries=JSON.parse(await readFile(f.file,'utf8'));assert.deepEqual(entries.slice(0,2),existing);
  const safe=entries.find(row=>row.command==='approval.approve'&&row.key!=='Enter');
  assert.ok(safe);assert.notEqual(safe.key,'Control+Shift+F13');
  await f.restart();assert.equal((await f.bridge.resolve(describeAction('approve'))).accelerator,safe.key);
});
test('explicitly disabled approval remains disabled while other commands can be prepared',async t=>{
  const f=await fixture(t,[{command:'approval.approve',key:null}]);await f.bridge.inspect();await f.restart();
  const status=await f.bridge.inspect();assert.equal(status.status,'partial');assert.equal(status.actions.approve.available,false);
  assert.equal(status.actions.decline.available,true);await assert.rejects(f.bridge.resolve(describeAction('approve')),/停用/);
  assert.equal(JSON.parse(await readFile(f.file,'utf8')).filter(row=>row.command==='approval.approve').length,1);
});
test('repeat polling and application restart preserve file bytes and mtime',async t=>{
  const f=await fixture(t);await f.bridge.inspect();await f.restart();await f.bridge.inspect();
  const before=await readFile(f.file),mtime=(await stat(f.file)).mtimeMs;
  await Promise.all(Array.from({length:6},()=>f.bridge.inspect()));
  assert.deepEqual(await readFile(f.file),before);assert.equal((await stat(f.file)).mtimeMs,mtime);
});
test('malformed JSON and symlink leave original data untouched and report failure',async t=>{
  const f=await fixture(t);await writeFile(f.file,'broken');
  assert.equal((await f.bridge.inspect()).status,'error');assert.equal(await readFile(f.file,'utf8'),'broken');
  await rm(f.file);const target=path.join(f.root,'outside.json');await writeFile(target,'[]');await symlink(target,f.file);
  assert.equal((await f.bridge.inspect()).status,'error');assert.equal(await readFile(target,'utf8'),'[]');
});
test('disabled mode and missing app do not create user config',async t=>{
  const f=await fixture(t);f.setProcess({installed:false,running:false});
  assert.equal((await f.bridge.inspect()).status,'missing-app');await assert.rejects(stat(f.file),{code:'ENOENT'});
  f.disable();assert.equal((await f.bridge.inspect()).status,'idle');await assert.rejects(stat(f.file),{code:'ENOENT'});
});
test('new file revision invalidates readiness until a new process launch',async t=>{
  const f=await fixture(t);await f.bridge.inspect();await f.restart();await f.bridge.inspect();
  const rows=JSON.parse(await readFile(f.file,'utf8'));rows.push({command:'custom.command',key:'Command+Y'});
  await writeFile(f.file,JSON.stringify(rows));await assert.rejects(f.bridge.resolve(describeAction('sendPrompt')),/重新打开/);
});
test('process proof rejects ambiguous, unknown, old and future launches',()=>{
  const process={installed:true,running:true,processCount:1,pid:12,launchedAtMs:200};
  assert.equal(freshCodexProcess(process,100,300),true);
  for(const patch of [{processCount:2},{pid:0},{running:false},{launchedAtMs:50},{launchedAtMs:5000},{launchedAtMs:null}])
    assert.equal(freshCodexProcess({...process,...patch},100,300),false);
});
test('closing drains a pending status query and later polls cannot start another process probe',async t=>{
  const f=await fixture(t);let probes=0,release;
  f.bridge.processInfo=async()=>{probes++;return new Promise(resolve=>{release=()=>resolve({installed:false});});};
  const pending=f.bridge.inspect();const closing=f.bridge.close();release();await closing;await pending;
  await f.bridge.inspect();await assert.rejects(f.bridge.availability(describeAction('approve')),/暂停/);
  assert.equal(probes,1);
});
