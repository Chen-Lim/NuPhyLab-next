import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {fakeService,until} from './helpers/fake-service.mjs';

const durationMs=4400;
const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const art=Array(84).fill('#123456');
const tasks=[{id:'wake-a',title:'Isolated running task',status:'running'},
  {id:'wake-b',title:'Isolated finished task',status:'completed'}];
const identity={transport:'USB',vendorId:0x19f5,productId:0x1028,ledCount:104,keyLedCount:84,
  protocolReady:true,locationId:0x12300000,serialNumber:'isolated-air-wake',
  backupPath:'/isolated/air75-wake/original-lighting.json'};
const settings={autoConnect:false,codexEnabled:false,claudeEnabled:false,quotaSideEnabled:false,
  brightness:27,lightDurationMs:0,lightIdleMs:0,codexSelectedPulse:false,codexAmbient:false,
  codexBrightness:100};
const journalState=[1,72,3,0,1,0,9,75,128,2,65,0,0,0,19,51,68,0,0,0,0,0];
const journalColors=[...Array(84).fill('#204060'),...Array(20).fill('#133344')];
const coloredPendingControl={initialRecoveryPending:true,recordVisibleWrites:true,
  originalLightingState:journalState,originalColors:journalColors,
  originalCustomColors:Array.from({length:84},()=>[0x20,0x40,0x60]).flat(),
  initialLightingState:[21,100,3,0,1,0,255,255,255,3,78,0,0,0,33,85,23,0,0,0,0,0],
  initialColors:[...Array(84).fill('#ff00ff'),...Array(20).fill('#215517')],
  storedSettings:{brightness:100}};
const ok=async(service,body)=>{
  const response=await service.command(body);
  assert.equal(response.ok,true,JSON.stringify(response));
  return response.result;
};
const paints=operations=>operations.filter(operation=>operation.op==='paint');
const gray=color=>/^#([0-9a-f]{2})\1\1$/i.test(color);
const nonblackGray=operation=>operation.op==='paint'&&operation.colors.some(color=>color!=='#000000')
  &&operation.colors.every(gray);
const visibleWrites=operations=>operations.filter(operation=>operation.event==='simulatedVisibleWrite');
function assertQuietTakeover(operations) {
  const writes=operations.filter(operation=>['restore','arm','armConnectionWake','paint','side','nativeLighting'].includes(operation.op));
  assert.equal(writes[0]?.op,'armConnectionWake','a pending journal must not flash its original effect or ordinary arm before quiet takeover');
  const visible=visibleWrites(operations);
  assert.equal(visible[0]?.operation,'armConnectionWake');
  assert.equal(visible[0].reusedJournal,true,'quiet takeover must retain the existing original journal');
  assert.equal(visible[0].quietPreparation,true,'only a complete retained custom palette supports quiet preparation');
  assert.ok(visible[0].previousColors.some(color=>!gray(color)),'exercise an old coloured RAM palette');
  assert.ok(visible[0].colors.every(color=>color==='#000000'),'first committed quiet frame must black out keys and sides');
  assert.equal(visible[0].state[1],100);
  for(const write of visible) {
    assert.ok(write.colors.slice(0,84).every(gray),`${write.operation} introduced coloured keys before wake handoff`);
    assert.equal(write.colors[83],'#000000');
    assert.ok(write.colors.slice(84).every(color=>color==='#000000'),`${write.operation} re-enabled a side LED during startup`);
    assert.equal(write.state[10],0,`${write.operation} re-enabled native side lighting during startup`);
  }
  assert.ok(!writes.some(operation=>operation.op==='side'&&operation.brightness>0),'startup must not issue a lit side command');
}
async function fixture(t,control={}) {
  return fakeService(t,{skipInitialConnect:true,modelId:'air75-v3',firmwareVersion:'1.0.23.6',
    readProbeVerified:true,connectionWake:true,tasks,permissions:{inputMonitoring:true,accessibility:true,canPostEvents:true},
    ...control,outputIdentity:{...identity,...control.outputIdentity},
    storedSettings:{...settings,...control.storedSettings}});
}
const playing=service=>until(service.state,state=>state.connectionWake?.active===true&&state.connectionWake.status==='playing',
  'verified USB Air did not start its connection animation',1800);
const completed=service=>until(service.state,state=>state.connectionWake?.status==='completed',
  'connection animation did not complete after 4400 ms',6000);

test('connection wake requires a fully verified Air USB identity and never upgrades older fixtures',async t=>{
  const cases=[
    ['Kick75',{modelId:'kick75',firmwareVersion:'4.0.18.6',outputIdentity:{productId:0x1026,keyLedCount:80}}],
    ['Bluetooth',{outputIdentity:{transport:'Bluetooth'}}],
    ['missing transport',{outputIdentity:{transport:null}}],
    ['wrong vendor',{outputIdentity:{vendorId:0x1234}}],
    ['wrong product',{outputIdentity:{productId:0x1029}}],
    ['wrong total LED count',{outputIdentity:{ledCount:103}}],
    ['wrong per-key LED count',{outputIdentity:{keyLedCount:83}}],
    ['unidentified',{outputIdentity:{identified:false}}],
    ['protocol not ready',{outputIdentity:{protocolReady:false}}],
    ['read-only',{readOnly:true}],
    ['per-key unsupported',{compatible:false}],
    ['read probe rejected',{readProbeVerified:false}],
    ['read probe missing',{readProbeVerified:undefined}],
    ['startup takeover unavailable',{connectionWake:false}],
    ['startup takeover capability missing',{connectionWake:undefined}],
  ];
  for(const [name,control] of cases) await t.test(name,async sub=>{
    const service=await fixture(sub,control);
    await ok(service,{op:'connect'});
    await wait(90);
    assert.equal((await service.state()).connectionWake?.active,false,name);
    assert.deepEqual((await service.operations()).filter(op=>['arm','armConnectionWake','paint'].includes(op.op)),[],name);
  });
  await t.test('unchanged legacy fake identity',async sub=>{
    const service=await fakeService(sub,{storedSettings:settings});
    await wait(90);
    assert.equal((await service.state()).connectionWake?.active,false);
    assert.deepEqual((await service.operations()).filter(op=>['arm','armConnectionWake','paint'].includes(op.op)),[]);
  });
});

test('quiet wake retains a coloured pending journal, keeps all side LEDs dark, and restores the exact original lighting',async t=>{
  const service=await fixture(t,coloredPendingControl);
  const before=await service.state(),file=path.join(service.dataDir,'library.json');
  const bytes=await readFile(file,'utf8');
  await ok(service,{op:'connect'});
  const active=await playing(service);
  assert.equal(active.device.recoveryPending,true);
  assert.equal(active.device.quietPreparation,true);
  assert.equal(active.device.state[10],0);
  await until(service.operations,ops=>ops.some(nonblackGray),'quiet takeover never displayed its white wave');
  const raw=await ok(service,{op:'readColors'});
  assert.equal(raw.colors.length,104);
  assert.ok(raw.colors.slice(84).every(color=>color==='#000000'));
  const after=await completed(service);
  const operations=await service.operations(),restoreIndex=operations.findIndex(operation=>operation.op==='restore');
  assert.ok(restoreIndex>0,'completion must restore the retained original journal');
  assertQuietTakeover(operations.slice(0,restoreIndex));
  assert.equal(operations.filter(operation=>operation.op==='armConnectionWake').length,1);
  assert.equal(after.device.armed,false);
  assert.equal(after.device.recoveryPending,false);
  assert.deepEqual(after.device.state,journalState);
  assert.deepEqual((await ok(service,{op:'readColors'})).colors,journalColors);
  assert.deepEqual(after.settings,before.settings);
  assert.deepEqual(after.scenes,before.scenes);
  assert.equal(await readFile(file,'utf8'),bytes);
});

test('preview cancels a quiet wake and returns the retained original side lighting to the new artwork',async t=>{
  const service=await fixture(t,coloredPendingControl);
  const before=await service.state(),file=path.join(service.dataDir,'library.json');
  const bytes=await readFile(file,'utf8');
  await ok(service,{op:'connect'});
  await playing(service);
  const startup=await until(service.operations,ops=>ops.some(nonblackGray),'quiet takeover did not display a white frame');
  assertQuietTakeover(startup);
  await ok(service,{op:'preview',colors:art});
  const after=await until(service.state,state=>!state.connectionWake.active&&state.playback.mode==='static'
    &&JSON.stringify(state.device.state.slice(9,17))===JSON.stringify(journalState.slice(9,17)),
  'new artwork did not regain the original side lighting',1600);
  assert.equal(after.connectionWake.status,'cancelled');
  assert.equal(after.device.armed,true);
  assert.equal(after.device.recoveryPending,true);
  assert.deepEqual(after.colors,art);
  const raw=await ok(service,{op:'readColors'});
  assert.deepEqual(raw.colors.slice(0,84),art);
  assert.deepEqual(raw.colors.slice(84),journalColors.slice(84));
  const operations=await service.operations();
  assert.equal(operations.filter(operation=>operation.op==='armConnectionWake').length,1);
  assert.equal(operations.filter(operation=>operation.op==='restore').length,0,'preview must retain the artwork lighting lease');
  assert.deepEqual(after.settings,before.settings);
  assert.deepEqual(after.scenes,before.scenes);
  assert.equal(await readFile(file,'utf8'),bytes);
});

test('startup capture without a complete retained custom palette reports that preparation was not quiet',async t=>{
  const cases=[
    ['first capture',{recordVisibleWrites:true,originalLightingState:journalState,originalColors:journalColors},false],
    ['state-only pending journal',{...coloredPendingControl,originalCustomColors:undefined},true],
  ];
  for(const [name,control,reusedJournal] of cases) await t.test(name,async sub=>{
    const service=await fixture(sub,control);
    await ok(service,{op:'connect'});
    const active=await playing(service);
    assert.equal(active.device.capabilities.connectionWake,true);
    assert.equal(active.device.quietPreparation,false,'transaction support must not promise a flash-free initial palette capture');
    const preparation=visibleWrites(await service.operations()).find(operation=>operation.operation==='armConnectionWake');
    assert.equal(preparation.quietPreparation,false);
    assert.equal(preparation.reusedJournal,reusedJournal);
    // This completed-transaction snapshot verifies the service handoff only.
    // The JSONL double cannot establish physical visibility during capture.
    assert.ok(preparation.colors.every(color=>color==='#000000'));
    assert.equal(active.device.state[10],0);
    await ok(service,{op:'stop'});
    assert.equal((await service.state()).device.armed,false);
  });
});

test('older helpers without startup takeover capability retain ordinary AI output without attempting a wake',async t=>{
  for(const connectionWake of [undefined,false]) await t.test(String(connectionWake),async sub=>{
    const service=await fixture(sub,{connectionWake,storedSettings:{codexEnabled:true,brightness:100}});
    await ok(service,{op:'connect'});
    const after=await until(service.state,state=>state.codex.lighting.ownsOutput,'ordinary AI output failed with the older helper');
    assert.equal(after.connectionWake.active,false);
    assert.equal(after.connectionWake.status,'idle');
    assert.equal(after.colors[1],'#304ffe');
    const operations=await service.operations();
    assert.ok(operations.some(operation=>operation.op==='arm'));
    assert.ok(operations.some(operation=>operation.op==='paint'));
    assert.equal(operations.filter(operation=>operation.op==='armConnectionWake').length,0);
  });
});

test('verified Air wake sends full white at 27% global brightness, retains shortcuts and hands output to AI',async t=>{
  const service=await fixture(t,{storedSettings:{codexEnabled:true,codexKeyAdaptation:true}});
  await ok(service,{op:'saveScene',scene:{name:'Keep original artwork',colors:art,animation:{effect:'static'}}});
  const before=await service.state();
  const stored=await readFile(path.join(service.dataDir,'library.json'),'utf8');
  const start=performance.now();
  await ok(service,{op:'connect'});
  assert.ok(performance.now()-start<1800,'connect must not wait for the 4400 ms animation');
  const active=await playing(service);
  const playingAt=performance.now();
  assert.equal(active.connectionWake.status,'playing');
  assert.equal(active.connectionWake.durationMs,durationMs);
  assert.ok(active.connectionWake.elapsedMs>=0&&active.connectionWake.elapsedMs<durationMs);
  assert.equal(active.connectionWake.sessionId,active.device.connectionSessionId);
  assert.equal(active.codex.keys.enabled,true,'USB startup must retain enabled task shortcuts');
  assert.equal(active.codex.lighting.ownsOutput,false,'AI RGB does not own the white startup frame');
  await ok(service,{op:'codexKey',code:'F2'});
  assert.equal((await service.operations()).filter(op=>op.op==='shortcut').at(-1).threadId,'wake-b');
  assert.equal((await service.state()).connectionWake.active,true);
  const output=await until(service.operations,ops=>paints(ops).some(op=>op.colors.includes('#ffffff')),
    'startup wave never reached unscaled full white',1600);
  for(const frame of paints(output)) {
    assert.equal(frame.colors.length,84);
    assert.ok(frame.colors.every(gray),'startup must have equal RGB channels without AI overlays');
    assert.equal(frame.colors[83],'#000000','unmapped Air slot must remain black');
  }
  await wait(Math.max(0,2600-active.connectionWake.elapsedMs-(performance.now()-playingAt)));
  const midpoint=await service.state();
  assert.equal(midpoint.connectionWake.active,true,'half-speed choreography must still run after 2.2 seconds');
  assert.ok(midpoint.connectionWake.elapsedMs>=2300&&midpoint.connectionWake.elapsedMs<durationMs);
  assert.ok(midpoint.colors.every(gray),'diagonal stage must also exclude AI colours');
  const after=await completed(service);
  assert.ok(performance.now()-start>=4250,'startup completed before its 4400 ms choreography');
  assert.equal(after.connectionWake.active,false);
  assert.equal(after.connectionWake.elapsedMs,durationMs);
  assert.equal(after.playback.mode,'agent');
  assert.equal(after.device.armed,true);
  assert.equal(after.codex.keys.enabled,true);
  assert.equal(after.codex.lighting.ownsOutput,true);
  assert.equal(after.colors[1],'#0d1545');
  assert.equal(after.colors[2],'#004515');
  assert.equal(after.colors[20],'#000000','completion must not inject the default heart');
  assert.deepEqual(after.settings,before.settings);
  assert.deepEqual(after.scenes,before.scenes);
  assert.equal(await readFile(path.join(service.dataDir,'library.json'),'utf8'),stored);
});

test('without an ordinary output the completed wake restores the keyboard and releases lighting ownership',async t=>{
  const service=await fixture(t);
  const before=await service.state();
  await ok(service,{op:'connect'});
  await playing(service);
  const active=await service.state(),original=active.device.state;
  assert.equal(active.device.armed,true);
  const after=await completed(service);
  assert.equal(after.connectionWake.active,false);
  assert.equal(after.device.armed,false);
  assert.equal(after.device.recoveryPending,false);
  assert.equal(after.playback.mode,'idle');
  assert.equal(after.playback.playing,false);
  assert.equal(after.device.state[0],1,'original native lighting mode must be restored');
  assert.equal(after.device.state[1],100,'original native brightness must be restored');
  assert.notDeepEqual(after.device.state,original,'startup custom-lighting mode must be released');
  assert.deepEqual(after.settings,before.settings);
  assert.deepEqual(after.scenes,before.scenes);
  assert.ok((await service.operations()).some(op=>op.op==='restore'));
  const count=paints(await service.operations()).length;
  await ok(service,{op:'connect'});
  await wait(120);
  assert.equal((await service.state()).connectionWake.status,'completed');
  assert.equal(paints(await service.operations()).length,count,'same-session reconnect cannot replay completion');
});

test('an unplugged trigger remains disabled after reconnection wake and native lighting is fully restored',async t=>{
  const service=await fixture(t,{storedSettings:{autoConnect:true,brightness:100}});
  await playing(service);
  await ok(service,{op:'stop'});
  const original=(await service.state()).device.state;
  await ok(service,{op:'triggerArm',colors:art,trigger:{count:3,intervalMs:200}});
  const armed=await service.state();
  assert.equal(armed.trigger.armed,true);
  assert.equal(armed.trigger.monitor,'global');
  await service.configure({disconnect:1,present:false});
  const removed=await until(service.state,state=>!state.device.connected&&!state.trigger.armed
    &&state.trigger.monitor==='off','physical removal did not disable the trigger');
  assert.equal(removed.playback.mode,'trigger','exercise the retained mode without a live trigger');
  const cursor=(await service.operations()).length;
  await service.configure({present:true});
  const active=await playing(service);
  assert.equal(active.trigger.armed,false);
  assert.equal(active.trigger.monitor,'off');
  const after=await completed(service);
  assert.equal(after.device.armed,false,'inactive trigger mode must not retain startup lighting ownership');
  assert.equal(after.device.recoveryPending,false);
  assert.deepEqual(after.device.state,original,'completion must restore the entire original native lighting configuration');
  assert.equal(after.trigger.armed,false);
  assert.equal(after.trigger.monitor,'off');
  await wait(120);
  assert.equal((await service.state()).device.armed,false);
  assert.ok(!(await service.operations()).slice(cursor).some(operation=>operation.op==='triggerMonitor'&&operation.enabled===true),
    'physical reinsertion must not restart a disabled trigger listener');
});

const outputIntents=[
  ['preview',async service=>ok(service,{op:'preview',colors:art}),'static'],
  ['play',async service=>ok(service,{op:'play',colors:art,animation:{effect:'static'}}),'static'],
  ['gameStart',async service=>ok(service,{op:'gameStart',gameType:'snake',speed:1}),'game'],
  ['triggerArm',async service=>ok(service,{op:'triggerArm',colors:art,trigger:{count:3,intervalMs:200}}),'trigger'],
  ['audioStart',async service=>{
    await ok(service,{op:'audioInventory',systemSupported:true,devices:[],microphonePermission:true});
    return ok(service,{op:'audioStart'});
  },'audio'],
  ['restore',async service=>ok(service,{op:'restore'}),'idle'],
  ['stop',async service=>ok(service,{op:'stop'}),'idle'],
];
for(const [name,intent,mode] of outputIntents) test(`${name} cancels startup promptly and repeated connect cannot replay it`,async t=>{
  const service=await fixture(t,{storedSettings:{brightness:100}});
  await ok(service,{op:'connect'});
  const first=await playing(service);
  await until(service.operations,ops=>ops.some(nonblackGray),'startup did not commit a visible frame');
  const start=performance.now();
  await intent(service);
  assert.ok(performance.now()-start<1800,`${name} was blocked by startup duration`);
  let state=await service.state();
  assert.equal(state.connectionWake.active,false);
  assert.equal(state.connectionWake.status,'cancelled');
  assert.equal(state.playback.mode,mode);
  const cursor=(await service.operations()).length;
  await ok(service,{op:'connect'});
  await wait(150);
  state=await service.state();
  assert.equal(state.connectionWake.active,false);
  assert.equal(state.connectionWake.status,'cancelled');
  assert.equal(state.connectionWake.sessionId,first.connectionWake.sessionId);
  assert.equal(state.playback.mode,mode);
  assert.ok(!(await service.operations()).slice(cursor).some(nonblackGray),'cancelled startup frame escaped into the new output');
  if(['preview','play'].includes(name))assert.ok(state.colors.every(color=>color==='#123456'));
});

test('changing brightness during an idle startup cancels it and releases the last white frame',async t=>{
  const service=await fixture(t);
  await ok(service,{op:'connect'});
  const initial=await playing(service);
  await until(service.operations,ops=>ops.some(nonblackGray),'startup did not send a white wave');
  await ok(service,{op:'settings',settings:{brightness:61}});
  const after=await until(service.state,state=>!state.connectionWake.active&&!state.device.armed,
    'brightness edit left the idle keyboard leased with its white startup frame',1600);
  assert.equal(after.connectionWake.status,'cancelled');
  assert.equal(after.settings.brightness,61);
  assert.equal(after.playback.mode,'idle');
  assert.equal(after.device.recoveryPending,false);
  assert.equal(after.device.state[0],1);
  assert.ok(after.colors.every(color=>color==='#000000'));
  const cursor=(await service.operations()).length;
  await ok(service,{op:'connect'});
  await wait(150);
  assert.equal((await service.state()).connectionWake.sessionId,initial.connectionWake.sessionId);
  assert.equal((await service.state()).connectionWake.active,false);
  assert.equal(paints((await service.operations()).slice(cursor)).length,0,'brightness edit must consume this startup');
});

test('ordinary artwork settings cancel reconnection wake and return its original side lighting',async t=>{
  const cases=[
    ['static brightness','static',{brightness:61},'#0b2034'],
    ['paused outputColorProfile','paused',{outputColorProfile:null},'#123456'],
  ];
  for(const [name,mode,changes,expectedColor] of cases) await t.test(name,async sub=>{
    const service=await fixture(sub,{...coloredPendingControl,storedSettings:{autoConnect:true,brightness:100,quotaSideEnabled:false}});
    await ok(service,{op:'connect'});
    await playing(service);
    await ok(service,{op:'preview',colors:art});
    if(mode==='paused') {
      await ok(service,{op:'play',colors:art,animation:{effect:'frames',speed:4,loop:true,
        frames:[{colors:art,duration:1000}]}});
      await wait(50);
      await ok(service,{op:'pause'});
    }
    const before=await service.state();
    assert.equal(before.playback.mode,mode);
    assert.deepEqual(before.device.state.slice(9,17),journalState.slice(9,17));
    await service.configure({disconnect:1,present:false});
    await until(service.state,state=>!state.device.connected,'ordinary artwork keyboard did not detach');
    const cursor=(await service.operations()).length;
    await service.configure({present:true});
    const active=await playing(service);
    await until(service.operations,ops=>ops.slice(cursor).some(nonblackGray),'reconnection startup never displayed its white wave');
    await ok(service,{op:'settings',settings:changes});
    const after=await until(service.state,state=>!state.connectionWake.active&&state.playback.mode===mode
      &&state.colors.every(color=>color===expectedColor)
      &&JSON.stringify(state.device.state.slice(9,17))===JSON.stringify(journalState.slice(9,17)),
    'settings returned ordinary artwork without returning its original side lighting',1600);
    assert.equal(after.connectionWake.status,'cancelled');
    assert.equal(after.settings.quotaSideEnabled,false,'quota must not mask missing side handoff');
    assert.equal(after.device.armed,true);
    assert.equal(after.device.recoveryPending,true);
    assert.deepEqual((await ok(service,{op:'readColors'})).colors.slice(84),journalColors.slice(84));
    await ok(service,{op:'connect'});
    await wait(120);
    const repeated=await service.state();
    assert.equal(repeated.connectionWake.active,false);
    assert.equal(repeated.connectionWake.sessionId,active.connectionWake.sessionId);
    assert.equal(repeated.playback.mode,mode);
    assert.deepEqual(repeated.device.state.slice(9,17),journalState.slice(9,17));
    assert.ok(repeated.colors.every(color=>color===expectedColor));
  });
});

test('gamePause during a reconnection startup cancels white output and retains the paused game',async t=>{
  const service=await fixture(t,{storedSettings:{autoConnect:true,brightness:100}});
  await playing(service);
  await ok(service,{op:'gameStart',gameType:'snake',speed:1});
  await ok(service,{op:'gamePause',paused:true});
  const before=await service.state();
  await service.configure({disconnect:1,present:false});
  await until(service.state,state=>!state.device.connected,'paused game keyboard did not detach');
  const cursor=(await service.operations()).length;
  await service.configure({present:true});
  const active=await playing(service);
  await until(service.operations,ops=>ops.slice(cursor).some(nonblackGray),'reconnection did not send its white wave');
  await ok(service,{op:'gamePause',paused:true});
  const after=await until(service.state,state=>!state.connectionWake.active
    &&JSON.stringify(state.colors)===JSON.stringify(before.colors),
  'game pause left the connection animation on the keyboard',1600);
  assert.equal(after.connectionWake.status,'cancelled');
  assert.equal(after.game.status,'paused');
  assert.equal(after.playback.mode,'game');
  assert.equal(after.playback.playing,false);
  await ok(service,{op:'connect'});
  await wait(150);
  const repeated=await service.state();
  assert.equal(repeated.connectionWake.active,false);
  assert.equal(repeated.connectionWake.sessionId,active.connectionWake.sessionId);
  assert.deepEqual(repeated.colors,before.colors);
});

test('pause during an animation reconnection wake preserves the new paused intent and frozen artwork position',async t=>{
  const service=await fixture(t,{storedSettings:{autoConnect:true,brightness:100}});
  await playing(service);
  const playedAt=performance.now();
  await ok(service,{op:'play',colors:art,animation:{effect:'frames',speed:4,loop:true,
    frames:[{colors:art,duration:1000},{colors:Array(84).fill('#abcdef'),duration:1000}]}});
  await wait(220);
  await service.configure({disconnect:1,present:false});
  await until(service.state,state=>!state.device.connected,'animation keyboard did not detach');
  const removedAt=performance.now(),cursor=(await service.operations()).length;
  await service.configure({present:true});
  const active=await playing(service);
  await until(service.operations,ops=>ops.slice(cursor).some(nonblackGray),'reconnection did not display a white wave');
  await ok(service,{op:'pause'});
  const paused=await until(service.state,state=>!state.connectionWake.active&&state.playback.mode==='paused'
    &&state.colors.every(color=>color==='#123456'),
  'deferred reconnect playback overwrote pause or its frozen artwork position',1600);
  assert.equal(paused.connectionWake.status,'cancelled');
  assert.equal(paused.playback.playing,false);
  assert.ok(paused.playback.elapsed>=150,'pause must retain the artwork progress before unplugging');
  assert.ok(paused.playback.elapsed<removedAt-playedAt+250,'pause must exclude the reconnect and startup wait');
  await ok(service,{op:'connect'});
  await wait(180);
  const repeated=await service.state();
  assert.equal(repeated.connectionWake.sessionId,active.connectionWake.sessionId);
  assert.equal(repeated.connectionWake.active,false);
  assert.equal(repeated.playback.mode,'paused');
  assert.equal(repeated.playback.playing,false);
  assert.equal(repeated.playback.elapsed,paused.playback.elapsed);
  assert.deepEqual(repeated.colors,art);
});

test('slow USB acknowledgements still commit the terminal black frame before restoring native lighting',async t=>{
  const service=await fixture(t,{paintDelayMs:120,storedSettings:{brightness:100}});
  await ok(service,{op:'connect'});
  await playing(service);
  const after=await completed(service);
  assert.equal(after.device.armed,false);
  assert.equal(after.device.recoveryPending,false);
  const operations=await service.operations();
  const restoreIndex=operations.findIndex(operation=>operation.op==='restore');
  assert.ok(restoreIndex>0,'completed idle startup must restore the original lighting');
  const beforeRestore=paints(operations.slice(0,restoreIndex));
  assert.ok(beforeRestore.length>2&&beforeRestore.some(nonblackGray),'slow fixture must commit visible startup frames');
  assert.ok(beforeRestore.at(-1).colors.every(color=>color==='#000000'),
    'a tail-frame acknowledgement crossing 4400 ms must not skip the terminal black frame');
  assert.equal(beforeRestore.at(-1).colors.length,84);
});

test('physical unplug cancels stale frames and the next automatic insertion wakes once before resuming artwork',async t=>{
  const service=await fixture(t);
  await ok(service,{op:'connect'});
  const first=await playing(service);
  await ok(service,{op:'preview',colors:art});
  await ok(service,{op:'settings',settings:{autoConnect:true,brightness:100}});
  await service.configure({disconnect:1,present:false});
  await until(service.state,state=>!state.device.connected,'fake USB removal was not observed');
  assert.equal((await service.state()).connectionWake.active,false);
  const removedCursor=(await service.operations()).length;
  await wait(140);
  assert.equal(paints((await service.operations()).slice(removedCursor)).length,0,'detached device received an old frame');
  await service.configure({present:true});
  const inserted=await playing(service);
  assert.notEqual(inserted.connectionWake.sessionId,first.connectionWake.sessionId);
  await ok(service,{op:'connect'});
  assert.equal((await service.state()).connectionWake.sessionId,inserted.connectionWake.sessionId);
  const after=await completed(service);
  assert.equal(after.playback.mode,'static');
  assert.deepEqual(after.colors,art,'previous artwork must resume after the startup animation');
  assert.equal(after.device.armed,true);
  const cursor=(await service.operations()).length;
  await wait(150);
  assert.ok(!(await service.operations()).slice(cursor).some(nonblackGray),'completed insertion replayed on status/tick');
});

test('removing USB during startup stops its frame producer and the next physical connection may play again',async t=>{
  const service=await fixture(t);
  await ok(service,{op:'connect'});
  const first=await playing(service);
  await until(service.operations,ops=>ops.some(nonblackGray),'first startup frame was not sent');
  await service.configure({disconnect:1,present:false});
  const removed=await until(service.state,state=>!state.device.connected&&state.connectionWake?.active===false,
    'USB removal did not cancel the active startup producer');
  assert.equal(removed.connectionWake.status,'cancelled');
  const cursor=(await service.operations()).length;
  await wait(150);
  assert.equal(paints((await service.operations()).slice(cursor)).length,0);
  await service.configure({present:true});
  await ok(service,{op:'connect'});
  const next=await playing(service);
  assert.notEqual(next.connectionWake.sessionId,first.connectionWake.sessionId);
  await ok(service,{op:'stop'});
});

test('helper restart cancels startup without treating its replacement as a physical insertion',async t=>{
  const service=await fixture(t,{recordHelperPid:true,storedSettings:{autoConnect:true}});
  const initial=await playing(service);
  const spawned=(await service.operations()).find(op=>op.event==='simulatedHelperStarted');
  assert.ok(Number.isInteger(spawned?.pid)&&spawned.pid>0);
  process.kill(spawned.pid,'SIGKILL');
  await until(service.state,state=>state.connectionWake?.active===false,
    'helper failure did not cancel startup');
  const operations=await until(service.operations,ops=>ops.filter(op=>op.event==='simulatedHelperStarted').length===2,
    'service did not replace its isolated helper',5000);
  const replacement=operations.findLastIndex(op=>op.event==='simulatedHelperStarted');
  await until(service.state,state=>state.device.connected,'replacement helper did not reconnect',5000);
  await ok(service,{op:'connect'});
  await wait(200);
  const after=await service.state();
  assert.equal(after.connectionWake.active,false);
  assert.equal(after.connectionWake.status,'cancelled');
  assert.equal(after.connectionWake.sessionId,initial.connectionWake.sessionId);
  assert.equal(paints((await service.operations()).slice(replacement)).length,0,
    'helper replacement must not replay a consumed physical insertion');
});

test('a startup paint failure retains normal rollback and consumes that insertion without retrying the effect',async t=>{
  const service=await fixture(t,{failPaint:1});
  // The first frame may be acknowledged inside connect or on the first tick.
  // Both paths must retain the existing hardware rollback rather than replay.
  await service.command({op:'connect'});
  await until(service.operations,ops=>ops.some(op=>op.event==='simulatedRollback'),
    'fake startup failure did not execute the existing restore path');
  const failed=await until(service.state,state=>state.connectionWake?.active===false,
    'failed startup retained its frame producer');
  assert.equal(failed.device.connected,true);
  assert.equal(failed.device.armed,false);
  assert.equal(failed.device.recoveryPending,false);
  assert.equal(failed.device.state[0],1);
  assert.equal(failed.connectionWake.status,'cancelled');
  const cursor=(await service.operations()).length;
  await ok(service,{op:'connect'});
  await wait(150);
  assert.equal((await service.state()).connectionWake.active,false);
  assert.deepEqual((await service.operations()).slice(cursor).filter(op=>['arm','paint'].includes(op.op)),[],
    'same insertion may not retry a failed animation');
});

test('verified native wake rollback resumes enabled AI once after a safe status confirmation',async t=>{
  const service=await fixture(t,{...coloredPendingControl,connectionWakeFailure:'verifiedRollback',
    storedSettings:{codexEnabled:true,brightness:100}});
  const failed=await service.command({op:'connect'});
  assert.equal(failed.ok,false,'the failed introduction must retain its own error result');
  const after=await until(service.state,state=>state.device.armed&&state.codex.lighting.ownsOutput,
    'verified rollback did not return the enabled AI mode to ordinary output',1800);
  assert.equal(after.connectionWake.status,'cancelled');
  assert.equal(after.connectionWake.active,false);
  assert.equal(after.connectionWake.elapsedMs,0);
  assert.equal(after.settings.codexEnabled,true);
  assert.equal(after.playback.mode,'agent');
  assert.equal(after.playback.lastError,failed.error,'AI fallback must retain the introduction failure');
  assert.equal(after.colors[1],'#304ffe');
  assert.equal(after.colors[2],'#00ff4c');
  const operations=await service.operations();
  const rollbackIndex=operations.findIndex(operation=>operation.event==='simulatedWakeRollback');
  const safeStatusIndex=operations.findIndex((operation,index)=>index>rollbackIndex
    &&operation.event==='simulatedWakeFailureStatus'&&operation.connected&&!operation.armed
    &&!operation.recoveryPending&&!operation.needsRestore);
  const armIndex=operations.findIndex(operation=>operation.op==='arm');
  assert.ok(rollbackIndex>=0&&safeStatusIndex>rollbackIndex&&armIndex>safeStatusIndex,
    'ordinary AI arm must follow explicit rollback and an independent safe status snapshot');
  assert.equal(operations[rollbackIndex].verified,true);
  assert.ok(!operations.slice(rollbackIndex+1,armIndex).some(operation=>
    ['armConnectionWake','paint','side','nativeLighting','restore'].includes(operation.op)),
  'no lighting mutation may precede the confirmed safe ordinary arm');
  assert.equal(operations.filter(operation=>operation.op==='armConnectionWake').length,1);
  assert.equal(operations.filter(operation=>operation.op==='arm').length,1);
  await wait(180);
  assert.equal((await service.state()).playback.lastError,failed.error);
  await ok(service,{op:'connect'});
  await wait(120);
  const repeated=await service.operations();
  assert.equal(repeated.filter(operation=>operation.op==='armConnectionWake').length,1,'AI recovery must not retry the failed wake');
  assert.equal(repeated.filter(operation=>operation.op==='arm').length,1,'ordinary recovery must arm once');
});

test('uncertain or still-pending native wake rollback cannot automatically rearm AI',async t=>{
  for(const connectionWakeFailure of ['unverifiedRollback','pendingAfterVerifiedRollback'])
    await t.test(connectionWakeFailure,async sub=>{
      const service=await fixture(sub,{...coloredPendingControl,connectionWakeFailure,
        storedSettings:{codexEnabled:true,brightness:100}});
      const failed=await service.command({op:'connect'});
      assert.equal(failed.ok,false);
      await wait(250);
      const after=await service.state(),operations=await service.operations();
      assert.equal(after.connectionWake.status,'cancelled');
      assert.equal(after.connectionWake.active,false);
      assert.equal(after.connectionWake.elapsedMs,0);
      assert.equal(after.device.connected,true);
      assert.equal(after.device.armed,false);
      assert.equal(after.device.recoveryPending,true);
      assert.equal(after.device.needsRestore,true);
      assert.equal(after.settings.codexEnabled,true,'preserve user intent while recovery is blocked');
      assert.equal(after.codex.lighting.ownsOutput,false);
      assert.equal(after.playback.lastError,failed.error);
      assert.equal(operations.filter(operation=>operation.op==='armConnectionWake').length,1);
      assert.deepEqual(operations.filter(operation=>['arm','paint','side','nativeLighting','restore'].includes(operation.op)),[],
        'uncertain recovery must not perform a new lighting mutation');
      const rollback=operations.find(operation=>operation.event==='simulatedWakeRollback');
      assert.equal(rollback.armed,false);
      assert.equal(rollback.recoveryPending,true);
      assert.equal(rollback.verified,connectionWakeFailure==='pendingAfterVerifiedRollback');
      assert.ok(operations.some(operation=>operation.event==='simulatedWakeFailureStatus'
        &&operation.recoveryPending&&!operation.armed),'the retained journal must remain visible in status');
    });
});
