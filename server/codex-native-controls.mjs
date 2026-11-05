import {createHash} from 'node:crypto';
import {parseMacShortcut} from './codex-shortcuts.mjs';

// A pure plan only: this module never writes Codex configuration, restarts an
// application, opens settings, posts keys, or connects to an app server.
export const NATIVE_CODEX_CONTROLS = Object.freeze([
  Object.freeze({id:'toggleFastMode',command:'composer.toggleFastMode',preferred:18}),
  Object.freeze({id:'decreaseReasoningEffort',command:'composer.decreaseReasoningEffort',preferred:19}),
  Object.freeze({id:'increaseReasoningEffort',command:'composer.increaseReasoningEffort',preferred:20}),
]);

function shortcut(value) {
  if(typeof value!=='string')return null;
  const parts=value.split('+'),last=parts.pop()?.trim();
  const aliases={printscreen:'F13',scrolllock:'F14',pause:'F15'};
  return parseMacShortcut([...parts,aliases[last?.toLowerCase()]??last].join('+'));
}
function identity(value) {
  const parsed=shortcut(value);
  return parsed?JSON.stringify([parsed.keyCode,[...parsed.modifiers].sort()]):null;
}
function usable(value,blocked) {
  const parsed=shortcut(value);
  return parsed&&/^F(?:1[3-9]|20)$/.test(parsed.code)&&
    parsed.modifiers.some(flag=>flag!=='fn')&&!blocked.has(parsed.keyCode);
}
export function planNativeCodexControls(entries,{blockedCodes=[]}={}) {
  if(!Array.isArray(entries)||entries.length>2048||entries.some(entry=>
    !entry||typeof entry!=='object'||Array.isArray(entry)||typeof entry.command!=='string'||
    !/^[A-Za-z0-9._-]{1,160}$/.test(entry.command)||
    !(entry.key===null||typeof entry.key==='string'&&entry.key.length<=100)||
    (Object.hasOwn(entry,'version')&&entry.version!==1)))throw new Error('Invalid Codex shortcut entries');
  if(!Array.isArray(blockedCodes)||blockedCodes.some(code=>typeof code!=='string'))throw new Error('Invalid physical key bindings');
  const blocked=new Set(blockedCodes.map(code=>shortcut(code)?.keyCode).filter(code=>code!==undefined));
  const proposed=structuredClone(entries),changes=[],controls=[];
  const occupied=()=>proposed.map(entry=>({command:entry.command,identity:identity(entry.key)}));
  const collides=(key,command)=>occupied().some(entry=>entry.command!==command&&entry.identity===identity(key));
  for(const target of NATIVE_CODEX_CONTROLS) {
    const existing=entries.filter(entry=>entry.command===target.command);
    const found=existing.find(entry=>usable(entry.key,blocked)&&!collides(entry.key,target.command));
    if(found) {controls.push({...target,status:'ready',key:found.key});continue;}
    if(existing.some(entry=>entry.key===null)) {
      controls.push({...target,status:'blocked',reason:'explicitly-disabled'});continue;
    }
    const order=[target.preferred,...Array.from({length:8},(_,index)=>13+index).filter(code=>code!==target.preferred)];
    const key=order.map(code=>'Control+Shift+F'+code).find(key=>usable(key,blocked)&&!collides(key,target.command));
    if(!key) {controls.push({...target,status:'blocked',reason:'no-free-dedicated-shortcut'});continue;}
    const change={command:target.command,key,version:1};proposed.push(change);changes.push(change);
    controls.push({...target,status:'add',key});
  }
  const canApply=controls.every(control=>control.status!=='blocked');
  return {controls,canApply,changes:canApply?changes:[],proposedEntries:canApply?proposed:structuredClone(entries),
    sourceSHA256:createHash('sha256').update(JSON.stringify(entries)).digest('hex'),
    requiresFreshCodexStart:canApply&&changes.length>0,
    activationConfirmed:false};
}
