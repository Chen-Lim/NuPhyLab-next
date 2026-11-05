import test from 'node:test';
import assert from 'node:assert/strict';
import {fakeService,until} from './helpers/fake-service.mjs';
import {KEYBOARD_MODELS,getCanvasCount} from '../shared/keyboard-models.mjs';
import {getLayoutForModel} from '../shared/layout.mjs';
import {KeyAdaptation,planKeyAdaptation} from '../server/key-adaptation.mjs';
import {SnakeGame} from '../server/engine.mjs';
import {PongGame} from '../server/games/pong.mjs';
import {MemoryGame} from '../server/games/memory.mjs';
import {WhackGame} from '../server/games/whack.mjs';
const entries=Object.entries(KEYBOARD_MODELS);
const settings={autoConnect:false,codexEnabled:false,claudeEnabled:false,quotaSideEnabled:false,brightness:100,lightDurationMs:0,lightIdleMs:0};
const ok=async(s,body)=>{const r=await s.command(body);assert.equal(r.ok,true,JSON.stringify(r));return r.result;};
for(const [modelId,p] of entries) {
 test(`${modelId}: real service plays full canvas, isolates saved works, and restores after wake`,async t=>{
  const s=await fakeService(t,{skipInitialConnect:true,freshLibrary:true,modelId,firmwareVersion:p.qualifiedFirmware,
   storedSettings:settings,connectionWake:true,readProbeVerified:true,recordVisibleWrites:true,
   outputIdentity:{transport:'USB',vendorId:p.vendorId,productId:p.productIds[0],keyLedCount:p.keyCount,ledCount:p.keyCount+p.sideCount,protocolReady:true}});
  await ok(s,{op:'connect'});
  await until(s.state,v=>v.connectionWake?.active===true,'startup did not become active');
  await until(s.state,v=>v.connectionWake?.status==='completed','startup did not finish',6500);
  let state=await s.state();assert.equal(state.device.recoveryPending,false);
  assert.equal(state.colors.length,p.canvasCount);assert.deepEqual(state.layout,getLayoutForModel(modelId));
  const colors=Array(p.canvasCount).fill('#234567');for(const i of p.unmappedIndices)colors[i]='#000000';
  await ok(s,{op:'play',colors,animation:{effect:'static'}});
  const raw=await ok(s,{op:'readColors'});assert.deepEqual(raw.colors.slice(0,p.keyCount),colors.slice(0,p.keyCount));
  const saved=(await ok(s,{op:'saveScene',scene:{name:'model canvas',colors,animation:{effect:'static'}}})).savedScene;
  assert.equal(saved.modelId,modelId);assert.equal(saved.colors.length,p.canvasCount);
  const other=entries.find(([id])=>id!==modelId)[0];
  assert.equal((await s.command({op:'saveScene',scene:{...saved,modelId:other}})).ok,false);
  await ok(s,{op:'restore'});assert.equal((await s.state()).device.recoveryPending,false);
  const writes=(await s.operations()).filter(v=>v.op==='paint');assert.ok(writes.length>2);
  assert.ok(writes.every(v=>v.colors.length===p.keyCount||v.colors.length===p.canvasCount));
  for(const Game of [SnakeGame,PongGame,MemoryGame,WhackGame]) {
   const game=new Game(()=>.4,getLayoutForModel(modelId));game.start();
   assert.equal(game.render().length,getCanvasCount(modelId),`${Game.name} must use its own model even with another global canvas`);
  }
 });
}
function nodeMap() {
 const p=KEYBOARD_MODELS['node75-lp'],size=p.rows*p.columns+p.extraKeys;
 const active=Array(size).fill(0),win=Array(size).fill(0),factory=[105,106,32262,32263,32264,32278,172,174,171,168,170,169];
 factory.forEach((v,i)=>{active[i+1]=v;win[i+1]=58+i;});active.splice(96,5,32283,168,171,170,169);win.splice(96,5,32283,168,171,170,169);
 return {modelId:'node75-lp',protocol:'node75-lp-s4-keymap',firmwareVersion:p.qualifiedFirmware,geometryVerified:true,readOnly:true,
  mode:0,locationId:1,matrixKeyCount:96,keymapKeyCount:101,active,defaults:[active.slice(),win],functionKeyLeaseSupported:true};
}
test('NODE touch gestures cannot become commands before a verified firmware lease',async()=>{
 const keys=Array.from({length:12},(_,i)=>`F${i+1}`),map=nodeMap();
 const before=planKeyAdaptation(map,keys);assert.deepEqual(before.shared,['F9','F10','F11','F12']);
 assert.deepEqual(before.unsupported,['F4','F9','F10','F11','F12']);
 assert.ok(before.mappings.every(m=>![0xc000000b5,0xc000000e2,0xc000000ea,0xc000000e9].includes(m.HIDKeyboardModifierMappingSrc)));
 const original=structuredClone(map),calls=[];let owned=false;
 const hardware={child:{},state:{connected:true},async request(op,body){calls.push({op,body});
  if(op==='permissions')return {inputMonitoring:true,accessibility:true,canPostEvents:true};
  if(op==='readKeymap')return {...structuredClone(map),functionKeyLease:owned};
  if(op==='prepareFunctionKey') {assert.deepEqual(body.keys,keys);owned=true;for(const i of [4,9,10,11,12])map.active[i]=57+i;return {leased:true,verified:true,keys:['F4','F9','F10','F11','F12']};}
  if(op==='restoreFunctionKey'){map.active=original.active.slice();owned=false;return {restored:true,verified:true};}
  return {verified:true};
 }};
 const a=new KeyAdaptation(hardware),state=await a.sync({enabled:true,active:true,connected:true,bindings:keys});
 assert.equal(state.status,'ready');assert.equal(state.mapped,12);assert.deepEqual(state.boardAdapted,['F4','F9','F10','F11','F12']);
 const os=calls.find(v=>v.op==='adaptKeys');assert.equal(os.body.mappings.length,7);
 assert.ok(os.body.mappings.every(m=>![0xc000000b5,0xc000000e2,0xc000000ea,0xc000000e9].includes(m.HIDKeyboardModifierMappingSrc)));
 assert.deepEqual(map.active.slice(96),original.active.slice(96));await a.release();assert.deepEqual(map.active,original.active);
});
