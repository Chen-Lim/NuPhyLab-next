import test from 'node:test';
import assert from 'node:assert/strict';
import {KEYBOARD_MODELS,getCanvasCount} from '../shared/keyboard-models.mjs';
import {getLayoutForModel,setLayoutModel,blank} from '../shared/layout.mjs';
import {renderConnectionWake,renderAirConnectionWake} from '../shared/air-connection-wake.mjs';
import {AirConnectionWake,supportsAirConnectionWake} from '../server/connection-wake.mjs';
import {FirmwareChecker,FIRMWARE_MODELS,parseFirmwareManifest} from '../server/firmware.mjs';
import {firmwarePrompt} from '../shared/firmware-onboarding.mjs';
import {validateScene} from '../server/storage.mjs';
import {buildGameBoard} from '../server/engine.mjs';
import {planKeyAdaptation} from '../server/key-adaptation.mjs';
import {createPresets as presets} from '../shared/presets.mjs';
const models=Object.entries(KEYBOARD_MODELS);
const identity=(id,p)=>({connected:true,identified:true,transport:'USB',vendorId:p.vendorId,productId:p.productIds[0],modelId:id,
  ledCount:p.keyCount+p.sideCount,keyLedCount:p.keyCount,protocolReady:true,readOnly:false,connectionSessionId:'model-session',
  capabilities:{perKey:true,readProbeVerified:true,connectionWake:true},armed:true});
for(const [id,p] of models) {
  test(`${id}: exact layout, full canvas, hidden controls and largest key remain separate`,()=>{
    setLayoutModel(id);try {
      const keys=getLayoutForModel(id),indices=keys.map(k=>k.index);
      assert.equal(new Set(indices).size,keys.length);assert.ok(keys.every(k=>k.index<p.keyCount));
      assert.equal(blank().length,p.canvasCount);
      for(const i of p.unmappedIndices)assert.ok(!indices.includes(i));
      assert.equal(keys.length+p.unmappedIndices.length,p.canvasCount);
      const board=buildGameBoard(keys);assert.ok(board);
      for(const preset of presets(keys))assert.equal(preset.colors.length,p.canvasCount);
      const seen=new Set();
      for(let time=25;time<4400;time+=25){const frame=renderConnectionWake(id,time);assert.equal(frame.length,p.canvasCount);
        for(const i of p.unmappedIndices)assert.equal(frame[i],'#000000');
        frame.forEach((c,i)=>{assert.match(c,/^#([0-9a-f]{2})\1\1$/);if(c!=='#000000')seen.add(i);});}
      assert.deepEqual([...seen].sort((a,b)=>a-b),indices.sort((a,b)=>a-b));
      assert.deepEqual(renderConnectionWake(id,4400),blank());
      const art={id:`art-${id}`,name:id,modelId:id,colors:blank(),animation:{effect:'static',direction:'right',speed:4,loop:true}};
      assert.equal(validateScene(art).colors.length,p.canvasCount);
      assert.throws(()=>validateScene({...art,colors:Array(p.canvasCount+1).fill('#000000')}));
    } finally{setLayoutModel('air75-v3');}
  });
  test(`${id}: startup capability requires matching identity and cancels on model replacement`,()=>{
    const device=identity(id,p);assert.equal(supportsAirConnectionWake(device),true);
    for(const invalid of [{productId:0xffff},{ledCount:0},{keyLedCount:p.keyCount+1},{capabilities:{perKey:true}},{readOnly:true}])
      assert.equal(supportsAirConnectionWake({...device,...invalid}),false);
    let now=0;const wake=new AirConnectionWake({now:()=>now});const ticket=wake.begin(device,1);assert.ok(ticket);assert.equal(wake.start(ticket,device,1),true);
    now=2100;assert.equal(wake.frame(device,1).length,getCanvasCount(id));
    const other=models.find(([model])=>model!==id);assert.equal(wake.frame(identity(...other),1),null);assert.equal(wake.active,false);
    assert.equal(wake.begin(device,1),null);wake.absent();assert.ok(wake.begin(device,2));
  });
  test(`${id}: firmware lookup stays model-specific and rejects an unqualified future release`,async()=>{
    const checker=new FirmwareChecker({fetchImpl:async()=>new Response(JSON.stringify({code:200,data:{businessId:p.businessId,type:'1',environment:'prod',status:'0',versionNumber:p.qualifiedFirmware}}))});
    checker.setModel(id);await checker.refresh();let snapshot=checker.snapshot({...identity(id,p),firmwareVersion:p.qualifiedFirmware});
    assert.equal(snapshot.latestSupported,true);assert.equal(snapshot.compatible,true);
    const data={businessId:p.businessId,type:'1',environment:'prod',status:'0',versionNumber:'99.0.1.6'};
    checker.fetchImpl=async()=>new Response(JSON.stringify({code:200,data}));await checker.refresh(true);snapshot=checker.snapshot({...identity(id,p),firmware:p.minimumVersion});
    assert.equal(snapshot.latestSupported,false);assert.equal(snapshot.upgradeRecommended,false);
    assert.equal(firmwarePrompt({device:{...identity(id,p),firmware:p.minimumVersion},firmware:snapshot}),null);
    assert.throws(()=>parseFirmwareManifest({code:200,data:{...data,businessId:'wrong'}},id));checker.close();
  });
  if(p.functionRow)test(`${id}: F-row uses matrix coordinates and excludes all touch/encoder slots`,()=>{
    const size=p.rows*p.columns+p.extraKeys,mac=Array(size).fill(0),win=Array(size).fill(0);
    for(let i=0;i<12;i++){win[i+1]=58+i;mac[i+1]=104+i;}
    const keymap={modelId:id,protocol:`${id==='air75-v3'?'air75':id}-s4-keymap`,mode:0,rows:p.rows,columns:p.columns,
      matrixKeyCount:p.rows*p.columns,keymapKeyCount:size,active:mac,defaults:[mac,win],locationId:123,compatible:true,functionKeyLeaseSupported:true,geometryVerified:true,readOnly:true};
    const result=planKeyAdaptation(keymap,Array.from({length:12},(_,i)=>`F${i+1}`));assert.equal(result.ready.length,12);assert.equal(result.mappings.length,12);
    const invalid={...keymap,active:mac.slice(0,-1)};assert.throws(()=>planKeyAdaptation(invalid,['F1']));
  });
}
test('AIR wake alias remains byte-identical to generalized AIR renderer',()=>{
 for(let t=-1;t<4402;t+=13)assert.deepEqual(renderAirConnectionWake(t),renderConnectionWake('air75-v3',t));
});
