import test from 'node:test';
import assert from 'node:assert/strict';
import {LightingPower,DEFAULT_LIGHT_TIME_MS,lightingTimerDeadline} from '../shared/lighting-power.mjs';
import {CodexLights} from '../shared/codex-lighting.mjs';
import {Store,defaultSettings,validateSettings} from '../server/storage.mjs';
import {translate} from '../shared/i18n.mjs';

test('new installs use one hour; saved custom and unlimited timers are preserved',()=>{
 const settings=new Store('/unused').data.settings;
 assert.equal(DEFAULT_LIGHT_TIME_MS,3600000);
 assert.equal(settings.lightDurationMs,3600000);assert.equal(settings.lightIdleMs,3600000);
 const legacy=validateSettings({codexEnabled:true,codexAutoOffMs:1000});
 assert.equal(legacy.lightDurationMs,3600000);assert.equal(legacy.lightIdleMs,3600000);
 const existing=validateSettings({lightDurationMs:0,lightIdleMs:900000});
 assert.equal(existing.lightDurationMs,0);assert.equal(existing.lightIdleMs,900000);
});
test('default Codex lights remain on at 6 and 59 minutes, switch off at 60, and wake for a full hour',()=>{
 let now=0;const power=new LightingPower(()=>now),lights=new CodexLights(()=>now);
 const settings={...defaultSettings,codexAutoOffMs:1000,codexHintMs:1000};
 for(const minute of [6,59]){
  now=minute*60000;assert.equal(power.update(settings).sleeping,false);
  assert.notEqual(lights.render(Array(84).fill('#000000'),[{id:'a',status:'running'}],settings)[1],'#000000');
 }
 now=3600000;assert.equal(power.update(settings).reason,'duration');
 power.wake();assert.equal(power.update(settings).remainingMs,3600000);
 now+=3599999;assert.equal(power.update(settings).sleeping,false);
 now++;assert.equal(power.update(settings).sleeping,true);
});

test('light timer stays off after duration and only explicit wake restarts it',()=>{
 let now=0;const power=new LightingPower(()=>now),settings={lightDurationMs:1000,lightIdleMs:3000};
 now=999;assert.equal(power.update(settings).sleeping,false);
 now=1000;assert.equal(power.update(settings).reason,'duration');
 now=2000;power.activity();assert.equal(power.update(settings).sleeping,true);
 power.wake();assert.equal(power.update(settings).remainingMs,1000);
});
test('two-hour duration and one-hour idle remain awake for minutes and idle activity cannot extend the duration',()=>{
 let now=0;const power=new LightingPower(()=>now),settings={lightDurationMs:7200000,lightIdleMs:3600000};
 for(const at of [60000,300000,3599999]){now=at;power.observeSystemIdle(at);assert.equal(power.update(settings).sleeping,false);}
 now=3600000;const asleep=power.update(settings);
 assert.equal(asleep.reason,'idle');assert.equal(asleep.remainingMs,3600000);
 now+=10000;power.activity();const resumed=power.update(settings);
 assert.equal(resumed.sleeping,false);assert.equal(resumed.remainingMs,3590000,'app activity keeps the original duration deadline');
 now=7200000;assert.equal(power.update(settings).reason,'duration');
 power.activity();assert.equal(power.update(settings).reason,'duration','typing cannot renew an expired session');
 power.wake();assert.equal(power.update(settings).remainingMs,7200000);
});
test('system activity resumes idle lights without renewing duration, which also expires while idle',()=>{
 let now=0;const power=new LightingPower(()=>now),settings={lightDurationMs:7200000,lightIdleMs:3600000};
 now=3600000;assert.equal(power.update(settings).reason,'idle');
 now=3601000;power.observeSystemIdle(10);assert.equal(power.update(settings).sleeping,false);
 assert.equal(power.snapshot(settings).remainingMs,3599000);
 now=7200000;assert.equal(power.update(settings).reason,'duration');
 power.observeSystemIdle(0);assert.equal(power.update(settings).reason,'duration');
 const idle=new LightingPower(()=>now);now+=3600000;assert.equal(idle.update(settings).reason,'idle');
 now+=3600000;assert.equal(idle.update(settings).reason,'duration','the fixed deadline expires even without an intervening wake');
});
test('timer diagnostics report the earliest independent deadline, including one or both timers disabled',()=>{
 const state={sleeping:false,reason:null,remainingMs:7200000,idleMs:60000};
 assert.deepEqual(lightingTimerDeadline(state,{lightDurationMs:7200000,lightIdleMs:3600000}),
  {durationRemainingMs:7200000,idleRemainingMs:3540000,nextSleepInMs:3540000,nextSleepReason:'idle'});
 assert.equal(lightingTimerDeadline(state,{lightDurationMs:7200000,lightIdleMs:0}).nextSleepReason,'duration');
 assert.equal(lightingTimerDeadline(state,{lightDurationMs:0,lightIdleMs:3600000}).nextSleepReason,'idle');
 assert.equal(lightingTimerDeadline(state,{lightDurationMs:0,lightIdleMs:0}).nextSleepInMs,null);
 assert.equal(lightingTimerDeadline({...state,sleeping:true,reason:'duration'},{lightDurationMs:7200000,lightIdleMs:3600000}).nextSleepReason,'duration');
});
test('idle sleep uses system and app activity without polling extending the timeout',()=>{
 let now=0;const power=new LightingPower(()=>now),settings={lightIdleMs:1000};
 now=1000;power.observeSystemIdle(1500);assert.equal(power.update(settings).reason,'idle');
 now=2000;power.observeSystemIdle(2500);assert.equal(power.update(settings).sleeping,true);
 power.observeSystemIdle(100);assert.equal(power.update(settings).sleeping,false);
 now=3000;assert.equal(power.update(settings).sleeping,true);
 power.activity();assert.equal(power.update(settings).sleeping,false);
 now=5000;assert.equal(power.update({}).sleeping,false);
});
test('Codex changes wake idle lights; an unchanged task list does not',()=>{
 let now=0;const power=new LightingPower(()=>now);power.observeCodex('working');
 now=1000;power.update({lightIdleMs:1000});power.observeCodex('working');assert.equal(power.sleeping,true);
 power.observeCodex('completed');assert.equal(power.sleeping,false);
});
test('Codex rendering remains lit until the global power controller sleeps',()=>{
 let now=0;const lights=new CodexLights(()=>now),power=new LightingPower(()=>now),slots=[{id:'a',status:'completed'}];
 const settings={lightDurationMs:5000,codexAutoOffMs:1000,codexHintMs:1000,codexAmbient:true};lights.select('a');
 const frame=()=>power.update(settings).sleeping?Array(84).fill('#000000'):lights.render(Array(84).fill('#112233'),slots,settings);
 now=1500;assert.notEqual(frame()[7],'#000000');assert.notEqual(frame()[1],'#000000');
 now=5000;assert.ok(frame().every(c=>c==='#000000'));
 power.wake();assert.notEqual(frame()[7],'#000000');assert.notEqual(frame()[1],'#000000');
});
test('timing and language settings validate independently and preserve existing settings',()=>{
 const settings=validateSettings({language:'en',lightDurationMs:86400000,lightIdleMs:1500,codexAutoOffMs:45000,codexHintMs:2000});
 assert.equal(validateSettings({language:'zh-CN'},settings).codexHintMs,2000);
 for(const patch of [{language:'de'},{lightDurationMs:999},{lightIdleMs:-1},{lightDurationMs:86400001},{codexHintMs:0},{codexHintMs:600001},{codexAutoOffMs:1.5}])assert.throws(()=>validateSettings(patch));
});
test('translation preserves values, placeholder user content, and Chinese selection',()=>{
 assert.equal(translate('en','已导入 3 个作品'),'Imported 3 scenes');
 assert.equal(translate('en','打开作品 我的小心意'),'Open scene 我的小心意');
 assert.equal(translate('en','不支持的设置项：abc'),'Unsupported setting: abc');
 assert.equal(translate('zh-CN','设备'),'设备');assert.equal(translate('en','设备'),'Device');
 assert.equal(translate('en',null),null);assert.equal(translate('en',42),42);
});
