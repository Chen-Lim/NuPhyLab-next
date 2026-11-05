import test from 'node:test';
import assert from 'node:assert/strict';
import {CodexAccessibilityBridge} from '../server/codex-accessibility-bridge.mjs';

test('preparation is coalesced, reports no action success, and needs no keybinding path',async()=>{
  let calls=0,finish;
  const bridge=new CodexAccessibilityBridge({prepare:()=>{calls++;return new Promise(resolve=>finish=resolve);}});
  const one=bridge.inspect(),two=bridge.inspect();
  await Promise.resolve();assert.equal(calls,1);
  finish({status:'warming'});await Promise.all([one,two]);
  assert.equal(bridge.snapshot().status,'warming');
  assert.equal(bridge.snapshot().message,'','normal warmup is not a key-press retry notification');
  assert.equal(bridge.snapshot().activationConfirmed,false);
  assert.deepEqual(bridge.snapshot().actions,{});
});
test('closing waits for preparation and never exposes a late result as ready',async()=>{
  let finish;
  const bridge=new CodexAccessibilityBridge({prepare:()=>new Promise(resolve=>finish=resolve)});
  const pending=bridge.inspect();await Promise.resolve();const closed=bridge.close();
  finish({status:'prepared'});await Promise.all([pending,closed]);
  assert.equal(bridge.snapshot().status,'idle');
  assert.equal((await bridge.inspect()).status,'idle');
});
test('denied, failed and changed-process preparation can recover without changing a configuration',async()=>{
  let status='permission-required';
  const bridge=new CodexAccessibilityBridge({prepare:async()=>{if(status==='error')throw Error('private metadata');return {status};}});
  assert.equal((await bridge.inspect()).status,'permission-required');
  status='error';assert.equal((await bridge.inspect()).status,'unavailable');
  assert.doesNotMatch(JSON.stringify(bridge.snapshot()),/private metadata/);
  status='prepared';assert.equal((await bridge.inspect()).status,'prepared');
  status='open-app';assert.equal((await bridge.inspect()).status,'open-app');
  status='warming';assert.equal((await bridge.inspect()).status,'warming');
});
