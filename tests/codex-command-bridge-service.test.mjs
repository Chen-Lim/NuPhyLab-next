import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,stat} from 'node:fs/promises';
import path from 'node:path';
import {fakeService,until} from './helpers/fake-service.mjs';

const ok=async(service,body)=>{const r=await service.command(body);assert.equal(r.ok,true,JSON.stringify(r));return r.result;};
const press=async(service,code,id)=>{
  const packet={op:'codexKey',code,gestureId:id,eventSource:'eventTap',eventTime:123.456};
  const down=await service.nativeKey({...packet,phase:'down'});
  await service.nativeKey({...packet,phase:'up'});return down;
};
const effects=async service=>(await service.operations()).filter(row=>['shortcut','codexControl'].includes(row.op));
async function enable(service) {await ok(service,{op:'settings',settings:{codexEnabled:true,codexSelectedPulse:false,codexAmbient:false,quotaSideEnabled:false}});}
test('fresh install uses attested F7-F12 without creating bindings or restarting the target',async t=>{
  const service=await fakeService(t,{freshLibrary:true});await enable(service);
  const state=await until(service.state,value=>value.codex.keys.commandBridge.status==='prepared','AX preparation');
  assert.deepEqual(await effects(service),[],'preparation never performs an action');
  assert.equal(state.codex.keys.commandBridge.activationConfirmed,false);
  for(const action of ['approve','decline','sendPrompt','toggleFastMode']) {
    assert.equal((await service.command({op:'codexAction',action,phase:'down'})).ok,false,'HTTP cannot authorize '+action);
  }
  for(const code of ['F7','F8','F9','F10','F11','F12']) {
    const result=await press(service,code,'fresh:'+code);assert.equal(result.ok,true,JSON.stringify(result));
  }
  const rows=await effects(service);assert.equal(rows.length,7);
  assert.deepEqual(rows.filter(row=>row.op==='codexControl').map(row=>[row.action,row.phase]),[
    ['toggleFastMode','tap'],['approve','tap'],['decline','tap'],['dictation','down'],['dictation','up'],['sendPrompt','tap']]);
  assert.ok(rows.some(row=>row.keyCode===45&&row.modifiers.join(',')==='command'),'F10 remains new chat');
  assert.ok(rows.filter(row=>row.op==='codexControl').every(row=>row.activateTarget===false||row.action==='dictation'));
  await assert.rejects(stat(path.join(path.dirname(service.dataDir),'codex-home/keybindings.json')),{code:'ENOENT'});
});
test('existing bindings remain byte-for-byte unchanged while controls use AX buttons',async t=>{
  const bindings=[{command:'approval.approve',key:null},{command:'composer.submit',key:'Control+Enter'}];
  const service=await fakeService(t,{freshLibrary:true,codexKeybindings:bindings});
  const file=path.join(path.dirname(service.dataDir),'codex-home/keybindings.json'),before=await readFile(file);
  await enable(service);await until(service.state,s=>s.codex.keys.commandBridge.status==='prepared','prepared');
  for(const code of ['F7','F8','F9','F11','F12'])assert.equal((await press(service,code,'direct:'+code)).ok,true);
  assert.deepEqual(await readFile(file),before);
  assert.ok((await effects(service)).every(row=>row.op==='codexControl'),'no default Return/Escape or dedicated chord fallback');
});
test('missing or unavailable controls never fall back to a shortcut, nor request target restart',async t=>{
  const service=await fakeService(t,{freshLibrary:true,codexProcess:{installed:false,running:false},codexControlError:{code:'TARGET_NOT_FOREGROUND'}});await enable(service);
  await until(service.state,s=>s.codex.keys.commandBridge.status==='open-app','missing app');
  for(const code of ['F8','F9','F12'])assert.equal((await press(service,code,'missing:'+code)).ok,false);
  assert.equal((await effects(service)).filter(row=>row.op==='shortcut').length,0);
  await assert.rejects(stat(path.join(path.dirname(service.dataDir),'codex-home/keybindings.json')),{code:'ENOENT'});
});
test('authorization refresh proactively prepares without sending a command',async t=>{
  const service=await fakeService(t,{freshLibrary:true,codexPrepareStatus:'permission-required'});
  await until(service.state,s=>s.codex.keys.commandBridge.status==='permission-required','permission state');
  await service.configure({codexPrepareStatus:'prepared'});
  await ok(service,{op:'nativePermissions',permissions:{inputMonitoring:true,accessibility:true,canPostEvents:true}});
  await until(service.state,s=>s.codex.keys.commandBridge.status==='prepared','grant must prepare without a physical key');
  assert.deepEqual(await effects(service),[]);
});
