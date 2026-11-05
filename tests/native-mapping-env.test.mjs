import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,writeFile,rm,chmod} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {Hardware} from '../server/hardware.mjs';
import {takeMappingCommitSecret,sanitizeMappingCommitSecret} from '../server/native-mapping-env.mjs';
import {helperProcessEnvironment,takeNativeHoldEnvironment} from '../server/native-hold-env.mjs';
import {createHmac} from 'node:crypto';
const deriveMappingCommitSecret=key=>createHmac('sha256',Buffer.from(key,'base64')).update('nuphylab-mapping-commit-key-v1').digest('base64');

const key=Buffer.alloc(32,0x62).toString('base64'),derived=deriveMappingCommitSecret(key),name='AIR_STUDIO_MAPPING_COMMIT_SECRET';
test('mapping commit capability is captured and inherited poisoning is scrubbed independently of F11 hold',()=>{
  const hold={secret:Buffer.alloc(32,0x42).toString('base64'),path:'/tmp/synthetic-hold.json'};
  const env={AIR_STUDIO_NATIVE_KEY_SECRET:key,AIR_STUDIO_NATIVE_HOLD_SECRET:hold.secret,AIR_STUDIO_NATIVE_HOLD_PATH:hold.path,[name]:derived,KEEP:'yes'};
  assert.equal(takeMappingCommitSecret(env),derived);assert.deepEqual(takeNativeHoldEnvironment(env),hold);assert.deepEqual(env,{KEEP:'yes'});
  for(const bad of [null,'',true,Buffer.alloc(31).toString('base64')])assert.equal(sanitizeMappingCommitSecret(bad),null);
  const inherited={[name]:key,AIR_STUDIO_NATIVE_KEY_SECRET:key};
  assert.deepEqual(helperProcessEnvironment(null,inherited),{});
  assert.deepEqual(helperProcessEnvironment(null,inherited,derived),{[name]:derived});
  const held=helperProcessEnvironment(hold,inherited,derived);
  assert.equal(held.AIR_STUDIO_NATIVE_HOLD_SECRET,hold.secret);assert.equal(held.AIR_STUDIO_NATIVE_HOLD_PATH,hold.path);
  assert.equal(held[name],derived);assert.equal(Object.hasOwn(held,'AIR_STUDIO_NATIVE_KEY_SECRET'),false);
});
test('public-baseline Hardware never inherits a mapping capability or exposes private keys',async t=>{
  const dir=await mkdtemp(path.join(tmpdir(),'nuphylab-mapping-env-'));t.after(()=>rm(dir,{recursive:true,force:true}));
  const binary=path.join(dir,'helper.mjs');
  await writeFile(binary,`#!${process.execPath}
import {createInterface} from 'node:readline';
const name='AIR_STUDIO_MAPPING_COMMIT_SECRET';
createInterface({input:process.stdin}).on('line',line=>{const r=JSON.parse(line);process.stdout.write(JSON.stringify({id:r.id,ok:true,result:{
  mappingMatches:process.env[name]===${JSON.stringify(derived)},masterAbsent:!Object.hasOwn(process.env,'AIR_STUDIO_NATIVE_KEY_SECRET'),
  heldAbsent:!Object.hasOwn(process.env,'AIR_STUDIO_NATIVE_HOLD_SECRET')}})+'\\n');});
`);await chmod(binary,0o700);
  const hardware=new Hardware(binary,path.join(dir,'unused.json'),{nativeMappingCommitSecret:derived});
  t.after(()=>{hardware.child?.kill('SIGTERM');});
  const result=await hardware.request('probeMappingEnvironment');
  assert.deepEqual(result,{mappingMatches:false,masterAbsent:true,heldAbsent:true});
  assert.ok(!JSON.stringify(hardware).includes(derived));assert.ok(!JSON.stringify(hardware.state).includes(derived));
});
