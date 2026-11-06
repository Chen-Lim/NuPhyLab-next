import {readdir} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
const sources=(await readdir('native/selection')).filter(x=>x.endsWith('.swift')).map(x=>'native/selection/'+x);
execFileSync('swiftc',['-target',`${process.arch==='arm64'?'arm64':'x86_64'}-apple-macosx14.0`,'-swift-version','5','-import-objc-header','native/selection-audio/include/ChordAudioBoundary.h','qa/SelectionChecks.swift','native/SelectionIntegration.swift','native/SelectionLab.swift','native/SelectionInteraction.swift','native/SelectionNotch.swift','native/SelectionAnswerView.swift','native/SelectionMarkdown.swift','bin/SelectionAudioBoundary.o',...sources,'-O','-o','/tmp/nuphylab-selection-host-checks',...['AppKit','SwiftUI','Carbon','Security','AVFoundation','ScreenCaptureKit','Vision','Speech'].flatMap(x=>['-framework',x])],{stdio:'inherit'});
execFileSync('/tmp/nuphylab-selection-host-checks',[],{stdio:'inherit'});
