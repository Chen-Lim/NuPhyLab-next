import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile, writeFile, mkdtemp, mkdir, rm} from 'node:fs/promises';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHmac} from 'node:crypto';
import {tmpdir} from 'node:os';
import path from 'node:path';

test('native physical hold records are private, atomic, signed and fail closed using only owned temporary files', {skip:process.platform !== 'darwin'}, async t => {
  const source = await readFile(new URL('../native/AppHost.swift', import.meta.url), 'utf8');
  const begin = '// BEGIN NATIVE HOLD STATE', end = '// END NATIVE HOLD STATE';
  assert.equal(source.split(begin).length, 2);
  assert.equal(source.split(end).length, 2);
  const store = source.slice(source.indexOf(begin), source.indexOf(end) + end.length);
  assert.doesNotMatch(store, /\bAppKit\b|\bNSApp\b|\bCGEvent\b|\bIOHID|\bAXUIElement|URLSession|\.post\(|\.tapCreate\(/);
  const signer = source.slice(source.indexOf('struct NativeKeySigner {'), source.indexOf(begin));
  // Compile the two pure production types. This program never initializes the
  // application, HID, accessibility, a target, a worker or any event source.
  const fixture = `import Foundation
import CryptoKit
import Darwin
${signer}
${store}
let fm=FileManager.default
let base=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
let secret=Data(repeating:0x42,count:32)
var checks=0
func check(_ condition:Bool,_ message:String){checks+=1;if !condition{fatalError(message)}}
func exists(_ url:URL)->Bool{fm.fileExists(atPath:url.path)}
func metadata(_ url:URL)->stat{var value=stat();check(lstat(url.path,&value)==0,"fixture path exists");return value}
func payload(_ value:NativePhysicalHoldStore)->[String:Any]{try! JSONSerialization.jsonObject(with:Data(contentsOf:value.fileURL)) as! [String:Any]}
func contents(_ url:URL)->Data{try! Data(contentsOf:url)}
func write(_ value:NativePhysicalHoldStore,_ id:String="press:F11:1",_ code:Int=103,_ epoch:Int=7,_ held:Bool=true,_ now:Int=1_000)->Bool{
    value.write(gestureID:id,keyCode:code,bindingEpoch:epoch,held:held,nowMs:now)
}
check(NativePhysicalHoldStore(secret:Data(),baseDirectory:base)==nil,"empty secret rejected")
check(NativePhysicalHoldStore(secret:Data(repeating:1,count:31),baseDirectory:base)==nil,"short secret rejected")
check(NativePhysicalHoldStore(secret:Data(repeating:1,count:33),baseDirectory:base)==nil,"long secret rejected")
check(NativePhysicalHoldStore(secret:secret,baseDirectory:URL(string:"https://invalid.example")!)==nil,"non-file base rejected")
check(NativePhysicalHoldStore(secret:secret,baseDirectory:base.appendingPathComponent("missing"))==nil,"missing base is not created")
check((try! fm.contentsOfDirectory(atPath:base.path)).isEmpty,"failed initialization leaves no directory")

let active=NativePhysicalHoldStore(secret:secret,baseDirectory:base)!
let other=NativePhysicalHoldStore(secret:secret,baseDirectory:base)!
check(active.directoryURL != other.directoryURL,"each store has a new directory")
check(active.fileURL.lastPathComponent=="current.json","fixed private record name")
let initial=metadata(active.directoryURL)
check((initial.st_mode & S_IFMT)==S_IFDIR && (initial.st_mode & 0o777)==0o700 && initial.st_uid==geteuid(),"private directory ownership and permissions")
check(!exists(active.fileURL) && !exists(other.fileURL),"no session record restored")
check(active.invalidate(nowMs:0),"empty invalidation is safe")
check(write(active),"down written")
let freshSession=NativePhysicalHoldStore(secret:secret,baseDirectory:base)!
check(freshSession.directoryURL != active.directoryURL && !exists(freshSession.fileURL),"a new store never recovers an existing session's held record")
freshSession.close()
var records=[[String:Any]]()
records.append(payload(active))
let downInode=metadata(active.fileURL).st_ino
check((metadata(active.fileURL).st_mode & 0o777)==0o600,"record mode is 0600")
check(metadata(active.fileURL).st_uid==geteuid(),"record belongs to this user")
check(write(active,"press:F11:1",103,7,false,1_050),"up written")
records.append(payload(active))
check(metadata(active.fileURL).st_ino != downInode,"up atomically replaces the file")
check(write(active,"press:F11:1",103,7,true,1_060),"duplicate ID replaces rather than appends")
check(write(active,"press:F11:2",103,8,true,1_070),"new press replaces the previous ID")
records.append(payload(active))
check((try! fm.contentsOfDirectory(atPath:active.directoryURL.path))==["current.json"],"no write staging files survive")
let snapshot=contents(active.fileURL)
let invalidIDs=["","a b","a/b","a\\nb","中文",String(repeating:"a",count:161)]
for id in invalidIDs{check(!write(active,id),"invalid ID rejected")}
for code in [-1,128,Int.max]+Array(54...63){check(!write(active,"bad-code",code),"modifier or out-of-range source key rejected")}
for number in [-1,NativePhysicalHoldStore.maximumSafeInteger+1,Int.max]{
    check(!write(active,"bad-epoch",103,number),"invalid epoch rejected")
    check(!write(active,"bad-clock",103,7,true,number),"invalid timestamp rejected")
}
check(contents(active.fileURL)==snapshot,"argument rejection cannot rewrite an accepted record")
check(write(active,String(repeating:"a",count:160),0,0,false,0),"zero values and longest ID accepted")
records.append(payload(active))
check(write(active,"A-z_9.0:1",127,NativePhysicalHoldStore.maximumSafeInteger,true,NativePhysicalHoldStore.maximumSafeInteger),"upper safe integer and key bounds accepted")
records.append(payload(active))
check(active.invalidate(nowMs:2_000),"invalidation writes released state")
records.append(payload(active))
check(payload(active)["held"] as? Bool == false,"invalidation cannot keep a hold")
check(active.invalidate(nowMs:-1),"invalid clock revokes own record")
check(!exists(active.fileURL),"invalid clock leaves no stale hold")
check(write(active),"a new press may follow invalidation")
let activeDirectory=active.directoryURL
active.close();active.close()
check(!exists(activeDirectory),"idempotent close removes the owned record and empty directory")
check(!write(active) && active.invalidate(nowMs:2_100),"closed store cannot resume")
other.close()

var failWrites=false
let failure=NativePhysicalHoldStore(secret:secret,baseDirectory:base,beforeWrite:{_,_ in
    if failWrites{throw CocoaError(.fileWriteUnknown)}
})!
check(write(failure),"fake writer starts with an accepted down")
failWrites=true
check(!write(failure,"press:F11:1",103,7,false,1_100),"injected release write failure is reported")
check(!exists(failure.fileURL),"failed release revokes the previous held record")
check((try! fm.contentsOfDirectory(atPath:failure.directoryURL.path)).isEmpty,"failure leaves no partial file")
failWrites=false
check(write(failure,"press:F11:3"),"write can recover for a new press")
failWrites=true
check(!failure.invalidate(nowMs:1_200) && !exists(failure.fileURL),"failed invalidation also revokes a hold")
failure.close()

let nonrecursive=NativePhysicalHoldStore(secret:secret,baseDirectory:base)!
check(write(nonrecursive),"nonrecursive fixture starts with an owned record")
let sentinel=nonrecursive.directoryURL.appendingPathComponent("unrelated.txt")
try! Data("keep".utf8).write(to:sentinel)
nonrecursive.close()
check(exists(sentinel) && !exists(nonrecursive.fileURL),"close preserves unexpected files")

let replaced=NativePhysicalHoldStore(secret:secret,baseDirectory:base)!
check(write(replaced),"replacement fixture starts with an owned record")
let saved=replaced.directoryURL.appendingPathComponent("saved-owned-record")
try! fm.moveItem(at:replaced.fileURL,to:saved)
let foreign=Data("foreign-record".utf8)
try! foreign.write(to:replaced.fileURL)
check(!write(replaced,"press:new"),"a foreign replacement cannot be overwritten")
replaced.close()
check(contents(replaced.fileURL)==foreign && exists(saved),"close preserves replacement and renamed files")

let symlink=NativePhysicalHoldStore(secret:secret,baseDirectory:base)!
check(write(symlink),"symlink fixture starts with an owned record")
try! fm.removeItem(at:symlink.fileURL)
let target=base.appendingPathComponent("foreign-target")
try! foreign.write(to:target)
try! fm.createSymbolicLink(at:symlink.fileURL,withDestinationURL:target)
check(!write(symlink,"press:symlink"),"symbolic-link replacement cannot be followed")
symlink.close()
check((try! fm.destinationOfSymbolicLink(atPath:symlink.fileURL.path))==target.path && contents(target)==foreign,"symlink and destination remain unchanged")

let moved=NativePhysicalHoldStore(secret:secret,baseDirectory:base)!
check(write(moved),"directory replacement fixture starts with an owned record")
let oldPath=moved.directoryURL,relocated=base.appendingPathComponent("renamed-owned-directory",isDirectory:true)
try! fm.moveItem(at:oldPath,to:relocated)
try! fm.createDirectory(at:oldPath,withIntermediateDirectories:false)
let foreignSentinel=oldPath.appendingPathComponent("foreign.txt")
try! foreign.write(to:foreignSentinel)
check(!write(moved,"press:moved"),"directory identity replacement rejects write")
check(!exists(relocated.appendingPathComponent("current.json")),"failed write revokes only the original directory's record")
moved.close()
check(contents(foreignSentinel)==foreign && exists(relocated),"close preserves both replacement and renamed directory paths")

let permissions=NativePhysicalHoldStore(secret:secret,baseDirectory:base)!
check(write(permissions),"directory mode fixture starts with an owned record")
check(chmod(permissions.directoryURL.path,0o755)==0,"fixture changes its own directory mode")
check(!write(permissions,"press:mode") && !exists(permissions.fileURL),"unsafe directory permissions revoke current state")
let permissionsPath=permissions.directoryURL
permissions.close()
check(!exists(permissionsPath),"close can remove its own empty directory after mode changes")
let filePermissions=NativePhysicalHoldStore(secret:secret,baseDirectory:base)!
check(write(filePermissions),"file mode fixture starts with an owned record")
check(chmod(filePermissions.fileURL.path,0o644)==0,"fixture changes its own file mode")
check(!write(filePermissions,"press:file-mode") && !exists(filePermissions.fileURL),"unsafe record permissions revoke current state")
filePermissions.close()

var ephemeralPath:URL!
do{
    let ephemeral=NativePhysicalHoldStore(secret:secret,baseDirectory:base)!
    ephemeralPath=ephemeral.directoryURL
    check(write(ephemeral),"deinit fixture writes")
}
check(!exists(ephemeralPath),"deinit removes its own session state")
var signer=NativeKeySigner(secret:secret)
let keyPacket=signer.sign(["op":"codexKey","code":"F11","phase":"down","gestureId":"press:F11:1","eventSource":"eventTap","nativeKeyBindingEpoch":7],trusted:true)!
let result:[String:Any]=["records":records,"keySignature":keyPacket["nativeKeySignature"]!,"checks":checks]
print(String(data:try! JSONSerialization.data(withJSONObject:result,options:.sortedKeys),encoding:.utf8)!)
`;
  const directory = await mkdtemp(path.join(tmpdir(), 'nuphylab-physical-hold-test-'));
  t.after(() => rm(directory, {recursive:true, force:true}));
  const base = path.join(directory, 'owned-fixture-files');
  await mkdir(base);
  const main = path.join(directory, 'main.swift'), binary = path.join(directory, 'check');
  await writeFile(main, fixture);
  const run = promisify(execFile);
  await run('swiftc', ['-module-cache-path', path.join(directory, 'module-cache'), main, '-framework', 'CryptoKit', '-o', binary]);
  const result = JSON.parse((await run(binary, [base])).stdout.trim());
  assert.ok(result.checks >= 85, 'all isolated Swift lifecycle and failure checks ran');
  assert.equal(result.records.length, 6);
  assert.deepEqual(result.records.map(record => record.held), [true, false, true, false, true, false]);
  for (const record of result.records) {
    assert.deepEqual(Object.keys(record).sort(), ['bindingEpoch', 'gestureId', 'held', 'recordedAtMs', 'signature', 'sourceKeyCode']);
    assert.match(record.signature, /^[a-f0-9]{64}$/);
    const canonical = JSON.stringify(['nuphylab-native-hold-v1', record.gestureId, record.sourceKeyCode, record.bindingEpoch, record.held, record.recordedAtMs]);
    assert.equal(record.signature, createHmac('sha256', Buffer.alloc(32, 0x42)).update(canonical).digest('hex'), 'Swift and Node sign exactly the same typed canonical array');
  }
  assert.notEqual(result.records[0].signature, result.keySignature, 'native-key and hold records use separate signing domains');
});
