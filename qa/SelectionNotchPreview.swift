import AppKit
import SwiftUI

/// Standalone synthetic view fixture. Never instantiates SelectionLab or opens
/// screen/audio/input/API services; compiled separately from the shipped app.
@main struct SelectionNotchPreview {
 @MainActor static func main(){let app=NSApplication.shared;let delegate=PreviewDelegate();app.delegate=delegate;app.setActivationPolicy(.regular);app.run();withExtendedLifetime(delegate){}}
}
@MainActor final class PreviewDelegate:NSObject,NSApplicationDelegate {
 let state=SelectionPanelState();var panel:SelectionResultPanel!;var controls:NSWindow!;var measured:LabAnswerMeasurement?;var surface:SelectionNotchSurface!;var overlay:SelectionOverlayWindow?;var stream:Timer?
 var trace:[[String:Any]]=[];var fixtureID="initial"
 func saveTrace(){
  let path=Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("native-frame-trace.json")
  if let data=try? JSONSerialization.data(withJSONObject:trace,options:[.prettyPrinted,.sortedKeys]){try? data.write(to:path,options:.atomic)}
 }
 func applicationWillTerminate(_ notification:Notification){saveTrace()}
 func applicationDidFinishLaunching(_ notification:Notification){
  let menu=NSMenu();let root=NSMenuItem();menu.addItem(root);let actions=NSMenu();root.submenu=actions
  for (index,id) in ["one","two","markdown","long","processing","permission","mode","selection","voice","stream"].enumerated(){let item=NSMenuItem(title:id,action:#selector(selectFixture(_:)),keyEquivalent:String(index+1));item.target=self;actions.addItem(item)}
  actions.addItem(NSMenuItem(title:"Quit",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"));NSApp.mainMenu=menu
  panel=SelectionResultPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
  panel.title="框选回答预览";panel.isReleasedWhenClosed=false;panel.hidesOnDeactivate=false;panel.level=NSWindow.Level(rawValue:NSWindow.Level.statusBar.rawValue+1);panel.becomesKeyOnlyIfNeeded=true;panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=false
  let host=SelectionHostingView(rootView:SelectionAnswerView(state:state));host.sizingOptions=[];panel.contentView=host;surface=SelectionNotchSurface(panel:panel)
  surface.onFrame={[weak self] frame,target,time,settled in
   guard let self else{return}
   self.trace.append(["fixture":self.fixtureID,"expanded":self.state.expanded,"time":time,"wall":ProcessInfo.processInfo.systemUptime,"width":frame.width,"height":frame.height,"top":frame.maxY,"targetWidth":target.width,"targetHeight":target.height,"settled":settled])
   if settled{self.saveTrace()}
  }
  state.size={[weak self] height in self?.measured=height;self?.layout()};state.close={[weak self] in guard let self,let screen=NSScreen.main else{return};let m=LabNotchLayout.place(on:screen,width:185,height:24);self.surface.dismiss(to:m)};state.beginTyping={[weak self] in self?.panel.makeKey()}
  state.submit={[weak self] _ in self?.state.showQuestion=false;self?.state.answer="这是本机合成的追问回答。没有联网、截图或录音。"}
  state.cancel={[weak self] in self?.state.busy=false;self?.state.issue="已停止"}
  state.expansion={[weak self] in self?.layout()}
  state.switchAction={[weak self] action in self?.state.action=action}
  state.settings={[weak self] in self?.state.issue="模拟设置入口"};state.reselect={[weak self] in self?.fixture("processing")}
  controls=NSWindow(contentRect:NSRect(x:100,y:140,width:980,height:130),styleMask:[.titled,.closable],backing:.buffered,defer:false);controls.title="合成界面验证 · 无截图 / 麦克风 / API"
  controls.contentView=NSHostingView(rootView:VStack(spacing:14){Text("本机合成样本").font(.headline);HStack{ForEach(["one","two","markdown","long","processing","permission","mode","selection","voice","stream"],id:\.self){id in Button(id){self.fixture(id)}};Button("退出"){NSApp.terminate(nil)}}}.padding(20));controls.makeKeyAndOrderFront(nil)
  NSApp.activate();fixture("one")
 }
 @objc func selectFixture(_ sender:NSMenuItem){fixture(sender.title)}
 func fixture(_ id:String){
  fixtureID=id
  stream?.invalidate();stream=nil;overlay?.orderOut(nil);overlay=nil;surface.hide();state.expanded=false
  state.answer="";state.question="";state.issue="";state.missingPermissions=[];state.showQuestion=false;state.busy=false;state.text="Synthetic sample";state.phase="正在翻译";measured=nil
  switch id {
   case "one":state.answer="本地风味芝加哥深盘披萨口味的壶式油炸薯片。"
   case "markdown":state.question="这里面图片的食物热量是多少？";state.answer="这张图是一组汉堡食材，**没有面包和酱料**。按常见分量估算，整盘大约 **480–550 大卡**，可以粗略记作 **约 500 大卡**。\n\n### 分项估算\n- 生菜 1 片：约 5 大卡\n- 番茄 1 大片：约 15–20 大卡\n- 芝士片 2 片：约 140–160 大卡\n\n| 食材 | 说明 |\n| --- | --- |\n| 蔬菜 | 保留原味 |\n| 芝士 | 按实际份量调整 |\n\n`2 * 3` 中的星号是代码，会正常保留。"
   case "two":state.answer="轻一点的界面，为内容留出空间。答案从刘海自然展开，读完就回到手头的事。"
   case "long":state.answer=(1...24).map{"\($0). 这是用于检查长回答的合成段落。内容会在面板内滚动，只有顶部一行操作保持可见。"}.joined(separator:"\n\n")
   case "mode","voice","selection":
    guard let screen=NSScreen.main else{return};let w=SelectionOverlayWindow(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    w.isReleasedWhenClosed=false;w.isOpaque=false;w.backgroundColor = .clear;w.hasShadow=false;w.level = .screenSaver
    let v=SelectionOverlayView(frame:NSRect(origin:.zero,size:screen.frame.size));let m=LabNotchLayout.place(on:screen,width:185,height:24)
    v.topInset=screen.frame.maxY-m.frame.maxY;v.cameraWidth=m.cameraWidth;v.listening=id=="voice";v.speech=id=="voice" ? "合成语音问题":""
    v.cancel={[weak self] in self?.overlay?.orderOut(nil)};v.mode={step in v.action=v.action.stepped(step)};v.finish={[weak self] _ in if id != "selection"{self?.fixture("one")}}
    w.contentView=v;overlay=w;w.makeKeyAndOrderFront(nil);return
   case "stream":
    state.busy=true
    let sample=(1...10).map{"\($0). **黑色界面**沿刘海自然展开，答案留在屏幕顶部。"}.joined(separator:"\n\n")
    var offset=0
    stream=Timer.scheduledTimer(withTimeInterval:0.05,repeats:true){[weak self] timer in MainActor.assumeIsolated{
     guard let self else{timer.invalidate();return};offset=min(sample.count,offset+6);self.state.answer=String(sample.prefix(offset));if offset==sample.count{timer.invalidate();self.state.busy=false}
    }}
   case "processing":state.busy=true
   case "permission":state.text="";state.missingPermissions=["microphone","speechRecognition"]
   default:state.answer="让想法自然流动。\n\n框选之后，答案会从屏幕顶部展开。"
  };layout();surface.show();panel.makeKeyAndOrderFront(nil)
 }
 func layout(){
  guard let screen=NSScreen.main else{return};let metrics=LabNotchLayout.place(on:screen,width:10000,height:24)
  if state.hasCameraHousing != metrics.hasCameraHousing{state.hasCameraHousing=metrics.hasCameraHousing}
  if state.maximumContentWidth != metrics.frame.width{state.maximumContentWidth=metrics.frame.width}
  let width=state.isCompact ? (metrics.hasCameraHousing ? metrics.cameraWidth:156):state.readingWidth
  let content=measured.flatMap{LabAnswerSizing.accepts($0,width:width) ? $0.height:nil}
  let height=state.isCompact ? 24:LabAnswerSizing.height(content:content,expanded:state.expanded,fallback:max(64,panel.frame.height))
  let layout=LabNotchLayout.place(on:screen,width:width,height:height)
  let overflow = !state.isCompact && (content ?? 0)>layout.frame.height-LabAnswerSizing.chromeHeight+1
  if state.contentOverflow != overflow{state.contentOverflow=overflow}
  if state.contentWidth != layout.frame.width{state.contentWidth=layout.frame.width}
  surface.place(layout,animated:true)
 }
}
