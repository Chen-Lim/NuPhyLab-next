import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import path from 'node:path';

test('startup restores normal windows but bounds maximized, corrupt and detached-display frames',
  {skip:process.platform!=='darwin'},async t=>{
    const directory=await mkdtemp('/tmp/nl-window-');
    t.after(()=>rm(directory,{recursive:true,force:true}));
    const source=await readFile(new URL('../native/AppHost.swift',import.meta.url),'utf8');
    const start=source.indexOf('enum NativeWindowStartupGeometry {');
    const end=source.indexOf('\nenum NativeWindowDragRegion {',start);
    assert.ok(start>=0 && end>start);
    const fixture=`import AppKit
${source.slice(start,end)}
var checks=[[String:Any]]()
func check(_ name:String,_ value:Bool){checks.append(["name":name,"passed":value])}
let screen=NSRect(x:0,y:23,width:1710,height:1050)
let preferred=NSSize(width:1080,height:720)
let centered=NSRect(x:315,y:188,width:1080,height:720)
let tiled="0 90 1710 983 0 0 1710 1073 {\\\"tilingState\\\":{\\\"tilingPosition\\\":9}}"
check("tiling metadata is not replayed as window state",NativeWindowStartupGeometry.savedFrame(tiled)==NSRect(x:0,y:90,width:1710,height:983))
check("normal saved numbers parse",NativeWindowStartupGeometry.savedFrame("257 288 938 624 0 0 1710 1073 ")==NSRect(x:257,y:288,width:938,height:624))
check("nil saved frame ignored",NativeWindowStartupGeometry.savedFrame(nil)==nil)
check("truncated saved frame ignored",NativeWindowStartupGeometry.savedFrame("0 0 900 600")==nil)
check("nonnumeric saved frame ignored",NativeWindowStartupGeometry.savedFrame("bad 0 900 600 0 0 1710 1073")==nil)
check("nonfinite saved frame ignored",NativeWindowStartupGeometry.savedFrame("0 0 inf 600 0 0 1710 1073")==nil)
check("negative saved dimensions ignored",NativeWindowStartupGeometry.savedFrame("0 0 -900 600 0 0 1710 1073")==nil)
let left=NSRect(x:-1440,y:0,width:1440,height:900)
check("saved display chosen by intersection",NativeWindowStartupGeometry.targetScreen(saved:NSRect(x:-1200,y:100,width:900,height:600),screens:[screen,left],fallback:screen)==left)
check("removed display uses main display",NativeWindowStartupGeometry.targetScreen(saved:NSRect(x:4000,y:100,width:900,height:600),screens:[screen,left],fallback:screen)==screen)
check("corrupt screen ignored",NativeWindowStartupGeometry.targetScreen(saved:screen,screens:[.zero,screen],fallback:left)==screen)
func frame(_ saved:NSRect?,_ visible:NSRect=screen)->NSRect{
    NativeWindowStartupGeometry.frame(restored:saved,visible:visible,defaultSize:preferred)
}
check("first launch is centered and moderate",frame(nil)==centered)
let ordinary=NSRect(x:257,y:288,width:938,height:624)
check("normal user window is preserved",frame(ordinary)==ordinary)
check("filled screen does not return",frame(screen)==centered)
check("real tiled autosave returns centered default",frame(NativeWindowStartupGeometry.savedFrame(tiled))==centered)
check("wide saved window is reset",frame(NSRect(x:0,y:100,width:1600,height:600))==centered)
check("tall saved window is reset",frame(NSRect(x:100,y:23,width:938,height:1050))==centered)
check("too small saved window is reset",frame(NSRect(x:500,y:500,width:300,height:200))==centered)
check("old disconnected display recenters",frame(NSRect(x:3000,y:0,width:900,height:600))==centered)
check("partial right/top overflow is clamped",frame(NSRect(x:1400,y:800,width:900,height:600))==NSRect(x:810,y:473,width:900,height:600))
check("partial left overflow is clamped",frame(NSRect(x:-50,y:400,width:900,height:600))==NSRect(x:0,y:400,width:900,height:600))
check("negative-coordinate screen centers correctly",frame(nil,NSRect(x:-1440,y:0,width:1440,height:900))==NSRect(x:-1260,y:90,width:1080,height:720))
let external=NSRect(x:-1300,y:100,width:900,height:600)
check("normal external-screen window is preserved",frame(external,NSRect(x:-1440,y:0,width:1440,height:900))==external)
check("nonfinite saved frame resets",frame(NSRect(x:CGFloat.nan,y:0,width:900,height:600))==centered)
check("zero saved frame resets",frame(.zero)==centered)
check("invalid screen safely falls back",frame(nil,.zero)==NSRect(x:180,y:90,width:1080,height:720))
let laptop=NativeWindowStartupGeometry.defaultContentSize(visible:NSSize(width:1710,height:1073))
check("default laptop size is1080x720",laptop==preferred)
let small=NativeWindowStartupGeometry.defaultContentSize(visible:NSSize(width:1280,height:800))
check("short screen leaves useful margin",small.width==1080 && abs(small.height-628)<0.001)
let tiny=NativeWindowStartupGeometry.defaultContentSize(visible:NSSize(width:640,height:480))
check("tiny usable screen is not exceeded",tiny==NSSize(width:608,height:448))
let fallback=NativeWindowStartupGeometry.defaultContentSize(visible:NSSize(width:CGFloat.infinity,height:800))
check("nonfinite screen size gets finite fallback",fallback==NSSize(width:1080,height:710))
let bounded=NativeWindowStartupGeometry.frame(restored:nil,visible:NSRect(x:0,y:0,width:640,height:480),defaultSize:preferred)
check("frame can never exceed visible display",bounded==NSRect(x:0,y:0,width:640,height:480))
let data=try! JSONSerialization.data(withJSONObject:["checks":checks,"applicationStarted":NSApp != nil],options:.sortedKeys)
print(String(data:data,encoding:.utf8)!)
`;
    const file=path.join(directory,'main.swift'),binary=path.join(directory,'checks');
    await writeFile(file,fixture);
    const run=promisify(execFile);
    await run('swiftc',['-module-cache-path',path.join(directory,'cache'),file,'-o',binary,'-framework','AppKit']);
    const result=JSON.parse((await run(binary)).stdout.trim());
    assert.equal(result.applicationStarted,false);
    assert.equal(result.checks.length,30);
    for(const row of result.checks)await t.test(row.name,()=>assert.equal(row.passed,true));
  });
