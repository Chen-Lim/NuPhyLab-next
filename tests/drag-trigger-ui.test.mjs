import test from 'node:test';
import assert from 'node:assert/strict';
import keys from '../shared/drag-trigger-keys.json' with {type:'json'};
import {createVMEnvironment,walkAll,textOf} from './helpers/source-ui-vm.mjs';
for(const language of ['zh-CN','en'])test('single drag trigger settings '+language,async()=>{
 const ui=createVMEnvironment({'lucide-react':new Proxy({},{get:()=>()=>null}),'../../shared/drag-trigger-keys.json':{default:keys},'./i18n':{useLanguage:()=>language}});
 let status={preferences:{enabled:true,trigger:'shift',quality:1,maxDimension:1600},ready:true,busy:false,history:[],issue:''};const calls=[];
 ui.window.webkit={messageHandlers:{dragConvert:{postMessage:async body=>{calls.push(body);if(body.op==='settings')status={...status,preferences:{...body.preferences}};return structuredClone(status);}}}};
 const loaded=await ui.load(new URL('../ui/src/DragConvertLab.tsx',import.meta.url));const mounted=ui.mount(loaded.exports.DragConvertLab);await new Promise(setImmediate);await ui.settle(mounted);
 const select=()=>walkAll(mounted.tree,n=>n.type==='select')[0];
 assert.equal(select().props.value,'shift');assert.equal(walkAll(select(),n=>n.type==='option').length,keys.length);
 assert.ok(!walkAll(select(),n=>n.type==='option').some(n=>n.props.value==='key:53'));
 select().props.onChange({target:{value:'key:0'}});await new Promise(setImmediate);await ui.settle(mounted);
 assert.equal(select().props.value,'key:0');assert.ok(textOf(mounted.tree).includes(language==='en'?'hold A before dragging':'按住 A 再拖起'));
 const request=calls.find(c=>c.op==='settings');assert.equal(request.preferences.trigger,'key:0');assert.equal(request.preferences.quality,1);
 mounted.unmount();const again=ui.mount(loaded.exports.DragConvertLab);await new Promise(setImmediate);await ui.settle(again);assert.equal(walkAll(again.tree,n=>n.type==='select')[0].props.value,'key:0');
 // A layout refresh changes the shown key, never the saved physical binding.
 status={...status,triggerLabels:{'key:0':'Q','key:12':'A'}};
 ui.window.dispatchEvent({type:'focus'});await new Promise(setImmediate);await ui.settle(again);
 const layoutSelect=walkAll(again.tree,n=>n.type==='select')[0];assert.equal(layoutSelect.props.value,'key:0');
 assert.equal(textOf(walkAll(layoutSelect,n=>n.type==='option'&&n.props.value==='key:0')[0]),'Q');
 assert.ok(textOf(again.tree).includes(language==='en'?'hold Q before dragging':'按住 Q 再拖起'));
 if(language==='en')assert.ok(!/[\u4e00-\u9fff]/u.test(textOf(again.tree)));
 for(const labels of [{'key:1':'Σ','key:13':'Σ'},{'key:50':"'",'key:39':"'"}]){
  status={...status,triggerLabels:labels};ui.window.dispatchEvent({type:'focus'});await new Promise(setImmediate);await ui.settle(again);
  const options=walkAll(walkAll(again.tree,n=>n.type==='select')[0],n=>n.type==='option').map(textOf);assert.equal(new Set(options).size,keys.length);
  const key=Object.keys(labels)[0];walkAll(again.tree,n=>n.type==='select')[0].props.onChange({target:{value:key}});await new Promise(setImmediate);await ui.settle(again);
  assert.equal(walkAll(again.tree,n=>n.type==='select')[0].props.value,key);assert.ok(textOf(again.tree).includes(language==='en'?'US':'美式'));
 }
 
 again.unmount();assert.deepEqual(ui.asyncErrors,[]);
});
