import {createHmac,timingSafeEqual} from 'node:crypto';
import keys from '../shared/trigger-keys.json' with {type:'json'};

const codes=new Set(keys.map(key=>key.code));
const sources=new Set(['eventTap','carbon','local']);
const domain='nuphylab-native-key-v2';

// Each worker receives a fresh key from its native parent. Only the verifier
// retains that key and replay boundary; neither is part of public app state.
export function createNativeKeyVerifier(secret=process.env.AIR_STUDIO_NATIVE_KEY_SECRET) {
  let key;
  if(typeof secret==='string'&&/^[A-Za-z0-9+/]{43}=$/.test(secret)) {
    const decoded=Buffer.from(secret,'base64');
    if(decoded.length===32&&decoded.toString('base64')===secret)key=decoded;
  }
  let lastSequence=0;
  return packet=>{
    if(!key)return false;
    try {
      if(!packet||typeof packet!=='object'||Array.isArray(packet)||packet.op!=='codexKey')return false;
      const {nativeKeySequence:sequence,nativeKeySignature:signature,nativeKeyBindingEpoch:bindingEpoch,code,phase,gestureId,eventSource}=packet;
      if(!Number.isSafeInteger(sequence)||sequence<=lastSequence||sequence<=0
        ||!Number.isSafeInteger(bindingEpoch)||bindingEpoch<0
        ||typeof signature!=='string'||!/^[a-fA-F0-9]{64}$/.test(signature)
        ||!codes.has(code)||!['down','up'].includes(phase)
        ||typeof gestureId!=='string'||gestureId.length<1||gestureId.length>160||!/^[A-Za-z0-9:._-]+$/.test(gestureId)
        ||!sources.has(eventSource))return false;
      const canonical=JSON.stringify([domain,sequence,code,phase,gestureId,eventSource,bindingEpoch]);
      const expected=createHmac('sha256',key).update(canonical).digest();
      if(!timingSafeEqual(expected,Buffer.from(signature,'hex')))return false;
      lastSequence=sequence;
      return true;
    } catch {
      return false;
    }
  };
}
