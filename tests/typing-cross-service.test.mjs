import test from 'node:test';
import assert from 'node:assert/strict';
import {fakeService,until} from './helpers/fake-service.mjs';
import {airLayout,blank} from '../shared/layout.mjs';
import {TYPING_KEYS} from '../shared/trigger.mjs';

const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const cross={code:'Enter',count:3,intervalMs:600,effect:'cross',color:'#ffffff',speed:4};
const index=code=>airLayout.find(key=>key.code===code).index;
const keyCode=code=>TYPING_KEYS.find(key=>key.code===code).keyCode;
const isBlack=colors=>colors.every(color=>color==='#000000');
const ok=async(service,body)=>{
  const result=await service.command(body);assert.equal(result.ok,true,JSON.stringify(result));return result.result;
};
async function fixture(t,controls={},settings={}){
  // Every native event below comes from the temporary JSONL helper. No host key
  // injection, running application or physical HID device participates.
  const service=await fakeService(t,controls);
  await ok(service,{op:'settings',settings:{brightness:100,codexEnabled:false,claudeEnabled:false,
    quotaSideEnabled:false,lightDurationMs:0,lightIdleMs:0,...settings}});
  await ok(service,{op:'triggerArm',colors:blank(),trigger:cross});
  return service;
}
const twoOrigins=state=>state.colors[index('Escape')]!=='#000000'&&state.colors[index('ArrowRight')]!=='#000000';

test('global typing monitor accepts every mapped press, overlaps waves and returns black after 800 ms while remaining armed',async t=>{
  const service=await fixture(t);
  const initial=await service.state();
  assert.equal(initial.trigger.monitor,'global');assert.equal(initial.trigger.armed,true);
  assert.equal(initial.trigger.activeWaves,0);assert.ok(isBlack(initial.colors));
  const monitor=(await service.operations()).findLast(operation=>operation.op==='triggerMonitor'&&operation.enabled);
  assert.equal(monitor.mode,'typing');
  assert.deepEqual(monitor.keyCodes,TYPING_KEYS.filter(key=>airLayout.some(position=>position.code===key.code)).map(key=>key.keyCode));
  await ok(service,{op:'triggerKey',code:'Escape'});
  assert.equal((await service.state()).trigger.activeWaves,0,'global ownership must ignore window fallback packets');
  await service.configure({trigger:1,triggerKeyCode:keyCode('Escape')});
  await until(service.state,state=>state.colors[index('Escape')]!=='#000000','global Escape did not light its physical origin');
  const secondAt=performance.now();
  await service.configure({trigger:2,triggerKeyCode:keyCode('ArrowRight')});
  const overlap=await until(service.state,state=>state.trigger.activeWaves===2&&twoOrigins(state),
    'second native key restarted or erased the first wave');
  assert.equal(overlap.trigger.config.code,'Enter','typing keys must be independent of the legacy selected key');
  assert.equal(overlap.colors[83],'#000000');assert.equal(overlap.device.state[10],0);
  const finished=await until(service.state,state=>state.trigger.activeWaves===0&&!state.trigger.flashing&&isBlack(state.colors),
    'cross did not finish its 800 ms tail',1800);
  assert.ok(performance.now()-secondAt>=750,'the second press must retain its own 800 ms lifetime');
  assert.equal(finished.trigger.armed,true);assert.equal(finished.trigger.monitor,'global');
  assert.equal(finished.playback.mode,'trigger');assert.equal(finished.playback.playing,false);
  assert.equal(finished.device.armed,true);assert.equal(finished.device.state[10],0);
  await service.configure({trigger:3,triggerKeyCode:keyCode('ShiftLeft')});
  await until(service.state,state=>state.trigger.activeWaves===1&&state.colors[index('ShiftLeft')]!=='#000000',
    'a modifier or later press could not start another wave');
});

test('window fallback routes actual codes and PrintScreen alias without a second global source',async t=>{
  const service=await fixture(t,{denyMonitor:true});
  assert.equal((await service.state()).trigger.monitor,'window');
  await service.configure({trigger:1,triggerKeyCode:keyCode('Escape')});
  await wait(60);assert.equal((await service.state()).trigger.activeWaves,0,'denied global monitor must not duplicate window typing');
  await ok(service,{op:'triggerKey',code:'Escape'});
  await until(service.state,state=>state.colors[index('Escape')]!=='#000000','window Escape did not start its wave');
  await ok(service,{op:'triggerKey',code:'ArrowRight'});
  await until(service.state,state=>state.trigger.activeWaves===2&&twoOrigins(state),'window presses did not overlap');
  await ok(service,{op:'triggerKey',code:'F13'});
  const print=await until(service.state,state=>state.trigger.activeWaves===3&&state.colors[index('PrintScreen')]!=='#000000',
    'window F13 did not address the physical PrintScreen slot');
  await ok(service,{op:'triggerKey',code:'MediaPlayPause'});
  assert.equal((await service.state()).trigger.activeWaves,print.trigger.activeWaves,'unknown DOM codes must not create a wave');
});

test('explicit cross triggerFire uses req.code instead of the stored legacy code and validates unsupported positions',async t=>{
  const service=await fixture(t);
  await ok(service,{op:'triggerFire',code:'Escape'});
  const first=await until(service.state,state=>state.colors[index('Escape')]!=='#000000','explicit test ignored req.code');
  assert.equal(first.colors[index('Enter')],'#000000');
  assert.equal(first.trigger.config.code,'Enter');
  await ok(service,{op:'triggerFire',code:'ArrowRight'});
  await until(service.state,state=>state.trigger.activeWaves===2&&twoOrigins(state),'explicit tests did not retain independent origins');
  const invalid=await service.command({op:'triggerFire',code:'MediaPlayPause'});
  assert.equal(invalid.ok,false);assert.equal((await service.state()).trigger.armed,true);
  assert.equal((await service.state()).trigger.activeWaves,2);
});

test('a native key queued behind a replacement trigger cannot enter the new trigger generation',async t=>{
  const service=await fixture(t,{recordVisibleWrites:true});
  const cursor=(await service.operations()).length;
  await service.configure({paintDelayMs:800});
  await ok(service,{op:'triggerFire',code:'Escape'});
  await until(service.operations,operations=>{
    const writes=operations.slice(cursor);
    return writes.filter(operation=>operation.op==='paint'&&!isBlack(operation.colors)).length
      > writes.filter(operation=>operation.event==='simulatedVisibleWrite'&&operation.operation==='paint'&&!isBlack(operation.colors)).length;
  },
    'fixture did not hold an old wave frame in flight');
  const replacement=service.command({op:'triggerArm',colors:blank(),trigger:{...cross,color:'#00ff00'}});
  replacement.catch(()=>{});
  await wait(40);
  const held=await service.state();assert.equal(held.trigger.config.color,'#ffffff');
  await service.configure({trigger:1,triggerKeyCode:keyCode('ArrowRight'),paintDelayMs:0});
  const response=await replacement;assert.equal(response.ok,true,JSON.stringify(response));
  await wait(120);
  const after=await service.state();
  assert.equal(after.trigger.config.color,'#00ff00');assert.equal(after.trigger.armed,true);
  assert.equal(after.trigger.activeWaves,0,'a queued key from the old monitor leaked into the replacement generation');
  assert.equal(after.trigger.flashing,false);assert.ok(isBlack(after.colors));
});

test('continuous typing refreshes activity without restarting the total light duration or relighting after expiry',async t=>{
  const service=await fixture(t,{}, {lightDurationMs:1500});
  const initial=await service.state();assert.ok(initial.lightPower.remainingMs>0);
  await wait(220);
  let previous=(await service.state()).lightPower.remainingMs;
  for(let press=1;press<=4;press++){
    await service.configure({trigger:press,triggerKeyCode:keyCode(press%2?'Escape':'ArrowRight')});
    await wait(100);
    const current=await service.state();
    assert.ok(current.lightPower.remainingMs<=previous,'a typing event reset the fixed duration deadline');
    previous=current.lightPower.remainingMs;
  }
  await until(service.state,state=>state.lightPower.sleeping&&state.lightPower.reason==='duration'
    &&state.lightPower.remainingMs===0&&isBlack(state.colors),'typing prevented the total light timer from expiring',1800);
  const cursor=(await service.operations()).length;
  await service.configure({trigger:5,triggerKeyCode:keyCode('Escape')});
  await ok(service,{op:'triggerFire',code:'ArrowRight'});
  await wait(150);
  const asleep=await service.state();
  assert.equal(asleep.lightPower.sleeping,true);assert.equal(asleep.lightPower.remainingMs,0);
  assert.equal(asleep.trigger.armed,true);assert.equal(asleep.trigger.monitor,'global');
  assert.ok(isBlack(asleep.colors));
  assert.ok(!(await service.operations()).slice(cursor).some(operation=>operation.op==='paint'&&!isBlack(operation.colors)),
    'a key or explicit test restarted light output after the total deadline');
});
