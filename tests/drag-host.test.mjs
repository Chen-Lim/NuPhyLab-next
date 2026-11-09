import test from 'node:test';import assert from 'node:assert/strict';import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';import {execFile} from 'node:child_process';import {promisify} from 'node:util';import {tmpdir} from 'node:os';import path from 'node:path';import {fileURLToPath} from 'node:url';
test('formal host defers quit/update during conversion and resumes dragging after a failed music save',{skip:process.platform!=='darwin',timeout:120000},async t=>{
 const d=await mkdtemp(path.join(tmpdir(),'nuphylab-drag-host-'));t.after(()=>rm(d,{recursive:true,force:true}));const root=fileURLToPath(new URL('../',import.meta.url)),framework=path.join(root,'vendor/sparkle'),host=await readFile(path.join(root,'native/AppHost.swift'),'utf8'),main=path.join(d,'main.swift'),bin=path.join(d,'check');
 const start=host.indexOf('    func presentDragBusyNotice(){'),end=host.indexOf('    func replyToTermination(',start);assert(start>=0&&end>start);
 // Replace only the alert presenter; all transition gates remain production code.
 let isolated=host.slice(0,start)+'    func presentDragBusyNotice(){dragNoticeCount+=1}\n'+host.slice(end);
 const recoveryStart=isolated.indexOf('    func recoverAfterAbortedUpdate(){'),recoveryEnd=isolated.indexOf('    func prepareUpdateAfterMusicSave(){',recoveryStart);
 assert(recoveryStart>=0&&recoveryEnd>recoveryStart);
 const recovery=isolated.slice(recoveryStart,recoveryEnd).replace(/appendWorkerLog\(Data\([^\n]+/, 'updateRecoveryLogCount+=1');
 isolated=isolated.slice(0,recoveryStart)+recovery+isolated.slice(recoveryEnd);
 const retryStart=isolated.indexOf('    func retryAbortedUpdateService(){'),retryEnd=isolated.indexOf('    func presentUpdateRecoveryFailure(){',retryStart);
 isolated=isolated.slice(0,retryStart)+'    func retryAbortedUpdateService(){updateRecoveryServiceRequests+=1}\n'+isolated.slice(retryEnd);
 await writeFile(main,isolated+`
var dragNoticeCount=0,updateRecoveryLogCount=0,updateRecoveryServiceRequests=0
extension AppDelegate {func setSleepFixture(_ value:Bool){keySessionSuspended=value}}
let system=NSApplication.shared,app=AppDelegate()
var count=0
func expect(_ value:Bool){precondition(value);count+=1}
expect(app.dragPresentationAllowed)
app.capturingKey=true;expect(!app.dragPresentationAllowed);app.capturingKey=false
app.selectionShortcutRecording=true;expect(!app.dragPresentationAllowed);app.selectionShortcutRecording=false
app.setSleepFixture(true);expect(!app.dragPresentationAllowed);app.setSleepFixture(false)
app.permissionRelaunchPending=true;expect(!app.dragPresentationAllowed);app.permissionRelaunchPending=false
app.musicFlushInProgress=true;expect(!app.dragPresentationAllowed);app.musicFlushInProgress=false
app.preparingUpdate=true;expect(!app.dragPresentationAllowed);app.preparingUpdate=false
app.terminating=true;expect(!app.dragPresentationAllowed);app.terminating=false
app.dragConvert.busy=true
expect(app.applicationShouldTerminate(system) == .terminateCancel)
expect(dragNoticeCount==1 && !app.terminating && app.worker==nil && !app.musicFlushInProgress)
var installed=false;app.pendingUpdateInstall={installed=true};app.prepareUpdateInstallation()
expect(dragNoticeCount==2 && !installed && !app.preparingUpdate && app.pendingUpdateInstall != nil)
app.baseURL=URL(string:"http://127.0.0.1:1");app.pendingUpdateVersion="1.2.46";app.prepareUpdateAfterMusicSave()
expect(dragNoticeCount==3 && !installed && !app.preparingUpdate)
expect(app.terminateAfterMusicSave(system) == .terminateCancel && dragNoticeCount==4)
app.dragConvert.busy=false;app.dragConvert.suspend();app.musicEverUsed=true
var saved=true;app.flushMusicForTransition{saved=$0}
expect(!saved && app.musicSaveFailed && !app.dragConvert.suspended && !app.terminating)
app.musicEverUsed=false
expect(app.applicationShouldTerminate(system) == .terminateNow && app.dragConvert.suspended)
app.updateInstallCommitted=true;app.dragConvert.suspend();app.didWake()
expect(!app.dragPresentationAllowed && app.dragConvert.suspended)
app.unlockMusicTransition();expect(app.dragConvert.suspended)
let current=Process();app.worker=current
app.workerDidExit(Process(),status:0,signaled:false);expect(app.worker === current)
let aborted=AppDelegate();aborted.recoverAfterAbortedUpdate()
expect(updateRecoveryServiceRequests==0 && !aborted.permissionRelaunchPending)
aborted.updateInstallCommitted=true;aborted.pendingUpdateInstall={};aborted.pendingUpdateVersion="1.2.46"
aborted.recoverAfterAbortedUpdate()
expect(updateRecoveryServiceRequests==1 && updateRecoveryLogCount==1 && aborted.updateAbortRecoveryRequested)
expect(!aborted.updateInstallCommitted && !aborted.permissionRelaunchPending && aborted.updatePreparationEpoch==1 && aborted.pendingUpdateInstall==nil && aborted.pendingUpdateVersion==nil)
aborted.recoverAfterAbortedUpdate();expect(updateRecoveryServiceRequests==1)
let quitting=AppDelegate();quitting.updateInstallCommitted=true;quitting.terminating=true;quitting.recoverAfterAbortedUpdate()
expect(!quitting.updateAbortRecoveryRequested && updateRecoveryServiceRequests==1)
expect(!aborted.dragPresentationAllowed && !aborted.musicPlayAllowed())
aborted.checkForUpdates();expect(updateRecoveryServiceRequests==2)
let preparing=AppDelegate();preparing.preparingUpdate=true;preparing.pendingUpdateInstall={};preparing.updatePreparationEpoch=12
preparing.recoverAfterAbortedUpdate()
expect(preparing.updatePreparationEpoch==13 && !preparing.preparingUpdate && preparing.pendingUpdateInstall==nil && preparing.updateAbortRecoveryRequested && updateRecoveryServiceRequests==3)
let saveOnly=AppDelegate();saveOnly.musicFlushInProgress=true
expect(saveOnly.applicationShouldTerminate(system) == .terminateCancel && !saveOnly.applicationQuitPending)
saveOnly.applicationQuitPending=true
expect(saveOnly.applicationShouldTerminate(system) == .terminateLater && saveOnly.applicationQuitPending)
let oldURL=app.baseURL;app.ready("http://127.0.0.1:9",from:Process())
expect(app.baseURL == oldURL && app.worker === current)
print("drag-host: \\(count) checks; no files/network/HID")
`);
 const run=promisify(execFile);await run('swiftc',[main,path.join(root,'tests/fixtures/selection-host-boundary.swift'),...['AppInstance','UpdateUserDriver','AudioCapture','KeyGestureGate'].map(x=>path.join(root,'native/'+x+'.swift')),'-o',bin,'-F',framework,'-framework','Sparkle','-Xlinker','-rpath','-Xlinker',framework,...['AppKit','WebKit','Carbon','AVFoundation','CoreAudio','Accelerate'].flatMap(x=>['-framework',x])]);assert.match((await run(bin)).stdout,/drag-host: 29 checks; no files\/network\/HID/);
});
