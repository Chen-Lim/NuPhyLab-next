import {mkdtemp,readdir,rm} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import path from 'node:path';
const directory=await mkdtemp(path.join(tmpdir(),'nsl-speech-'));
try {
 const sources=(await readdir('native/selection')).filter(x=>x.endsWith('.swift')).map(x=>'native/selection/'+x);
 const output=path.join(directory,'checks');
 execFileSync('swiftc',['-D','DEBUG','-target',`${process.arch==='arm64'?'arm64':'x86_64'}-apple-macosx14.0`,'-swift-version','5','-import-objc-header','native/selection-audio/include/ChordAudioBoundary.h','qa/SelectionSpeechChecks.swift','bin/SelectionAudioBoundary.o',...sources,'-O','-o',output,...['AppKit','SwiftUI','Carbon','Security','AVFoundation','ScreenCaptureKit','Vision','Speech'].flatMap(x=>['-framework',x])],{stdio:'inherit'});
 execFileSync(output,[],{stdio:'inherit'});
}finally{await rm(directory,{recursive:true,force:true});}
