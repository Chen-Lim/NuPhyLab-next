import test from 'node:test';
import assert from 'node:assert/strict';
import {createHmac,randomBytes} from 'node:crypto';
import {createNativeKeyVerifier} from '../server/native-key-auth.mjs';

const packet=(sequence=1,changes={})=>({op:'codexKey',code:'F8',phase:'down',gestureId:'isolated-host:F8:123456',
  eventSource:'eventTap',nativeKeySequence:sequence,nativeKeyBindingEpoch:0,...changes});
function sign(key,value) {
  const canonical=JSON.stringify(['nuphylab-native-key-v2',value.nativeKeySequence,value.code,value.phase,value.gestureId,value.eventSource,value.nativeKeyBindingEpoch]);
  return {...value,nativeKeySignature:createHmac('sha256',key).update(canonical).digest('hex')};
}

test('missing, malformed and incorrectly sized native secrets fail closed',()=>{
  const key=randomBytes(32),value=sign(key,packet());
  for(const secret of ['',null,42,'invalid',randomBytes(31).toString('base64'),randomBytes(33).toString('base64'),key.toString('base64')+'\n']) {
    assert.equal(createNativeKeyVerifier(secret)(value),false);
  }
});

test('the default verifier reads only its worker-specific environment secret',t=>{
  const previous=process.env.AIR_STUDIO_NATIVE_KEY_SECRET;
  t.after(()=>{if(previous===undefined)delete process.env.AIR_STUDIO_NATIVE_KEY_SECRET;else process.env.AIR_STUDIO_NATIVE_KEY_SECRET=previous;});
  const key=randomBytes(32),value=sign(key,packet());
  delete process.env.AIR_STUDIO_NATIVE_KEY_SECRET;
  assert.equal(createNativeKeyVerifier()(value),false);
  process.env.AIR_STUDIO_NATIVE_KEY_SECRET=key.toString('base64');
  assert.equal(createNativeKeyVerifier()(value),true);
});

test('canonical HMAC verifies down/up from all native sources and accepts only strictly increasing sequences',()=>{
  const key=randomBytes(32),verify=createNativeKeyVerifier(key.toString('base64'));
  assert.equal(verify(sign(key,packet(1))),true);
  assert.equal(verify(sign(key,packet(1))),false,'a captured packet cannot be replayed');
  assert.equal(verify(sign(key,packet(2,{phase:'up'}))),true);
  assert.equal(verify(sign(key,packet(1,{phase:'up'}))),false,'an older authentic packet is still stale');
  assert.equal(verify(sign(key,packet(3,{code:'KeyA',eventSource:'carbon'}))),true);
  assert.equal(verify(sign(key,packet(7,{code:'KeyA',phase:'up',eventSource:'local'}))),true,'sequence gaps are allowed');
});

test('bad signatures, field tampering and failed high sequences do not advance the replay boundary',()=>{
  const key=randomBytes(32),verify=createNativeKeyVerifier(key.toString('base64'));
  const valid=sign(key,packet(2));
  assert.equal(verify({...valid,nativeKeySignature:'0'.repeat(64)}),false);
  for(const changes of [{nativeKeySequence:100},{nativeKeyBindingEpoch:1},{code:'F9'},{phase:'up'},{gestureId:'different-host:F8:123456'},{eventSource:'local'}]) {
    assert.equal(verify({...valid,...changes}),false);
  }
  assert.equal(verify(valid),true,'the authentic lower packet remains usable after rejected attempts');
  assert.equal(verify(sign(key,packet(3,{phase:'up'}))),true);
});

test('authenticated payloads still require valid event formats and safe positive sequence numbers',()=>{
  const key=randomBytes(32);
  const changes=[{op:'codexAction'},{code:'F99'},{code:'F8\n'},{code:null},{phase:'tap'},
    {gestureId:''},{gestureId:'has spaces'},{gestureId:'a'.repeat(161)},{gestureId:null},
    {eventSource:'browser'},{eventSource:null},{nativeKeySequence:0},{nativeKeySequence:-1},
    {nativeKeySequence:1.5},{nativeKeySequence:'1'},{nativeKeySequence:Number.MAX_SAFE_INTEGER+1},
    {nativeKeyBindingEpoch:undefined},{nativeKeyBindingEpoch:null},{nativeKeyBindingEpoch:-1},{nativeKeyBindingEpoch:1.5},
    {nativeKeyBindingEpoch:'0'},{nativeKeyBindingEpoch:Number.MAX_SAFE_INTEGER+1}];
  for(const change of changes) {
    const verify=createNativeKeyVerifier(key.toString('base64'));
    assert.equal(verify(sign(key,packet(1,change))),false);
    assert.equal(verify(sign(key,packet())),true,'a rejected format cannot consume its sequence');
  }
  for(const signature of [undefined,null,0,'a'.repeat(63),'g'.repeat(64),'a'.repeat(65)]) {
    assert.equal(createNativeKeyVerifier(key.toString('base64'))({...packet(),nativeKeySignature:signature}),false);
  }
  for(const value of [null,undefined,[],{},'codexKey'])assert.equal(createNativeKeyVerifier(key.toString('base64'))(value),false);
});

test('binding epochs are authenticated but the pure verifier leaves current-epoch comparison to the caller',()=>{
  const key=randomBytes(32),verify=createNativeKeyVerifier(key.toString('base64'));
  assert.equal(verify(sign(key,packet(1,{nativeKeyBindingEpoch:42}))),true);
  assert.equal(verify(sign(key,packet(2,{nativeKeyBindingEpoch:0}))),true,'a valid old epoch is cryptographically authentic');
  const value=packet(3),legacyCanonical=JSON.stringify(['nuphylab-native-key-v1',value.nativeKeySequence,value.code,value.phase,value.gestureId,value.eventSource]);
  const legacy={...value,nativeKeySignature:createHmac('sha256',key).update(legacyCanonical).digest('hex')};
  assert.equal(verify(legacy),false,'v1 signatures cannot authorize v2 requests');
  assert.equal(verify(sign(key,value)),true,'a rejected legacy signature does not consume the sequence');
});

test('a restarted worker rejects the previous worker key and has an independent sequence boundary',()=>{
  const oldKey=randomBytes(32),newKey=randomBytes(32),oldPacket=sign(oldKey,packet(100));
  assert.equal(createNativeKeyVerifier(oldKey.toString('base64'))(oldPacket),true);
  const newWorker=createNativeKeyVerifier(newKey.toString('base64'));
  assert.equal(newWorker(oldPacket),false);
  assert.equal(newWorker(sign(newKey,packet())),true,'old-worker traffic cannot advance the new boundary');
});
