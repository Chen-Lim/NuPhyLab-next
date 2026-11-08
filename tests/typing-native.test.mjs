import test from 'node:test';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp,rm} from 'node:fs/promises';
import path from 'node:path';
const run=promisify(execFile);
test('native typing settings, key gates, all sample banks and offline limiter',{skip:process.platform!=='darwin'},async()=>{
  const dir=await mkdtemp('/tmp/nl-typing-');
  try{
    await run('swiftc',['-swift-version','5','native/typing/TypingSoundModel.swift','native/typing/TypingSoundEngine.swift','qa/TypingSoundChecks.swift','-O','-o',path.join(dir,'checks'),'-framework','AVFoundation','-framework','AudioToolbox'],{maxBuffer:2**20});
    const {stdout}=await run(path.join(dir,'checks'),[path.resolve('assets/typing-sounds')],{maxBuffer:2**22});
    const report=JSON.parse(stdout);assert.equal(report.passed,true,JSON.stringify(report.checks.filter(x=>!x.passed)));assert.equal(report.decodedBuffers,732);assert.equal(report.audioDeviceOpened,false);
  }finally{await rm(dir,{recursive:true,force:true});}
});
test('native controller permission-free preview, overlapping pauses and cancelled quit',{skip:process.platform!=='darwin'},async()=>{
  const dir=await mkdtemp('/tmp/nl-typing-state-');
  try{
    await run('swiftc',['-swift-version','5','native/typing/TypingSoundModel.swift','native/typing/TypingSoundController.swift','qa/TypingControllerChecks.swift','-O','-o',path.join(dir,'checks'),'-framework','AppKit','-framework','Carbon','-framework','IOKit'],{maxBuffer:2**20});
    const {stdout}=await run(path.join(dir,'checks'),[path.resolve('assets/typing-sounds/catalog.json'),dir],{maxBuffer:2**20});
    const report=JSON.parse(stdout);assert.equal(report.passed,true,JSON.stringify(report.checks.filter(x=>!x.passed)));assert.equal(report.usesRealInputOrAudio,false);
  }finally{await rm(dir,{recursive:true,force:true});}
});
