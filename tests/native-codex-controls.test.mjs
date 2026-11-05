import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm,mkdir,chmod,symlink} from 'node:fs/promises';
import {createHmac} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {tmpdir} from 'node:os';
import path from 'node:path';

test('standard Codex controls select exact bounded synthetic AX controls without touching a real application', {skip:process.platform!=='darwin'}, async t=>{
  const source=await readFile(new URL('../native/HIDBridge.swift',import.meta.url),'utf8');
  const hostSource=await readFile(new URL('../native/AppHost.swift',import.meta.url),'utf8');
  assert.match(hostSource,/func physicalHoldNowMs\(\)->Int\s*\{Int\(ProcessInfo\.processInfo\.systemUptime\*1000\)\}/,
    'the actual hold producer records monotonic uptime, matching the production verifier');
  const start=source.indexOf('// BEGIN CODEX CONTROLS');
  const end=source.indexOf('// END CODEX CONTROLS',start);
  assert.ok(start>=0&&end>start);
  const controls=source.slice(start,end);
  const allowedEnable='AXUIElementSetAttributeValue(application,"AXManualAccessibility" as CFString,kCFBooleanTrue)';
  const allowedComplete='AXUIElementSetAttributeValue(application,"AXEnhancedUserInterface" as CFString,kCFBooleanTrue)';
  const allowedFocus='AXUIElementSetAttributeValue(elements[editable],kAXFocusedAttribute as CFString,kCFBooleanTrue)';
  const allowedActivate='target.activate(options:[])';
  assert.equal(controls.split(allowedEnable).length-1,1,'one fixed Electron opt-in, with no caller-supplied attribute or value');
  assert.equal(controls.split(allowedComplete).length-1,1,'one fixed application AT opt-in, never disabled or caller configurable');
  assert.equal(controls.split(allowedFocus).length-1,1,'one fixed, exact editor focus mutation, never text or selection');
  assert.equal(controls.split(allowedActivate).length-1,1,'only the verified unique running Codex process can be activated for held dictation');
  assert.doesNotMatch(controls.replace(allowedEnable,'').replace(allowedComplete,'').replace(allowedFocus,'').replace(allowedActivate,''),/kAXValueAttribute|AXIsProcessTrustedWithOptions|AXUIElementSetAttributeValue|\.activate\(|\.launchApplication|\.post\(|\.postToPid\(|\.tapCreate\(/);
  assert.match(controls,/static func prepare\(\)/,'public opt-in is available before the physical key');
  const errorStart=source.indexOf('struct BridgeError:');
  const errorEnd=source.indexOf('\nfunc failure(',errorStart);
  const errorSource=source.slice(errorStart,errorEnd);
  assert.ok(errorStart>=0&&errorEnd>errorStart);
  // Compile the actual production adapter as well as its planner, but invoke
  // only the planner with synthetic nodes and in-memory reader/press closures.
  // In particular this fixture never calls CodexControls.perform or creates an
  // AX application, event tap, window, HID handle, shortcut or real recording.
  const holdKey=Buffer.alloc(32,42),holdRecord={gestureId:'fixture:hold',sourceKeyCode:103,bindingEpoch:9,held:true,recordedAtMs:1000};
  const signedHold=patch=>{
    const value={...holdRecord,...patch};
    value.signature=createHmac('sha256',holdKey).update(JSON.stringify(['nuphylab-native-hold-v1',value.gestureId,value.sourceKeyCode,value.bindingEpoch,value.held,value.recordedAtMs])).digest('hex');
    return value;
  };
  const holdData=value=>Buffer.from(JSON.stringify(value)).toString('base64');
  const validHold=signedHold({});
  const fixture=`import Foundation
import AppKit
import ApplicationServices
${errorSource}
func failure(_ code:String,_ message:String)->BridgeError {BridgeError(code:code,message:message)}
${controls}
var checks=0
func check(_ value:Bool,_ message:String){checks+=1;if !value{fatalError(message)}}
func expect(_ code:String,_ action:() throws -> Void) {
    do {try action();check(false,"expected rejection")}
    catch let error as BridgeError {check(error.code==code,"explicit bounded failure code")}
    catch {check(false,"unexpected error type")}
}
let baseline=CodexControlContext(bundleID:"com.openai.codex",pid:42,window:0)
let childrenDiagnostics=CodexControlDiagnostics(now:{0})
// A real AX provider may expose an empty visible subset on a window while its
// ordinary children contain the renderer. Exercise the production AX adapter.
var attributes=[String]()
let renderer:[Int]=try! CodexControlChildren.read(count:{attribute in
    attributes.append(attribute);return (.success,attribute=="AXChildren" ? 1:0)
},values:{attribute,count in (.success,attribute=="AXChildren" ? [7]:[])},check:{},diagnostics:childrenDiagnostics)
check(renderer==[7],"empty AXVisibleChildren cannot hide the renderer from traversal")
check(attributes==["AXChildren"],"the hierarchy is independent of optional viewport subsets")
expect("CONTROL_READ_FAILED") {
    let _: [Int]=try CodexControlChildren.read(count:{_ in (.cannotComplete,0)},values:{_,_ in (.success,[])},check:{},diagnostics:childrenDiagnostics)
}
expect("CONTROL_SCAN_LIMIT") {
    let _: [Int]=try CodexControlChildren.read(count:{_ in (.success,4097)},values:{_,_ in (.success,[])},check:{},diagnostics:childrenDiagnostics)
}
expect("CONTROL_READ_FAILED") {
    let _: [Int]=try CodexControlChildren.read(count:{_ in (.success,2)},values:{_,_ in (.success,[7])},check:{},diagnostics:childrenDiagnostics)
}
check(CodexModelPickerOpener.parse(["keyCode":46,"modifiers":["shift","control"]]) != nil,"standard model-picker opener")
for code in [105,107,113,106,64,79,80,90] {
    check(CodexModelPickerOpener.parse(["keyCode":code,"modifiers":["control","shift"]]) != nil,"dedicated model-picker opener")
}
for raw:Any in [NSNull(),["keyCode":46,"modifiers":["command"]],["keyCode":36,"modifiers":["control"]],
    ["keyCode":105,"modifiers":[]],["keyCode":105,"modifiers":["fn"]],
    ["keyCode":46,"modifiers":["control","shift","shift"]],["keyCode":105,"modifiers":["unknown"]]] {
    check(CodexModelPickerOpener.parse(raw) == nil,"unsafe opener is rejected without a fallback event")
}
func button(_ label:String,_ enabled:Bool=true,_ role:String="AXButton")->CodexControlNode {
    CodexControlNode(role:role,title:label,enabled:enabled,actions:["AXPress"])
}
func basic(_ label:String,_ enabled:Bool=true,_ role:String="AXButton")->[Int:CodexControlNode] {
    [0:CodexControlNode(role:"AXWindow",children:[1]),1:button(label,enabled,role)]
}
final class Fixture {
    var nodes:[Int:CodexControlNode]
    var current:CodexControlContext?=baseline
    var time=0.0,readAdvance=0.0,settleSeconds=0.01
    var reads=[Int](),presses=[Int](),cancels=[Int](),opens=0,settles=0,contexts=0,enables=0,applicationReads=0
    var order=[String]()
    var lastDiagnostic:CodexControlDiagnostics?
    var onEnable:(() throws -> String)?,onSettle:((Int) -> Void)?,onApplicationRole:(() throws -> String?)?
    var onPress:((Int) throws -> Void)?,onOpen:(() throws -> Void)?,onCancel:((Int) throws -> Bool)?,onRead:((Int) -> Void)?,onContext:((Int) -> CodexControlContext?)?
    var activations=0,activationResponse="accepted",focused:Int?,documentFocused:Int?,documentFocusReads=0,ownedScope:Int?,selectedScope:Int?,selectedDocument:Int?,selectedEditable:Int?
    var allowAutomatic=false,held=true,holdChecks=0,focusRequests=[Int](),focusable=true
    var onStructure:((Int) -> Void)?,onHold:((Int) -> Bool)?,onFocus:((Int) -> Void)?
    var activationIdentity=CodexAccessibilityActivationIdentity(pid:42,launch:Date(timeIntervalSince1970:100))
    init(_ nodes:[Int:CodexControlNode]){self.nodes=nodes}
    func run(_ action:CodexControlAction,opener:Bool=false,cancel:Bool=false,bootstrap:Bool=false,deadline:Double?=nil,phase:String?=nil,scoped:Bool=false,
             activation:CodexAccessibilityActivation?=nil,composer:Bool=false) throws -> [String:Any] {
        var open:(() throws -> Void)?=nil,close:((Int) throws -> Bool)?=nil,enable:(() throws -> String)?=nil,applicationRole:(() throws -> String?)?=nil
        lastDiagnostic=bootstrap || activation != nil || composer ? CodexControlDiagnostics(now:{self.time}):nil
        if bootstrap {
            enable={self.enables+=1;self.order.append("enable");return try self.onEnable?() ?? "requested"}
            applicationRole={
                self.applicationReads+=1;self.order.append("application-role")
                if let read=self.onApplicationRole {return try read()}
                return "AXApplication"
            }
        }
        if opener {open={self.opens+=1;try self.onOpen?()}}
        if cancel {close={id in self.cancels.append(id);return try self.onCancel?(id) ?? false}}
        func readNode(_ id:Int) throws -> CodexControlNode {
            self.reads.append(id);self.order.append("window-node");self.time+=self.readAdvance;self.onRead?(id)
            guard let node=self.nodes[id] else{throw failure("CONTROL_READ_FAILED","fixture")};return node
        }
        func structureNode(_ id:Int) throws -> CodexControlNode {
            self.onStructure?(id)
            guard let node=self.nodes[id] else{throw failure("CONTROL_READ_FAILED","fixture")}
            return CodexControlNode(role:node.role,children:node.role == "AXStaticText" ? []:node.children,url:node.url)
        }
        func metadataNode(_ id:Int) throws -> CodexControlNode {
            guard let node=self.nodes[id] else {throw failure("CONTROL_READ_FAILED","fixture")}
            return CodexControlNode(role:node.role,url:node.url)
        }
        func documentFocus() -> Int? {self.documentFocusReads+=1;return self.documentFocused}
        func requireHeld() throws {
            self.holdChecks+=1
            guard self.onHold?(self.holdChecks) ?? self.held else {self.lastDiagnostic?.focusAction="cancelled";throw CodexPhysicalHoldProof.released()}
        }
        var documentRead:((Int) throws -> CodexControlNode)?=nil
        if scoped || bootstrap || composer {documentRead={id in var node=try readNode(id);if node.role == "AXWebArea" {node.children=[]};return node}}
        var resolve:((Int) throws -> Int)?=nil,readiness:((Bool) throws -> Void)?=nil
        func parent(_ id:Int) throws -> Int? {self.nodes.first(where:{$0.value.children.contains(id)})?.key}
        if composer {resolve={document in
            self.selectedDocument=document
            if let owned=self.ownedScope {
                _ = try CodexComposerSelection.ancestry(from:owned,through:document,window:0,read:readNode,parent:parent,check:{},diagnostics:self.lastDiagnostic)
                self.selectedScope=owned;self.lastDiagnostic?.scopeKind="owned-input"
                self.lastDiagnostic?.focusSource="owned";self.lastDiagnostic?.focusStage="ready";return owned
            }
            let scope:CodexComposerScope
            do {scope=try CodexComposerSelection.select(document:document,window:0,focused:self.focused,read:readNode,parent:parent,check:{},diagnostics:self.lastDiagnostic,
                metadata:metadataNode,structure:structureNode,documentFocused:documentFocus)}
            catch let error as BridgeError where error.code=="CONTROL_FOCUS_REQUIRED" && self.allowAutomatic {
                scope=try CodexComposerSelection.focusAutomatically(document:document,window:0,read:readNode,metadata:metadataNode,structure:structureNode,
                    parent:parent,check:{},diagnostics:self.lastDiagnostic,requireHeld:requireHeld,sameTarget:{guard self.current==baseline else{throw failure("CONTROL_TARGET_CHANGED","fixture")}},
                    canFocus:{_ in self.focusable},focus:{id in self.focusRequests.append(id);self.focused=id;self.onFocus?(id)},
                    focused:{self.focused},documentFocused:documentFocus,settle:{self.settles+=1})
            }
            self.selectedScope=scope.node;self.selectedEditable=scope.editable;self.lastDiagnostic?.scopeKind="focused-input";return scope.node
        }}
        if let activation=activation,phase != "up" {readiness={ready in
            if ready {self.lastDiagnostic?.actionReadiness="ready";return}
            try activation.require(identity:self.activationIdentity,now:self.time,diagnostics:self.lastDiagnostic!,activate:{self.activations+=1;return self.activationResponse})
        }}
        return try CodexControlRunner.run(action:action,initial:baseline,root:0,
            context:{self.contexts+=1;return self.onContext?(self.contexts) ?? self.current},
            read:readNode,
            press:{id in
                if self.allowAutomatic && phase != "up" {try requireHeld()}
                if composer && phase != "up" {
                    guard let scope=self.selectedScope,let editable=self.selectedEditable,
                          try CodexComposerSelection.uniqueEditable(root:scope,expected:editable,read:structureNode,check:{},diagnostics:self.lastDiagnostic) else {throw failure("CONTROL_FOCUS_REQUIRED","fixture")}
                    let chain=try CodexComposerSelection.focusedChain(document:self.selectedDocument!,window:0,focused:self.focused,
                        read:metadataNode,parent:parent,check:{},diagnostics:self.lastDiagnostic,documentFocused:documentFocus)
                    guard chain.contains(scope),chain.contains(editable) else {throw failure("CONTROL_FOCUS_REQUIRED","fixture")}
                    self.lastDiagnostic?.focusStage="ready"
                }
                self.presses.append(id);try self.onPress?(id)
            },now:{self.time},settle:{self.settles+=1;self.time+=self.settleSeconds;self.onSettle?(self.settles)},
            openModelPicker:open,cancelMenu:close,deadline:deadline,diagnostics:lastDiagnostic,prepareAccessibility:enable,readApplicationRole:applicationRole,readDocumentNode:documentRead,dictationPhase:phase,
            resolveDictationScope:resolve,resolveCommandScope:action.momentary ? {document in
                if action == .sendPrompt {
                    return try CodexComposerSelection.select(document:document,window:0,focused:self.focused,read:readNode,parent:parent,check:{},metadata:metadataNode,structure:structureNode,documentFocused:documentFocus).node
                }
                return try CodexApprovalSelection.scope(document:document,read:readNode,parent:parent,check:{})
            }:nil,ensureActionReadiness:readiness)
    }
}
let failedPreparation=CodexAccessibilityActivation()
let failedIdentity=CodexAccessibilityActivationIdentity(pid:99,launch:Date(timeIntervalSince1970:1))
let preparationDiagnostic=CodexControlDiagnostics(now:{0})
var preparationAttempts=0
func prepareAttempt(_ time:Double,_ result:String) {
    do {try failedPreparation.require(identity:failedIdentity,now:time,diagnostics:preparationDiagnostic,activate:{preparationAttempts+=1;return result})}
    catch {}
}
prepareAttempt(0,"failed")
failedPreparation.retryFailedPreparation(identity:failedIdentity,now:4);prepareAttempt(4,"accepted")
check(preparationAttempts==1,"transient AT failures use a bounded background retry")
failedPreparation.retryFailedPreparation(identity:failedIdentity,now:6);prepareAttempt(6,"accepted")
check(preparationAttempts==2,"background preparation can recover without restarting the target")
failedPreparation.retryFailedPreparation(identity:failedIdentity,now:20);prepareAttempt(20,"accepted")
check(preparationAttempts==2,"accepted AT opt-in is never repeated")
// Approval and send are never keyboard fallbacks. Only the unique visible
// compact pair / focused composer may receive one direct press.
func approvalNodes()->[Int:CodexControlNode] {
    [0:CodexControlNode(role:"AXWindow",children:[1]),
     1:CodexControlNode(role:"AXWebArea",children:[2],url:URL(string:"app://-/index.html")),
     2:CodexControlNode(role:"AXGroup",children:[3,4]),3:button("Allow once"),4:button("Deny")]
}
for (action,id) in [(CodexControlAction.approve,3),(.decline,4)] {
    let fixture=Fixture(approvalNodes())
    let result=try fixture.run(action,scoped:true)
    check(fixture.presses==[id] && result["confirmation"] as? String=="delivered","one exact press, never claim approval execution")
    fixture.nodes[3]=button("允许一次");fixture.nodes[4]=button("拒绝")
    _ = try fixture.run(action,scoped:true)
    check(fixture.presses==[id,id],"Chinese pair is supported")
}
for label in ["Always allow","Allow for this conversation","允许此对话","始终允许","请求批准","Request approval","Approve","Allow once malicious"] {
    let fixture=Fixture(approvalNodes());fixture.nodes[3]=button(label)
    expect("CONTROL_NOT_FOUND"){_ = try fixture.run(.approve,scoped:true)}
    check(fixture.presses.isEmpty,"expanded grants and substring matches are forbidden")
}
let splitPair=Fixture(approvalNodes());splitPair.nodes[1]?.children=[2,5];splitPair.nodes[2]?.children=[3];splitPair.nodes[5]=CodexControlNode(role:"AXGroup",children:[4])
expect("CONTROL_NOT_FOUND"){_ = try splitPair.run(.approve,scoped:true)}
let manyApprovals=Fixture(approvalNodes());manyApprovals.nodes[2]?.children.append(5);manyApprovals.nodes[5]=button("Allow once")
expect("CONTROL_AMBIGUOUS"){_ = try manyApprovals.run(.approve,scoped:true)}
let disabledApprove=Fixture(approvalNodes());disabledApprove.nodes[3]?.enabled=false
check(try disabledApprove.run(.approve,scoped:true)["performed"] as? Bool==false,"disabled approval is not pressed")
let changedApprove=Fixture(approvalNodes());var pairReads=0
changedApprove.onRead={id in if id==4 {pairReads+=1;if pairReads==2 {changedApprove.nodes[4]=button("Cancel")}}}
expect("CONTROL_NOT_FOUND"){_ = try changedApprove.run(.approve,scoped:true)}
check(changedApprove.presses.isEmpty,"changing approval pair cancels before delivery")
let sendFixture=Fixture([0:CodexControlNode(role:"AXWindow",children:[1]),1:CodexControlNode(role:"AXWebArea",children:[2],url:URL(string:"app://-/index.html")),2:CodexControlNode(role:"AXGroup",children:[3,4,5]),3:CodexControlNode(role:"AXTextArea"),4:button("Dictate"),5:button("Send")])
sendFixture.focused=3
check(try sendFixture.run(.sendPrompt,scoped:true)["performed"] as? Bool==true,"focused composer send works without bindings")
check(sendFixture.presses==[5],"only send control receives press")
sendFixture.focused=nil
expect("CONTROL_FOCUS_REQUIRED"){_ = try sendFixture.run(.sendPrompt,scoped:true)}
sendFixture.focused=3
for label in ["Stop","Resume","Finish dictation and send","发送消息？","Send to all"] {
    sendFixture.nodes[5]=button(label)
    expect("CONTROL_NOT_FOUND"){_ = try sendFixture.run(.sendPrompt,scoped:true)}
}
check(sendFixture.presses==[5],"no stop/resume/other destination or fallback Enter")
func verify(_ result:[String:Any],_ performed:Bool,_ state:String,_ confirmation:String) {
    check(result["performed"] as? Bool==performed,"performed is accurate")
    check(result["observedState"] as? String==state,"observed state is bounded and accurate")
    check(result["confirmation"] as? String==confirmation,"delivery is distinct from state observation")
    check(Set(result.keys).isSubset(of:["performed","observedState","confirmation","menuOpened","menuDismissed","controlDiagnostic","released"]),"no labels, chat text, values or identifiers are returned")
}

for (start,finish) in [("Dictate","Stop dictation"),("听写","停止听写")] {
    let value=Fixture(basic(start));value.onPress={id in value.nodes[id]=button(finish)}
    verify(try value.run(.dictation),true,"recording","observed")
    check(value.presses==[1],"one microphone start press")
    let stop=Fixture(basic(finish));stop.onPress={id in stop.nodes[id]=button(start)}
    verify(try stop.run(.dictation),true,"idle","observed")
    check(stop.presses==[1],"one microphone stop press")
}
for (label,state) in [("Starting dictation; click to cancel","starting"),("正在启动听写；点击可取消","starting"),("Finishing dictation","finishing"),("正在完成听写","finishing")] {
    let value=Fixture(basic(label));verify(try value.run(.dictation),false,state,"not-performed")
    check(value.presses.isEmpty,"starting or finishing never gets another press")
}
let disabled=Fixture(basic("Dictate",false));verify(try disabled.run(.dictation),false,"disabled","not-performed");check(disabled.presses.isEmpty,"disabled microphone not pressed")
let noAction=Fixture(basic("Dictate"));noAction.nodes[1]?.actions=[]
verify(try noAction.run(.dictation),false,"not-operable","not-performed")
for label in ["Start voice chat","开启语音聊天","Mute microphone","取消麦克风静音","End voice chat","Retry dictation","Dictate now"," Dictate"] {
    let value=Fixture(basic(label));expect("CONTROL_NOT_FOUND"){_ = try value.run(.dictation)};check(value.presses.isEmpty,"no fuzzy or voice-chat fallback")
}
let wrongRole=Fixture(basic("Dictate",true,"AXCheckBox"));expect("CONTROL_NOT_FOUND"){_ = try wrongRole.run(.dictation)}
let ambiguous=Fixture([0:CodexControlNode(role:"AXWindow",children:[1,2]),1:button("Dictate"),2:button("听写",false)])
expect("CONTROL_AMBIGUOUS"){_ = try ambiguous.run(.dictation)};check(ambiguous.presses.isEmpty,"even disabled duplicate context fails closed")
let conflict=Fixture(basic("Dictate"));conflict.nodes[1]?.description="Stop dictation"
expect("CONTROL_AMBIGUOUS"){_ = try conflict.run(.dictation)}

for raw in ["https://example.test/","http://localhost/","app://fs/index.html","app://evil/index.html","app://-/other.html",""] {
    let value=Fixture([0:CodexControlNode(role:"AXWindow",children:[1]),1:CodexControlNode(role:"AXWebArea",children:[99],url:URL(string:raw)),99:button("Dictate")])
    expect("CONTROL_NOT_FOUND"){_ = try value.run(.dictation)}
    check(!value.reads.contains(99),"untrusted web-area descendants are not read")
}
for raw in ["app://-/index.html?initialRoute=%2Fthreads%2Ffixture","app://-/detached-window.html"] {
    let value=Fixture([0:CodexControlNode(role:"AXWindow",children:[1]),1:CodexControlNode(role:"AXWebArea",children:[2,3],url:URL(string:raw)),2:button("Dictate"),3:CodexControlNode(role:"AXWebArea",children:[99],url:URL(string:"https://example.test/")),99:button("Dictate")])
    value.onPress={id in value.nodes[id]=button("Stop dictation")}
    verify(try value.run(.dictation),true,"recording","observed")
    check(!value.reads.contains(99),"nested external web area is excluded")
}
let text=Fixture([0:CodexControlNode(role:"AXWindow",children:[1,2]),1:CodexControlNode(role:"AXTextArea",children:[99]),2:button("Dictate"),99:button("Dictate")])
text.onPress={id in text.nodes[id]=button("Stop dictation")};_ = try text.run(.dictation)
check(!text.reads.contains(99),"editable content is never traversed")
let cycle=Fixture([0:CodexControlNode(role:"AXWindow",children:[1,2]),1:CodexControlNode(role:"AXGroup",children:[0]),2:button("Dictate")])
cycle.onPress={id in cycle.nodes[id]=button("Stop dictation")};_ = try cycle.run(.dictation);check(cycle.presses==[2],"cycles do not duplicate candidates")
var large=[0:CodexControlNode(role:"AXWindow",children:Array(1...4096))]
for id in 1...4096 {large[id]=CodexControlNode(role:"AXGroup")}
let bounded=Fixture(large);expect("CONTROL_SCAN_LIMIT"){_ = try bounded.run(.dictation)}
check(bounded.reads.count<=4096 && bounded.presses.isEmpty,"node bound fails before pressing")
var deep=[Int:CodexControlNode]()
for id in 0...66 {deep[id]=CodexControlNode(role:"AXGroup",children:id==66 ? []:[id+1])}
deep[66]=button("Dictate")
let depth=Fixture(deep);expect("CONTROL_SCAN_LIMIT"){_ = try depth.run(.dictation)}
let timeout=Fixture(large);timeout.readAdvance=0.2;expect("CONTROL_SCAN_LIMIT"){_ = try timeout.run(.dictation)};check(timeout.presses.isEmpty,"time bound fails before pressing")
for changed in [CodexControlContext(bundleID:"com.openai.codex",pid:43,window:0),CodexControlContext(bundleID:"com.openai.codex",pid:42,window:1),CodexControlContext(bundleID:"other.application",pid:42,window:0)] {
    let value=Fixture(basic("Dictate"));value.onContext={count in count<3 ? baseline:changed}
    expect("CONTROL_TARGET_CHANGED"){_ = try value.run(.dictation)};check(value.presses.isEmpty,"changed foreground identity cannot receive a press")
}
let changedNode=Fixture(basic("Dictate"));var targetReads=0
changedNode.onRead={id in if id==1 {targetReads+=1;if targetReads==2 {changedNode.nodes[1]=button("Stop dictation")}}}
expect("CONTROL_TARGET_CHANGED"){_ = try changedNode.run(.dictation)}
let rejected=Fixture(basic("Dictate"));rejected.onPress={_ in throw failure("CONTROL_PRESS_FAILED","fixture")}
expect("CONTROL_PRESS_FAILED"){_ = try rejected.run(.dictation)};check(rejected.presses.count==1,"a rejected press is not retried")
let delayed=Fixture(basic("Dictate"));verify(try delayed.run(.dictation),true,"idle","delivered");check(delayed.presses.count==1,"no state confirmation means delivered only")
let changedAfter=Fixture(basic("Dictate"));changedAfter.onPress={_ in changedAfter.current=nil}
verify(try changedAfter.run(.dictation),true,"unknown","delivered")

for (label,next) in [("Enable fast mode","Enable standard mode"),("启用标准模式","启用快速模式")] {
    let value=Fixture([0:CodexControlNode(role:"AXWindow",children:[1]),1:CodexControlNode(role:"AXMenu",actions:["AXCancel"],children:[2]),2:button(label,true,"AXMenuItem")])
    value.onPress={id in value.nodes[id]=button(next,true,"AXMenuItem")}
    let result=try value.run(.toggleFastMode,opener:true,cancel:true)
    verify(result,true,label=="Enable fast mode" ? "fast":"standard","observed")
    check(value.opens==0 && value.cancels.isEmpty,"an already-open user menu is never opened or dismissed")
}
let noFast=Fixture(basic("Enable ultrafast mode",true,"AXMenuItem"));expect("CONTROL_NOT_FOUND"){_ = try noFast.run(.toggleFastMode)}
check(noFast.presses.isEmpty,"Ultrafast is never a strict two-state fallback")
let fastDisabled=Fixture(basic("Enable fast mode",false,"AXCheckBox"));verify(try fastDisabled.run(.toggleFastMode,opener:true),false,"disabled","not-performed");check(fastDisabled.opens==0,"disabled speed control does not open another menu")
let fastAmbiguous=Fixture([0:CodexControlNode(role:"AXWindow",children:[1,2]),1:button("Enable fast mode"),2:button("Enable standard mode")])
expect("CONTROL_AMBIGUOUS"){_ = try fastAmbiguous.run(.toggleFastMode,opener:true)};check(fastAmbiguous.opens==0,"ambiguous speed controls do not invoke an opener")

let picker=Fixture([0:CodexControlNode(role:"AXWindow",children:[1]),1:CodexControlNode(role:"AXButton",title:"model-name",help:"选择模型",enabled:true,actions:["AXPress"])])
picker.onPress={id in
    if id==1 {picker.nodes[0]?.children=[1,3];picker.nodes[3]=CodexControlNode(role:"AXMenu",actions:["AXCancel"],children:[2]);picker.nodes[2]=button("启用快速模式",true,"AXCheckBox")}
    else {picker.nodes[id]=button("启用标准模式",true,"AXCheckBox")}
}
picker.onCancel={id in picker.nodes[0]?.children=[1];return true}
let opened=try picker.run(.toggleFastMode,opener:true,cancel:true)
verify(opened,true,"fast","observed")
check(picker.presses==[1,2] && picker.opens==0,"exact Help label opens once, then presses only the two-state target")
check(picker.cancels==[3] && opened["menuOpened"] as? Bool==true && opened["menuDismissed"] as? Bool==true,"only the owned closest menu is cancelled and disappearance is observed")
let fallback=Fixture([0:CodexControlNode(role:"AXWindow")])
fallback.onOpen={fallback.nodes[0]?.children=[3];fallback.nodes[3]=CodexControlNode(role:"AXMenu",children:[2]);fallback.nodes[2]=button("Enable fast mode",true,"AXMenuItem")}
fallback.onPress={id in fallback.nodes[id]=button("Enable standard mode",true,"AXMenuItem")}
let fallbackResult=try fallback.run(.toggleFastMode,opener:true,cancel:true)
check(fallback.opens==1 && fallback.presses==[2] && fallbackResult["menuDismissed"] as? Bool==false,"normal shortcut opener is used once; an unsupported cancel leaves the menu")
let fakeCancel=Fixture([0:CodexControlNode(role:"AXWindow")])
fakeCancel.onOpen={fakeCancel.nodes[0]?.children=[3];fakeCancel.nodes[3]=CodexControlNode(role:"AXMenu",children:[2]);fakeCancel.nodes[2]=button("Enable fast mode")}
fakeCancel.onPress={id in fakeCancel.nodes[id]=button("Enable standard mode")};fakeCancel.onCancel={_ in true}
let stillOpen=try fakeCancel.run(.toggleFastMode,opener:true,cancel:true)
check(stillOpen["menuDismissed"] as? Bool==false,"AXCancel acceptance alone is not menu-dismissal confirmation")
let unavailablePicker=Fixture(basic("Select model",false));expect("CONTROL_NOT_OPERABLE"){_ = try unavailablePicker.run(.toggleFastMode,opener:true)};check(unavailablePicker.opens==0,"disabled picker does not fall back")
let duplicatePicker=Fixture([0:CodexControlNode(role:"AXWindow",children:[1,2]),1:button("Select model"),2:button("选择模型")])
expect("CONTROL_AMBIGUOUS"){_ = try duplicatePicker.run(.toggleFastMode,opener:true)};check(duplicatePicker.opens==0,"ambiguous picker does not fall back")
let unopened=Fixture([0:CodexControlNode(role:"AXWindow")]);expect("CONTROL_NOT_FOUND"){_ = try unopened.run(.toggleFastMode,opener:true)}
check(unopened.opens==1 && unopened.settles==4 && unopened.presses.isEmpty,"menu wait is bounded and opener never repeats")
// The production bootstrap uses the same pure runner with injected readers
// and opt-in closures. No fixture ever calls the real adapter or its AX setter.
func trusted(_ label:String)->[Int:CodexControlNode] {
    [0:CodexControlNode(role:"AXWindow",children:[1]),
     1:CodexControlNode(role:"AXWebArea",children:[2],url:URL(string:"app://-/index.html?private-fixture-query")),
     2:button(label)]
}
let diagnosticFields:Set<String>=["enableStatus","visitedNodes","webAreasSeen","trustedWebAreas","missingURLWebAreas","rejectedURLWebAreas","buttonCount","menuCount","matchCount","elapsedMs","scanLimited","limitReason","actionReadiness","warmupRemainingMs","activationResponse","scopeKind","focusSource","focusStage","focusRole","focusDepth","focusHasDocument","focusHasWindow","focusAction"]
func checkDiagnostic(_ diagnostic:[String:Any],_ status:String) {
    check(Set(diagnostic.keys)==diagnosticFields,"diagnostics expose only the exact fixed schema")
    check(diagnostic["enableStatus"] as? String==status,"enable status is a fixed enum")
    for field in diagnosticFields.subtracting(["enableStatus","scanLimited","limitReason","actionReadiness","activationResponse","scopeKind","focusSource","focusStage","focusRole","focusHasDocument","focusHasWindow","focusAction"]) {
        let value=diagnostic[field] as? Int
        check(value != nil && value! >= 0 && value! <= (field == "elapsedMs" ? 2000:field == "warmupRemainingMs" ? 3000:field == "focusDepth" ? 64:4096),"diagnostic count/duration is a bounded integer")
    }
    check(diagnostic["scanLimited"] is Bool,"scan-limited is a boolean")
    check(["none","nodes","depth","children","time"].contains(diagnostic["limitReason"] as! String),"limit reason has only fixed enumerators")
    check(["warming","ready","unavailable","unknown"].contains(diagnostic["actionReadiness"] as! String),"action readiness is a fixed enum")
    check(["not-requested","accepted","unsupported","denied","failed"].contains(diagnostic["activationResponse"] as! String),"activation response is a fixed enum")
    check(["none","document","focused-input","owned-input"].contains(diagnostic["scopeKind"] as! String),"scope kind contains no element identity or label")
    check(["none","application","document","owned"].contains(diagnostic["focusSource"] as! String),"focus source is a fixed enum")
    check(["unknown","missing","outside-document","container","editable-missing","scope-rejected","ready"].contains(diagnostic["focusStage"] as! String),"focus stage is a fixed enum")
    check(["none","text-area","text-field","web-area","group","scroll-area","window","button","search-field","secure-field","other"].contains(diagnostic["focusRole"] as! String),"focus role is a fixed category rather than raw metadata")
    check(diagnostic["focusHasDocument"] is Bool && diagnostic["focusHasWindow"] is Bool,"focus ancestry reports only boolean membership")
    check(["none","requested","confirmed","failed","cancelled"].contains(diagnostic["focusAction"] as! String),"focus action is a fixed bounded enum")
    let encoded=String(data:try! JSONSerialization.data(withJSONObject:diagnostic),encoding:.utf8)!
    check(!["private-fixture","Dictate","Stop dictation","app://","fixture-label","AXButton"].contains(where:{encoded.contains($0)}),"no labels, URLs, roles, text, process IDs or element IDs leak")
}
let already=Fixture(trusted("Dictate"));already.onPress={id in already.nodes[id]=button("Stop dictation")}
already.nodes[1]?.children.append(3);already.nodes[3]=CodexControlNode(role:"AXButton",title:"fixture-label-private",help:"private-fixture-help")
let alreadyResult=try already.run(.dictation,bootstrap:true)
verify(alreadyResult,true,"recording","observed")
check(already.enables==0 && already.presses==[2],"an already exposed trusted tree never requests another opt-in")
checkDiagnostic(alreadyResult["controlDiagnostic"] as! [String:Any],"already-enabled")

check(already.applicationReads==1 && already.order.firstIndex(of:"application-role")! < already.order.firstIndex(of:"window-node")!,"application AXRole is read before the first window traversal")

let roleTree=Fixture([0:CodexControlNode(role:"AXWindow",children:[1]),1:CodexControlNode(role:"AXScrollArea")])
var rootRoleSeen=false,containerRoleSeen=false
roleTree.onApplicationRole={rootRoleSeen=true;return "AXApplication"}
roleTree.onRead={id in
    check(rootRoleSeen,"no window node is read before the application role")
    if id==1 {containerRoleSeen=true}
}
roleTree.onEnable={"unsupported"}
roleTree.onSettle={count in
    if count==1 && containerRoleSeen {
        roleTree.nodes[1]?.children=[2]
        roleTree.nodes[2]=CodexControlNode(role:"AXWebArea",children:[3],url:URL(string:"app://-/index.html"))
        roleTree.nodes[3]=button("Dictate")
    }
}
roleTree.onPress={id in roleTree.nodes[id]=button("Stop dictation")}
let roleResult=try roleTree.run(.dictation,bootstrap:true)
verify(roleResult,true,"recording","observed")
check(roleTree.applicationReads==1 && containerRoleSeen && roleTree.presses==[3],"root and scroll-container role requests allow an asynchronous basic renderer tree")
checkDiagnostic(roleResult["controlDiagnostic"] as! [String:Any],"unsupported")

let changedBeforeRoot=Fixture(trusted("Dictate"))
changedBeforeRoot.onContext={count in count<2 ? baseline:CodexControlContext(bundleID:"com.openai.codex",pid:43,window:0)}
expect("CONTROL_TARGET_CHANGED"){_ = try changedBeforeRoot.run(.dictation,bootstrap:true)}
check(changedBeforeRoot.applicationReads==0 && changedBeforeRoot.reads.isEmpty && changedBeforeRoot.enables==0 && changedBeforeRoot.presses.isEmpty,"changed context before root-role request fails without reading the root or window")
let changedAfterRoot=Fixture(trusted("Dictate"))
changedAfterRoot.onApplicationRole={changedAfterRoot.current=CodexControlContext(bundleID:"com.openai.codex",pid:42,window:1);return "AXApplication"}
expect("CONTROL_TARGET_CHANGED"){_ = try changedAfterRoot.run(.dictation,bootstrap:true)}
check(changedAfterRoot.applicationReads==1 && changedAfterRoot.reads.isEmpty && changedAfterRoot.enables==0 && changedAfterRoot.presses.isEmpty,"changed context after root-role request fails before any window traversal")
for role:String? in ["AXWindow",nil] {
    let wrongRoot=Fixture(trusted("Dictate"));wrongRoot.onApplicationRole={role}
    expect("CONTROL_NOT_FOUND"){_ = try wrongRoot.run(.dictation,bootstrap:true)}
    check(wrongRoot.applicationReads==1 && wrongRoot.reads.isEmpty && wrongRoot.enables==0 && wrongRoot.presses.isEmpty,"only the exact AXApplication root can authorize traversal")
}

let treeDelay=Fixture([0:CodexControlNode(role:"AXWindow")])
treeDelay.onSettle={count in if count==2 {treeDelay.nodes=trusted("Dictate")}}
treeDelay.onPress={id in treeDelay.nodes[id]=button("Stop dictation")}
let treeDelayResult=try treeDelay.run(.dictation,bootstrap:true)
verify(treeDelayResult,true,"recording","observed")
check(treeDelay.enables==1 && treeDelay.presses==[2] && treeDelay.settles>=2,"one opt-in waits for a delayed renderer tree, then one control press")
checkDiagnostic(treeDelayResult["controlDiagnostic"] as! [String:Any],"requested")

let unsupported=Fixture([0:CodexControlNode(role:"AXWindow")])
unsupported.onEnable={unsupported.nodes=trusted("Dictate");return "unsupported"}
unsupported.onPress={id in unsupported.nodes[id]=button("Stop dictation")}
let unsupportedResult=try unsupported.run(.dictation,bootstrap:true)
verify(unsupportedResult,true,"recording","observed")
check(unsupported.enables==1 && unsupported.presses==[2],"unsupported setter does not reject an independently readable trusted tree")
checkDiagnostic(unsupportedResult["controlDiagnostic"] as! [String:Any],"unsupported")

let neverReady=Fixture([0:CodexControlNode(role:"AXWindow")]);neverReady.onEnable={"failed"}
expect("CONTROL_NOT_FOUND"){_ = try neverReady.run(.toggleFastMode,opener:true,bootstrap:true)}
check(neverReady.enables==1 && neverReady.settles==4 && neverReady.presses.isEmpty && neverReady.opens==0,"unready renderer neither retries the opt-in nor invokes a blind menu opener")
checkDiagnostic(neverReady.lastDiagnostic!.snapshot,"failed")

let changedBootstrap=Fixture([0:CodexControlNode(role:"AXWindow")])
changedBootstrap.onEnable={changedBootstrap.current=CodexControlContext(bundleID:"com.openai.codex",pid:42,window:1);return "requested"}
expect("CONTROL_TARGET_CHANGED"){_ = try changedBootstrap.run(.dictation,bootstrap:true)}
check(changedBootstrap.enables==1 && changedBootstrap.presses.isEmpty,"changed target during opt-in receives no control press")

let timedBootstrap=Fixture([0:CodexControlNode(role:"AXWindow")]);timedBootstrap.readAdvance=0.3
timedBootstrap.onSettle={count in if count==1 {timedBootstrap.nodes=trusted("Dictate")}}
expect("CONTROL_SCAN_LIMIT"){_ = try timedBootstrap.run(.dictation,bootstrap:true,deadline:0.5)}
check(timedBootstrap.enables==1 && timedBootstrap.presses.isEmpty,"bootstrap shares the original deadline instead of obtaining a fresh control budget")
check(timedBootstrap.lastDiagnostic!.snapshot["scanLimited"] as? Bool==true,"deadline failures are structurally diagnosed")

let missingURL=Fixture([0:CodexControlNode(role:"AXWindow",children:[1]),1:CodexControlNode(role:"AXWebArea",children:[99]),99:button("Dictate")])
expect("CONTROL_NOT_FOUND"){_ = try missingURL.run(.dictation,bootstrap:true)}
check(missingURL.lastDiagnostic!.snapshot["missingURLWebAreas"] as? Int==1 && !missingURL.reads.contains(99),"missing AX URL is diagnosed without loosening trust or reading its descendants")
let rejectedURL=Fixture([0:CodexControlNode(role:"AXWindow",children:[1]),1:CodexControlNode(role:"AXWebArea",children:[99],url:URL(string:"https://private-fixture.invalid/")),99:button("Dictate")])
expect("CONTROL_NOT_FOUND"){_ = try rejectedURL.run(.dictation,bootstrap:true)}
check(rejectedURL.lastDiagnostic!.snapshot["rejectedURLWebAreas"] as? Int==1 && !rejectedURL.reads.contains(99),"foreign AX URL is diagnosed without loosening trust")

let pendingAfterPress=Fixture(trusted("Dictate"))
let pendingResult=try pendingAfterPress.run(.dictation,bootstrap:true)
verify(pendingResult,true,"idle","delivered")
check(pendingAfterPress.presses==[2] && pendingAfterPress.enables==0,"an unconfirmed delivered press is never repeated by bootstrap or observation")
var boundedError=failure("CONTROL_NOT_FOUND","fixture")
boundedError.controlDiagnostic=neverReady.lastDiagnostic!.snapshot
check(Set(boundedError.json.keys)==["code","message","controlDiagnostic"],"production BridgeError serializes the optional structural snapshot")
checkDiagnostic(boundedError.json["controlDiagnostic"] as! [String:Any],"failed")
let absentDiagnostic=failure("OTHER","fixture")
check(Set(absentDiagnostic.json.keys)==["code","message"],"unrelated bridge errors preserve their original schema")

// Production selection first establishes a unique trusted renderer root.
let outside=Fixture([0:CodexControlNode(role:"AXWindow",children:[1,9]),1:CodexControlNode(role:"AXWebArea",children:[2],url:URL(string:"app://-/index.html")),2:button("Dictate"),9:button("Dictate")])
outside.onPress={id in outside.nodes[id]=button("Stop dictation")}
verify(try outside.run(.dictation,scoped:true),true,"recording","observed")
check(outside.presses==[2],"outside native chrome never becomes a composer control")
let twoDocuments=Fixture([0:CodexControlNode(role:"AXWindow",children:[1,3]),1:CodexControlNode(role:"AXWebArea",children:[2],url:URL(string:"app://-/index.html")),2:button("Dictate"),3:CodexControlNode(role:"AXWebArea",children:[4],url:URL(string:"app://-/detached-window.html")),4:button("Dictate")])
expect("CONTROL_AMBIGUOUS"){_ = try twoDocuments.run(.dictation,scoped:true)}
check(twoDocuments.presses.isEmpty && !twoDocuments.reads.contains(2) && !twoDocuments.reads.contains(4),"document discovery does not descend into either renderer before rejecting ambiguity")
let chromeOnly=Fixture(basic("Dictate"));expect("CONTROL_NOT_FOUND"){_ = try chromeOnly.run(.dictation,scoped:true)}
check(chromeOnly.presses.isEmpty,"matching native chrome cannot substitute for a trusted renderer")

var roomy=trusted("Dictate")
roomy[1]?.children=Array(2...3002)
for id in 3...3002 {roomy[id]=CodexControlNode(role:"AXGroup")}
let manyNodes=Fixture(roomy);manyNodes.onPress={id in manyNodes.nodes[id]=button("Stop dictation")}
verify(try manyNodes.run(.dictation,bootstrap:true),true,"recording","observed")
check(manyNodes.presses==[2] && manyNodes.lastDiagnostic!.snapshot["scanLimited"] as? Bool==false,"a substantial chat below 4096 nodes is supported without dropping duplicate checking")
var longPath=trusted("Dictate")
longPath[1]?.children=[3]
for id in 3...45 {longPath[id]=CodexControlNode(role:"AXGroup",children:id==45 ? [2]:[id+1])}
let nestedComposer=Fixture(longPath);nestedComposer.onPress={id in nestedComposer.nodes[id]=button("Stop dictation")}
verify(try nestedComposer.run(.dictation,bootstrap:true),true,"recording","observed")
check(nestedComposer.presses==[2],"deep but bounded composer nesting is supported")
var excessive=trusted("Dictate");excessive[1]?.children=Array(2...4097)
for id in 2...4097 {excessive[id]=CodexControlNode(role:"AXGroup")}
let nodeLimited=Fixture(excessive);expect("CONTROL_SCAN_LIMIT"){_ = try nodeLimited.run(.dictation,bootstrap:true)}
check(nodeLimited.lastDiagnostic!.limitReason=="nodes" && nodeLimited.presses.isEmpty,"node limit is diagnosed without any press")
excessive[1]?.children=Array(2...4098);excessive[4098]=CodexControlNode(role:"AXGroup")
let childLimited=Fixture(excessive);expect("CONTROL_SCAN_LIMIT"){_ = try childLimited.run(.dictation,bootstrap:true)}
check(childLimited.lastDiagnostic!.limitReason=="children" && childLimited.presses.isEmpty,"children prefetch/queue limit is distinguished")
var depthTree=trusted("Dictate");depthTree[1]?.children=[3]
for id in 3...70 {depthTree[id]=CodexControlNode(role:"AXGroup",children:id==70 ? [2]:[id+1])}
let deepLimited=Fixture(depthTree);expect("CONTROL_SCAN_LIMIT"){_ = try deepLimited.run(.dictation,bootstrap:true)}
check(deepLimited.lastDiagnostic!.limitReason=="depth" && deepLimited.presses.isEmpty,"depth64 limit is distinguished")
let timeLimited=Fixture(trusted("Dictate"));timeLimited.readAdvance=0.3
expect("CONTROL_SCAN_LIMIT"){_ = try timeLimited.run(.dictation,bootstrap:true)}
check(timeLimited.lastDiagnostic!.limitReason=="time" && timeLimited.presses.isEmpty,"time remains independently bounded")

// Hold ownership is local and never treats a pre-existing manual recording as ours.
let firstOwner="11111111-1111-4111-8111-111111111111",secondOwner="22222222-2222-4222-8222-222222222222"
for command:[String:Any] in [["phase":"tap","owner":firstOwner],["phase":"down"],["phase":"up","owner":"not-a-private-owner"]] {
    expect("INVALID_CONTROL"){_ = try CodexDictationOwnership.request(command)}
}
check(try CodexDictationOwnership.request(["phase":"down","owner":firstOwner]).phase=="down","only down/up private-owner gestures are accepted")
final class HoldFixture {
    let target:Fixture
    let ownership=CodexDictationOwnership()
    init(_ target:Fixture){self.target=target}
    func down(_ owner:String) throws -> [String:Any] {
        _ = try CodexDictationOwnership.request(["phase":"down","owner":owner])
        if ownership.activeOwner != nil {return ["performed":false,"released":false]}
        let result=try target.run(.dictation,phase:"down",scoped:true)
        _ = ownership.claim(owner:owner,context:baseline,performed:result["performed"] as? Bool == true)
        return result
    }
    func up(_ owner:String) throws -> [String:Any] {
        _ = try CodexDictationOwnership.request(["phase":"up","owner":owner])
        guard ownership.take(owner:owner) != nil else{return ["performed":false,"released":false]}
        return try target.run(.dictation,phase:"up",scoped:true)
    }
}
let holdTarget=Fixture(trusted("Dictate"));holdTarget.onPress={id in holdTarget.nodes[id]=button(holdTarget.nodes[id]?.title == "Dictate" ? "Stop dictation":"Dictate")}
let hold=HoldFixture(holdTarget)
let downResult=try hold.down(firstOwner);verify(downResult,true,"recording","observed")
check(downResult["released"] as? Bool==false && hold.ownership.activeOwner==firstOwner,"actual start press owns the private hold")
let readsBeforeDuplicate=holdTarget.reads.count
check(try hold.down(firstOwner)["performed"] as? Bool==false && holdTarget.reads.count==readsBeforeDuplicate,"duplicate down neither reads nor presses again")
check(try hold.up(secondOwner)["released"] as? Bool==false && holdTarget.presses.count==1,"another owner cannot release this capture")
let upResult=try hold.up(firstOwner);verify(upResult,true,"idle","observed")
check(upResult["released"] as? Bool==true && hold.ownership.activeOwner==nil && holdTarget.presses==[2,2],"release ends only the recording initiated by that hold")
let readsAfterRelease=holdTarget.reads.count
check(try hold.up(firstOwner)["released"] as? Bool==false && holdTarget.reads.count==readsAfterRelease,"duplicate release does not inspect or press")
_ = try hold.down(secondOwner)
check(try hold.up(firstOwner)["released"] as? Bool==false && hold.ownership.activeOwner==secondOwner,"a delayed old release cannot consume a newer hold")
_ = try hold.up(secondOwner)

let manualTarget=Fixture(trusted("Stop dictation")),manual=HoldFixture(manualTarget)
let manualDown=try manual.down(firstOwner)
check(manualDown["performed"] as? Bool==false && manual.ownership.activeOwner==nil && manualTarget.presses.isEmpty,"down never toggles or claims existing manual dictation")
let manualReads=manualTarget.reads.count
check(try manual.up(firstOwner)["released"] as? Bool==false && manualTarget.reads.count==manualReads,"up cannot stop manual recording without an owned start")
let quickTarget=Fixture(trusted("Dictate")),quick=HoldFixture(quickTarget)
quickTarget.onPress={id in quickTarget.nodes[id]=button(quickTarget.nodes[id]?.title == "Dictate" ? "Starting dictation; click to cancel":"Dictate")}
_ = try quick.down(firstOwner)
let quickUp=try quick.up(firstOwner)
check(quickUp["performed"] as? Bool==true && quickUp["released"] as? Bool==true && quickTarget.presses.count==2,"a quick release cancels only the exact starting control from our own hold")
for state in ["Dictate","Finishing dictation"] {
    let target=Fixture(trusted("Dictate")),held=HoldFixture(target)
    target.onPress={id in target.nodes[id]=button(state)}
    _ = try held.down(firstOwner);let before=target.presses.count
    let released=try held.up(firstOwner)
    check(released["released"] as? Bool==true && released["performed"] as? Bool==false && target.presses.count==before,"an already ended/finishing owned capture is released without a second press")
}
let blockedTarget=Fixture(trusted("Dictate")),blockedHold=HoldFixture(blockedTarget)
blockedTarget.onPress={id in blockedTarget.nodes[id]=button("Stop dictation",false)}
_ = try blockedHold.down(firstOwner);let blockedUp=try blockedHold.up(firstOwner)
check(blockedUp["released"] as? Bool==false && blockedUp["performed"] as? Bool==false && blockedHold.ownership.activeOwner==nil,"unavailable owned stop warns manual completion and clears ownership")
let failureTarget=Fixture(trusted("Dictate")),failedHold=HoldFixture(failureTarget)
failureTarget.onPress={_ in throw failure("CONTROL_PRESS_FAILED","fixture")}
expect("CONTROL_PRESS_FAILED"){_ = try failedHold.down(firstOwner)}
let failedUp=try failedHold.up(firstOwner)
check(failedHold.ownership.activeOwner==nil && failedUp["released"] as? Bool==false,"failed start never grants release ownership")
let switchedTarget=Fixture(trusted("Dictate")),switched=HoldFixture(switchedTarget)
switchedTarget.onPress={id in switchedTarget.nodes[id]=button("Stop dictation")}
_ = try switched.down(firstOwner);switchedTarget.current=CodexControlContext(bundleID:"com.openai.codex",pid:42,window:1)
expect("CONTROL_TARGET_CHANGED"){_ = try switched.up(firstOwner)}
check(switched.ownership.activeOwner==nil && switchedTarget.presses.count==1,"changed window is not pressed and release ownership is consumed")
let launched=Date(timeIntervalSince1970:100)
check(CodexControlTargetIdentity.valid(expected:baseline,current:baseline,expectedLaunch:launched,currentLaunch:launched,sameWindow:true,isForeground:false,requiresForeground:false),"owned stop may end the same original background window without activation")
check(!CodexControlTargetIdentity.valid(expected:baseline,current:baseline,expectedLaunch:launched,currentLaunch:launched,sameWindow:true,isForeground:false,requiresForeground:true),"start and F7 still require the foreground target")
check(!CodexControlTargetIdentity.valid(expected:baseline,current:baseline,expectedLaunch:launched,currentLaunch:Date(timeIntervalSince1970:200),sameWindow:true,isForeground:true,requiresForeground:false),"PID reuse or process restart cannot inherit ownership")
check(!CodexControlTargetIdentity.valid(expected:baseline,current:baseline,expectedLaunch:launched,currentLaunch:launched,sameWindow:false,isForeground:true,requiresForeground:false),"another window cannot receive an owned stop")
check(!CodexControlTargetIdentity.valid(expected:baseline,current:baseline,expectedLaunch:nil,currentLaunch:nil,sameWindow:true,isForeground:true,requiresForeground:false),"background release requires a process launch identity")
let uncertainTarget=Fixture(trusted("Dictate")),uncertain=HoldFixture(uncertainTarget)
uncertainTarget.onPress={id in uncertainTarget.nodes.removeValue(forKey:id)}
let uncertainDown=try uncertain.down(firstOwner)
check(uncertainDown["performed"] as? Bool==true && uncertainDown["observedState"] as? String=="unknown" && uncertain.ownership.activeOwner==firstOwner && uncertainTarget.presses.count==1,"a delivered start with failed observation remains owned for its physical release")
uncertainTarget.nodes[2]=button("Stop dictation");uncertainTarget.onPress={id in uncertainTarget.nodes[id]=button("Dictate")}
let recoveredRelease=try uncertain.up(firstOwner)
check(recoveredRelease["released"] as? Bool==true && uncertainTarget.presses.count==2 && uncertain.ownership.activeOwner==nil,"the subsequent owned release can stop after a failed start observation without retrying the start")
for state in ["idle","finishing"] {
    check(CodexDictationOwnership.releaseConfirmed(["released":true,"observedState":state]),"EOF cleanup accepts only observed idle/finishing")
}
for state in ["unknown","recording","starting","disabled"] {
    check(!CodexDictationOwnership.releaseConfirmed(["released":true,"observedState":state]),"an accepted stop without end-state observation is not a confirmed EOF cleanup")
}
check(!CodexDictationOwnership.releaseConfirmed(["released":false,"observedState":"idle"]),"unowned idle does not masquerade as released ownership")

// AXPress initiates stop asynchronously. The same owned scope can keep its
// recording label, briefly unmount its button, or show finishing before idle.
for (startLabel,stopLabel,endLabel) in [("Dictate","Stop dictation","Dictate"),("听写","停止听写","正在完成听写")] {
    for delay in [3,12,25] {
        let target=Fixture(trusted(startLabel)),held=HoldFixture(target);target.settleSeconds=0.04
        target.onPress={id in target.nodes[id]=button(stopLabel)}
        _ = try held.down(firstOwner)
        let before=target.presses.count,releaseStarts=target.settles
        target.onPress={_ in}
        target.onSettle={count in if count-releaseStarts>=delay{target.nodes[2]=button(endLabel)}}
        let released=try held.up(firstOwner)
        check(CodexDictationOwnership.releaseConfirmed(released),"owned stop observes asynchronous idle/finishing beyond the old 80ms window")
        check(released["confirmation"] as? String=="observed" && target.settles-releaseStarts>=delay,"stop acknowledgement needs an actual ended-state witness")
        check(target.presses.count==before+1 && held.ownership.activeOwner==nil,"delayed readback never replays stop or retains old ownership")
    }
}
let detachedStopTarget=Fixture(trusted("Dictate")),detachedStop=HoldFixture(detachedStopTarget)
detachedStopTarget.settleSeconds=0.04;detachedStopTarget.onPress={id in detachedStopTarget.nodes[id]=button("Stop dictation")}
_ = try detachedStop.down(firstOwner)
let detachedStopStarts=detachedStopTarget.settles
detachedStopTarget.onPress={_ in detachedStopTarget.nodes[1]?.children=[]}
detachedStopTarget.onSettle={count in if count-detachedStopStarts==8{detachedStopTarget.nodes[1]?.children=[2];detachedStopTarget.nodes[2]=button("Dictate")}}
let detachedStopResult=try detachedStop.up(firstOwner)
check(CodexDictationOwnership.releaseConfirmed(detachedStopResult) && detachedStopTarget.presses.count==2,"temporary missing stop button is re-observed without pressing its replacement")

for label in ["Stop dictation","Starting dictation; click to cancel","Unrecognized dictation state"] {
    let target=Fixture(trusted("Dictate")),held=HoldFixture(target);target.settleSeconds=0.04
    target.onPress={id in target.nodes[id]=button("Stop dictation")};_ = try held.down(firstOwner)
    let began=target.time,releaseStarts=target.settles
    target.onPress={id in target.nodes[id]=button(label)}
    let result=try held.up(firstOwner)
    check(!CodexDictationOwnership.releaseConfirmed(result),"recording, starting or unknown after the deadline still requires manual stop warning")
    check(target.presses.count==2 && held.ownership.activeOwner==nil,"unconfirmed stop is not retried and old ownership cannot restart it")
    check(target.settles-releaseStarts>2 && target.settles-releaseStarts<=CodexControlRunner.maximumReleaseObservations,
        "stop observation is bounded independently of its result")
    check(target.time-began<=CodexControlSelection.maximumSeconds+target.settleSeconds+0.0001,"asynchronous readback does not extend the existing total deadline")
}
let stalledStopTarget=Fixture(trusted("Dictate")),stalledStop=HoldFixture(stalledStopTarget)
stalledStopTarget.settleSeconds=0;stalledStopTarget.onPress={id in stalledStopTarget.nodes[id]=button("Stop dictation")}
_ = try stalledStop.down(firstOwner);let stalledBegins=stalledStopTarget.settles
stalledStopTarget.onPress={_ in}
check(!CodexDictationOwnership.releaseConfirmed(try stalledStop.up(firstOwner)) &&
    stalledStopTarget.settles-stalledBegins==CodexControlRunner.maximumReleaseObservations && stalledStopTarget.presses.count==2,
    "an injected nonadvancing clock cannot create an unbounded stop wait or another press")
for changeDocument in [false,true] {
    let target=Fixture(trusted("Dictate")),held=HoldFixture(target);target.settleSeconds=0.04
    target.onPress={id in target.nodes[id]=button("Stop dictation")};_ = try held.down(firstOwner)
    let releaseStarts=target.settles;target.onPress={_ in}
    target.onSettle={count in if count-releaseStarts==3 {
        target.nodes[2]=button("Dictate")
        if changeDocument{target.nodes[1]?.url=URL(string:"https://untrusted.invalid/")}
        else{target.current=CodexControlContext(bundleID:"com.openai.codex",pid:42,window:1)}
    }}
    let result=try held.up(firstOwner)
    check(!CodexDictationOwnership.releaseConfirmed(result) && result["observedState"] as? String=="unknown" && target.presses.count==2,
        "late idle in a changed window or document is not confirmation for the owned recording")
    check(target.settles-releaseStarts==3,"target identity loss ends observation without following another scope")
}
let ambiguousStopTarget=Fixture(trusted("Dictate")),ambiguousStop=HoldFixture(ambiguousStopTarget)
ambiguousStopTarget.onPress={id in ambiguousStopTarget.nodes[id]=button("Stop dictation")};_ = try ambiguousStop.down(firstOwner)
let ambiguousStopStarts=ambiguousStopTarget.settles
ambiguousStopTarget.onPress={_ in ambiguousStopTarget.nodes[1]?.children=[2,3];ambiguousStopTarget.nodes[3]=button("Dictate")}
check(!CodexDictationOwnership.releaseConfirmed(try ambiguousStop.up(firstOwner)) && ambiguousStopTarget.presses.count==2 &&
    ambiguousStopTarget.settles-ambiguousStopStarts==1,"ambiguous stop controls fail closed immediately rather than waiting for a guessed target")
let privateJSON=String(data:try! JSONSerialization.data(withJSONObject:upResult),encoding:.utf8)!
check(!privateJSON.contains(firstOwner) && !privateJSON.contains(secondOwner),"private owners never leave the control result")
check(CodexControlAction(rawValue:"approve") == .approve && CodexControlAction(rawValue:"sendPrompt") == .sendPrompt,"momentary controls use exact scoped buttons")

// Complete-mode readiness is requested once per process launch. These fake
// setters never open an application, wait two seconds, or queue a gesture.
let warming=Fixture(trusted("Enable fast mode")),activation=CodexAccessibilityActivation()
warming.nodes[2]?.actions=[]
expect("CONTROL_INITIALIZING"){_ = try warming.run(.toggleFastMode,scoped:true,activation:activation)}
check(warming.activations==1 && warming.presses.isEmpty && warming.opens==0 && warming.settles==0,"cold metadata requests AT once without opening a menu, sleeping or pressing")
check(warming.lastDiagnostic!.actionReadiness=="warming" && warming.lastDiagnostic!.warmupRemainingMs==2000,"initializing reports the bounded remaining delay")
warming.time=0.5
expect("CONTROL_INITIALIZING"){_ = try warming.run(.toggleFastMode,scoped:true,activation:activation)}
check(warming.activations==1 && warming.lastDiagnostic!.warmupRemainingMs==1500,"a fresh gesture during warmup does not reset Chromium's debounce")
warming.time=2.1
expect("CONTROL_NOT_OPERABLE"){_ = try warming.run(.toggleFastMode,scoped:true,activation:activation)}
check(warming.activations==1 && warming.lastDiagnostic!.actionReadiness=="unavailable" && warming.lastDiagnostic!.warmupRemainingMs==0,"failed readiness after the delay does not start a blind retry loop")
warming.nodes[2]?.actions=["AXPress"]
warming.onPress={id in warming.nodes[id]=button("Enable standard mode")}
verify(try warming.run(.toggleFastMode,scoped:true,activation:activation),true,"fast","observed")
check(warming.activations==1 && warming.presses==[2] && warming.lastDiagnostic!.actionReadiness=="ready","only a new physical request with actual AXPress metadata executes")
warming.nodes[2]?.actions=[]
warming.activationIdentity=CodexAccessibilityActivationIdentity(pid:42,launch:Date(timeIntervalSince1970:200))
expect("CONTROL_INITIALIZING"){_ = try warming.run(.toggleFastMode,scoped:true,activation:activation)}
check(warming.activations==2,"a new launch identity cannot inherit the previous AT request")
warming.activationIdentity=CodexAccessibilityActivationIdentity(pid:43,launch:Date(timeIntervalSince1970:200))
expect("CONTROL_INITIALIZING"){_ = try warming.run(.toggleFastMode,scoped:true,activation:activation)}
check(warming.activations==3,"a different PID cannot inherit the previous AT request")
warming.activationIdentity=CodexAccessibilityActivationIdentity(pid:42,launch:Date(timeIntervalSince1970:100))
expect("CONTROL_NOT_OPERABLE"){_ = try warming.run(.toggleFastMode,scoped:true,activation:activation)}
check(warming.activations==3,"returning to an already attempted live process does not repeat its AT request")
let capped=CodexAccessibilityActivation(),cappedDiagnostic=CodexControlDiagnostics(now:{0})
var cappedCalls=0
for pid:Int32 in 1...8 {
    expect("CONTROL_INITIALIZING"){try capped.require(identity:CodexAccessibilityActivationIdentity(pid:pid,launch:Date(timeIntervalSince1970:100)),now:0,diagnostics:cappedDiagnostic,activate:{cappedCalls+=1;return "accepted"})}
}
expect("CONTROL_NOT_OPERABLE"){try capped.require(identity:CodexAccessibilityActivationIdentity(pid:9,launch:Date(timeIntervalSince1970:100)),now:0,diagnostics:cappedDiagnostic,activate:{cappedCalls+=1;return "accepted"})}
check(cappedCalls==8,"a bounded cache fails closed rather than evicting a still-live launch and re-requesting it")
capped.retainOnly([])
expect("CONTROL_INITIALIZING"){try capped.require(identity:CodexAccessibilityActivationIdentity(pid:9,launch:Date(timeIntervalSince1970:100)),now:0,diagnostics:cappedDiagnostic,activate:{cappedCalls+=1;return "accepted"})}
check(cappedCalls==9,"explicitly pruning terminated process identities permits a fresh launch without unbounded storage")
for response in ["unsupported","denied","failed","arbitrary-private-error"] {
    let value=Fixture(trusted("Enable fast mode")),state=CodexAccessibilityActivation()
    value.nodes[2]?.actions=[];value.activationResponse=response
    let code=response == "unsupported" ? "CONTROL_INITIALIZING":"CONTROL_NOT_OPERABLE"
    expect(code){_ = try value.run(.toggleFastMode,scoped:true,activation:state)}
    value.time=1
    expect(code){_ = try value.run(.toggleFastMode,scoped:true,activation:state)}
    check(value.activations==1 && value.presses.isEmpty,"unsupported and failed setters are cached without repeating the request")
    check(value.lastDiagnostic!.activationResponse == (response == "arbitrary-private-error" ? "failed":response),"only fixed activation status leaves the adapter")
}
let readyNoOptIn=Fixture(trusted("Enable fast mode"));readyNoOptIn.onPress={id in readyNoOptIn.nodes[id]=button("Enable standard mode")}
verify(try readyNoOptIn.run(.toggleFastMode,scoped:true,activation:CodexAccessibilityActivation()),true,"fast","observed")
check(readyNoOptIn.activations==0,"existing exact AXPress capability skips AT activation")
let noTrusted=Fixture(basic("Enable fast mode"))
expect("CONTROL_NOT_FOUND"){_ = try noTrusted.run(.toggleFastMode,scoped:true,activation:CodexAccessibilityActivation())}
check(noTrusted.activations==0 && noTrusted.opens==0 && noTrusted.presses.isEmpty,"an untrusted document never requests complete AT mode")
let pickerCold=Fixture(trusted("Select model"));pickerCold.nodes[2]?.actions=[]
expect("CONTROL_INITIALIZING"){_ = try pickerCold.run(.toggleFastMode,opener:true,scoped:true,activation:CodexAccessibilityActivation())}
check(pickerCold.activations==1 && pickerCold.opens==0 && pickerCold.presses.isEmpty,"a metadata-free picker cannot trigger the opener fallback")
for label in ["Select effort","选择推理强度"] {
    let value=Fixture(trusted(label))
    value.onPress={id in
        if id==2 {value.nodes[1]?.children.append(3);value.nodes[3]=button("Enable fast mode")}
        else {value.nodes[id]=button("Enable standard mode")}
    }
    verify(try value.run(.toggleFastMode,opener:true,scoped:true,activation:CodexAccessibilityActivation()),true,"fast","observed")
    check(value.opens==0 && value.activations==0 && value.presses==[2,3],"the exact installed effort-picker label opens its menu before the strict speed press")
}
check(CodexControlSelection.modelPicker(button("Select reasoning effort"),id:0)==nil,"an unverified effort-picker wording is not a fuzzy target")
let witnessed=Fixture(trusted("Dictate"));witnessed.nodes[1]?.children.append(3);witnessed.nodes[3]=button("Stop dictation")
witnessed.onOpen={witnessed.nodes[1]?.children.append(4);witnessed.nodes[4]=button("Enable fast mode")}
witnessed.onPress={id in witnessed.nodes[id]=button("Enable standard mode")}
verify(try witnessed.run(.toggleFastMode,opener:true,scoped:true,activation:CodexAccessibilityActivation()),true,"fast","observed")
check(witnessed.opens==1 && witnessed.presses==[4] && witnessed.activations==0,"two exact microphone metadata witnesses permit one safe opener and one speed press without touching either microphone")
for variant in ["disabled","no-action","foreign","starting"] {
    let value=Fixture(trusted("Dictate"))
    switch variant {
    case "disabled":value.nodes[2]?.enabled=false
    case "no-action":value.nodes[2]?.actions=[]
    case "starting":value.nodes[2]=button("Starting dictation; click to cancel")
    default:
        value.nodes[1]?.children=[3]
        value.nodes[3]=CodexControlNode(role:"AXWebArea",children:[2],url:URL(string:"https://private-fixture.invalid/"))
    }
    expect("CONTROL_INITIALIZING"){_ = try value.run(.toggleFastMode,opener:true,scoped:true,activation:CodexAccessibilityActivation())}
    check(value.activations==1 && value.opens==0 && value.presses.isEmpty,"disabled, actionless, foreign or transitional microphones do not prove readiness or open a cold menu")
    if variant == "foreign" {check(!value.reads.contains(2),"foreign witness descendants are never read")}
}
let fallbackWarm=Fixture(trusted("听写")),fallbackState=CodexAccessibilityActivation();fallbackWarm.nodes[2]?.actions=[]
fallbackWarm.onOpen={fallbackWarm.nodes[1]?.children.append(3);fallbackWarm.nodes[3]=button("Enable fast mode")}
fallbackWarm.onPress={id in fallbackWarm.nodes[id]=button("Enable standard mode")}
expect("CONTROL_INITIALIZING"){_ = try fallbackWarm.run(.toggleFastMode,opener:true,scoped:true,activation:fallbackState)}
fallbackWarm.time=3
expect("CONTROL_NOT_OPERABLE"){_ = try fallbackWarm.run(.toggleFastMode,opener:true,scoped:true,activation:fallbackState)}
check(fallbackWarm.opens==0 && fallbackWarm.presses.isEmpty && fallbackWarm.activations==1,"elapsed warmup time without metadata cannot permit the keyboard opener")
fallbackWarm.nodes[2]?.actions=["AXPress"]
verify(try fallbackWarm.run(.toggleFastMode,opener:true,scoped:true,activation:fallbackState),true,"fast","observed")
check(fallbackWarm.opens==1 && fallbackWarm.presses==[3] && fallbackWarm.activations==1,"fresh ready metadata after warmup restores the safe fallback without another activation request")
let changedDocWarm=Fixture(trusted("Enable fast mode"));changedDocWarm.nodes[2]?.actions=[]
changedDocWarm.onRead={id in if id==2 {changedDocWarm.nodes[1]?.url=URL(string:"https://private-fixture.invalid/")}}
expect("CONTROL_TARGET_CHANGED"){_ = try changedDocWarm.run(.toggleFastMode,scoped:true,activation:CodexAccessibilityActivation())}
check(changedDocWarm.activations==0 && changedDocWarm.presses.isEmpty,"a document changed during selection never receives AT initialization")
let changedDocPress=Fixture(trusted("Enable fast mode"));var selectedReads=0
changedDocPress.onRead={id in if id==2 {selectedReads+=1;if selectedReads==2 {changedDocPress.nodes[1]?.url=URL(string:"https://private-fixture.invalid/")}}}
expect("CONTROL_TARGET_CHANGED"){_ = try changedDocPress.run(.toggleFastMode,scoped:true,activation:CodexAccessibilityActivation())}
check(changedDocPress.activations==0 && changedDocPress.presses.isEmpty,"a document changed during the final control refresh never receives a press")
let upCold=Fixture(trusted("Stop dictation"));upCold.nodes[2]?.actions=[]
let upColdResult=try upCold.run(.dictation,phase:"up",scoped:true,activation:CodexAccessibilityActivation())
check(upColdResult["performed"] as? Bool==false && upCold.activations==0 && upCold.settles==0,"owned up never initializes, waits for or defers a PTT start")

func twoComposers()->[Int:CodexControlNode] {
    [0:CodexControlNode(role:"AXWindow",children:[1]),
     1:CodexControlNode(role:"AXWebArea",children:[2,5],url:URL(string:"app://-/index.html")),
     2:CodexControlNode(role:"AXGroup",children:[3,4]),3:CodexControlNode(role:"AXTextArea"),4:button("Dictate"),
     5:CodexControlNode(role:"AXGroup",children:[6,7]),6:CodexControlNode(role:"AXTextArea"),7:button("Dictate")]
}
let focusedSecond=Fixture(twoComposers());focusedSecond.focused=6
focusedSecond.onPress={id in focusedSecond.nodes[id]=button(focusedSecond.nodes[id]?.title == "Dictate" ? "Stop dictation":"Dictate")}
verify(try focusedSecond.run(.dictation,phase:"down",composer:true),true,"recording","observed")
check(focusedSecond.selectedScope==5 && focusedSecond.selectedDocument==1 && focusedSecond.presses==[7],"the second focused editor selects its nearest enclosing composer rather than the first microphone")
focusedSecond.ownedScope=focusedSecond.selectedScope;focusedSecond.focused=3
verify(try focusedSecond.run(.dictation,phase:"up",composer:true),true,"idle","observed")
check(focusedSecond.presses==[7,7],"owned up remains in the original composer after focus moves to another editor")
let focusedFirst=Fixture(twoComposers());focusedFirst.focused=3
focusedFirst.onPress={id in focusedFirst.nodes[id]=button("Stop dictation")}
verify(try focusedFirst.run(.dictation,phase:"down",composer:true),true,"recording","observed")
check(focusedFirst.selectedScope==2 && focusedFirst.presses==[4],"the first focused editor independently selects its own microphone")
check(focusedFirst.documentFocusReads==0 && focusedFirst.lastDiagnostic?.focusSource=="application" && focusedFirst.lastDiagnostic?.focusStage=="ready","a real application-level editable remains the primary route without asking for another focus")
for role in ["AXGroup","AXScrollArea","AXSplitGroup"] {
    let value=Fixture(twoComposers());value.nodes[0]?.children=[10];value.nodes[10]=CodexControlNode(role:role,children:[1])
    value.focused=10;value.documentFocused=6
    value.onPress={id in value.nodes[id]=button("Stop dictation")}
    verify(try value.run(.dictation,phase:"down",composer:true),true,"recording","observed")
    check(value.presses==[7] && value.documentFocusReads==2,"a proven native ancestor container uses the trusted document focus and rechecks it before press")
    check(value.lastDiagnostic?.focusSource=="document" && value.lastDiagnostic?.focusRole=="text-area" && value.lastDiagnostic?.focusStage=="ready","document fallback exposes only fixed focus categories")
    check(value.lastDiagnostic?.focusHasDocument==true && value.lastDiagnostic?.focusHasWindow==true && value.lastDiagnostic?.focusDepth==5,"the actual focused editable is proven inside the same document and window")
}
for focus in [1] {
    let value=Fixture(twoComposers());value.focused=focus;value.documentFocused=3
    value.onPress={id in value.nodes[id]=button("Stop dictation")}
    verify(try value.run(.dictation,phase:"down",composer:true),true,"recording","observed")
    check(value.presses==[4] && value.documentFocusReads==2,"the exact trusted WebArea may defer to its public renderer focus")
}
for role in ["AXWindow","AXGroup","AXScrollArea"] {
    let value=Fixture(twoComposers());value.nodes[0]=CodexControlNode(role:role,children:[1]);value.focused=0;value.documentFocused=3
    expect("CONTROL_FOCUS_REQUIRED"){_ = try value.run(.dictation,phase:"down",composer:true)}
    check(value.presses.isEmpty && value.documentFocusReads==0,"window-level focus never borrows a stale renderer editable even if the window's reported role resembles a container")
}
for focus:Int? in [nil,4,5] {
    let value=Fixture(twoComposers());value.focused=focus;value.documentFocused=3
    expect("CONTROL_FOCUS_REQUIRED"){_ = try value.run(.dictation,phase:"down",composer:true)}
    check(value.documentFocusReads==0 && value.presses.isEmpty,"missing focus, a button, and an in-document generic group never borrow document focus")
}
for role in ["AXTextField","AXSearchField","AXSecureTextField","AXButton"] {
    let value=Fixture(twoComposers());value.nodes[0]?.children.append(8);value.nodes[8]=CodexControlNode(role:role)
    value.focused=8;value.documentFocused=3
    expect("CONTROL_FOCUS_REQUIRED"){_ = try value.run(.dictation,phase:"down",composer:true)}
    check(value.documentFocusReads==0 && value.presses.isEmpty,"a native search, secure field, unrelated editable or button cannot redirect to the last web editor")
    check(value.lastDiagnostic?.focusSource=="application" && value.lastDiagnostic?.focusStage=="outside-document","outside focus is diagnosed without a document query")
}
let missingDocumentFocus=Fixture(twoComposers());missingDocumentFocus.focused=1
expect("CONTROL_FOCUS_REQUIRED"){_ = try missingDocumentFocus.run(.dictation,phase:"down",composer:true)}
check(missingDocumentFocus.documentFocusReads==1 && missingDocumentFocus.presses.isEmpty && missingDocumentFocus.lastDiagnostic?.focusStage=="missing" && missingDocumentFocus.lastDiagnostic?.focusRole=="none","an unavailable document focus stays explicit and cannot pick the first microphone")
for variant in ["outside-document","foreign-document","noneditable"] {
    let value=Fixture(twoComposers());value.focused=1
    if variant == "noneditable" {value.documentFocused=4}
    else if variant == "outside-document" {value.nodes[0]?.children.append(8);value.nodes[8]=CodexControlNode(role:"AXTextArea");value.documentFocused=8}
    else {value.nodes[0]?.children.append(8);value.nodes[8]=CodexControlNode(role:"AXWebArea",children:[9],url:URL(string:"https://private-fixture.invalid/"));value.nodes[9]=CodexControlNode(role:"AXTextArea");value.documentFocused=9}
    expect("CONTROL_FOCUS_REQUIRED"){_ = try value.run(.dictation,phase:"down",composer:true)}
    check(value.presses.isEmpty && value.documentFocusReads==1,"document focus must still be a real editable in the exact original trusted document")
    check(value.lastDiagnostic?.focusStage==(variant == "noneditable" ? "editable-missing":"outside-document"),"document focus failures identify the rejected structural stage")
}
let fallbackFocusRace=Fixture(twoComposers());fallbackFocusRace.focused=1;fallbackFocusRace.documentFocused=3
fallbackFocusRace.onRead={id in if id==4 && fallbackFocusRace.selectedScope != nil {fallbackFocusRace.documentFocused=6}}
expect("CONTROL_FOCUS_REQUIRED"){_ = try fallbackFocusRace.run(.dictation,phase:"down",composer:true)}
check(fallbackFocusRace.presses.isEmpty && fallbackFocusRace.documentFocusReads==2,"a renderer focus move after selection cannot switch the intended editor at press time")
let ownedWithoutFocus=Fixture(twoComposers());ownedWithoutFocus.ownedScope=2;ownedWithoutFocus.nodes[4]=button("Stop dictation")
ownedWithoutFocus.documentFocused=6;ownedWithoutFocus.onPress={id in ownedWithoutFocus.nodes[id]=button("Dictate")}
verify(try ownedWithoutFocus.run(.dictation,phase:"up",composer:true),true,"idle","observed")
check(ownedWithoutFocus.documentFocusReads==0 && ownedWithoutFocus.presses==[4] && ownedWithoutFocus.lastDiagnostic?.focusSource=="owned","an owned release never asks for or follows new document focus")
for role in ["AXTextField","AXTextArea","AXSearchField","AXSecureTextField"] {
    let value=Fixture(twoComposers());value.nodes[1]?.children.append(8);value.nodes[8]=CodexControlNode(role:role);value.focused=8
    expect("CONTROL_FOCUS_REQUIRED"){_ = try value.run(.dictation,phase:"down",composer:true)}
    check(value.presses.isEmpty,"an unrelated editable or search within the trusted document cannot borrow another composer's microphone")
}
for role in ["AXTextField","AXTextArea","AXSearchField","AXSecureTextField"] {
    let value=Fixture(twoComposers());value.focused=3;value.nodes[2]?.children.append(8);value.nodes[8]=CodexControlNode(role:role)
    expect("CONTROL_FOCUS_REQUIRED"){_ = try value.run(.dictation,phase:"down",composer:true)}
    check(value.presses.isEmpty,"a scope mixed with another editable, search or secure field fails instead of expanding to its document")
}
let nestedEditable=Fixture(twoComposers());nestedEditable.focused=3;nestedEditable.nodes[3]?.children=[8];nestedEditable.nodes[8]=CodexControlNode(role:"AXTextField")
expect("CONTROL_FOCUS_REQUIRED"){_ = try nestedEditable.run(.dictation,phase:"down",composer:true)}
check(nestedEditable.presses.isEmpty,"an editable nested beneath the focused editor is conservatively rejected by role-only structure inspection")
let staticLeaf=Fixture(twoComposers());staticLeaf.focused=3;staticLeaf.nodes[3]?.children=[8]
staticLeaf.nodes[8]=CodexControlNode(role:"AXStaticText",title:"private-input-content",children:[9]);staticLeaf.nodes[9]=CodexControlNode(role:"AXTextField")
staticLeaf.onPress={id in staticLeaf.nodes[id]=button("Stop dictation")}
verify(try staticLeaf.run(.dictation,phase:"down",composer:true),true,"recording","observed")
check(staticLeaf.presses==[4] && !staticLeaf.reads.contains(8) && !staticLeaf.reads.contains(9),"static text is a structural leaf and neither its content nor descendants are read")
let scopeRace=Fixture(twoComposers());scopeRace.focused=3
scopeRace.onRead={id in if id==4 && scopeRace.selectedScope != nil && scopeRace.nodes[8] == nil {scopeRace.nodes[2]?.children.append(8);scopeRace.nodes[8]=CodexControlNode(role:"AXTextField")}}
expect("CONTROL_FOCUS_REQUIRED"){_ = try scopeRace.run(.dictation,phase:"down",composer:true)}
check(scopeRace.presses.isEmpty,"another editable added after scope selection is rejected again immediately before the start press")
let readonlyUp=Fixture(twoComposers());readonlyUp.focused=3
readonlyUp.onPress={id in readonlyUp.nodes[id]=button(readonlyUp.nodes[id]?.title == "Dictate" ? "Stop dictation":"Dictate")}
verify(try readonlyUp.run(.dictation,phase:"down",composer:true),true,"recording","observed")
readonlyUp.ownedScope=readonlyUp.selectedScope;readonlyUp.nodes[3]=CodexControlNode(role:"AXGroup");readonlyUp.focused=6
verify(try readonlyUp.run(.dictation,phase:"up",composer:true),true,"idle","observed")
check(readonlyUp.presses==[4,4],"owned release remains valid when recording changes the original editor's role and focus moves elsewhere")
for focus:Int? in [nil,4,0] {
    let value=Fixture(twoComposers());value.focused=focus
    expect("CONTROL_FOCUS_REQUIRED"){_ = try value.run(.dictation,phase:"down",activation:CodexAccessibilityActivation(),composer:true)}
    check(value.presses.isEmpty && value.activations==0,"missing or noneditable focus fails before AT activation or any microphone press")
}
let externalFocus=Fixture(twoComposers());externalFocus.nodes[0]?.children.append(8)
externalFocus.nodes[8]=CodexControlNode(role:"AXWebArea",children:[9],url:URL(string:"https://private-fixture.invalid/"));externalFocus.nodes[9]=CodexControlNode(role:"AXTextArea");externalFocus.focused=9
expect("CONTROL_FOCUS_REQUIRED"){_ = try externalFocus.run(.dictation,phase:"down",composer:true)}
check(externalFocus.presses.isEmpty,"an external web area's focused editor cannot select a trusted composer's microphone")
let chromeFocus=Fixture(twoComposers());chromeFocus.nodes[0]?.children.append(9);chromeFocus.nodes[9]=CodexControlNode(role:"AXTextField");chromeFocus.focused=9
expect("CONTROL_FOCUS_REQUIRED"){_ = try chromeFocus.run(.dictation,phase:"down",composer:true)}
check(chromeFocus.presses.isEmpty,"a native chrome text field outside the trusted document cannot supply composer focus")
let noMic=Fixture(twoComposers());noMic.focused=3;noMic.nodes.removeValue(forKey:4);noMic.nodes[2]?.children=[3];noMic.nodes[1]?.children=[2]
expect("CONTROL_FOCUS_REQUIRED"){_ = try noMic.run(.dictation,phase:"down",composer:true)}
check(noMic.presses.isEmpty,"a focused input without an exact microphone cannot choose an unrelated fallback")
let duplicateWithin=Fixture(twoComposers());duplicateWithin.focused=3;duplicateWithin.nodes[2]?.children.append(8);duplicateWithin.nodes[8]=button("听写")
expect("CONTROL_AMBIGUOUS"){_ = try duplicateWithin.run(.dictation,phase:"down",composer:true)}
check(duplicateWithin.presses.isEmpty,"multiple exact microphones in the nearest composer remain ambiguous")
let movedOwned=Fixture(twoComposers());movedOwned.ownedScope=5;movedOwned.focused=3;movedOwned.nodes[1]?.children=[2];movedOwned.nodes[0]?.children.append(5)
expect("CONTROL_FOCUS_REQUIRED"){_ = try movedOwned.run(.dictation,phase:"up",composer:true)}
check(movedOwned.presses.isEmpty,"a detached original scope never retargets the other composer's microphone")
let coldPTT=Fixture(twoComposers()),coldState=CodexAccessibilityActivation(),coldOwner=CodexDictationOwnership()
coldPTT.focused=6;coldPTT.nodes[7]?.actions=[]
expect("CONTROL_INITIALIZING"){let result=try coldPTT.run(.dictation,phase:"down",activation:coldState,composer:true);_ = coldOwner.claim(owner:firstOwner,context:baseline,performed:result["performed"] as? Bool == true)}
check(coldOwner.take(owner:firstOwner)==nil && coldPTT.presses.isEmpty,"initialization grants no PTT ownership for its subsequent release")
coldPTT.time=3;coldPTT.nodes[7]?.actions=["AXPress"]
check(coldPTT.presses.isEmpty && coldPTT.settles==0 && coldOwner.activeOwner==nil,"readiness after release cannot replay the old hold or start a recording")

let liveExpected=try CodexPhysicalHoldProof.request(["gestureId":"fixture:hold","sourceKeyCode":103,"bindingEpoch":9])
let liveSecret=Data(base64Encoded:"${holdKey.toString('base64')}")!
let liveBytes=Data(base64Encoded:"${holdData(validHold)}")!
check(CodexPhysicalHoldProof.verify(liveBytes,expected:liveExpected,secret:liveSecret,nowMs:1000),"independently signed Node HMAC is accepted by the production Swift verifier")
for time in [999.0,3001.0,Double.infinity,Double.nan] {
    check(!CodexPhysicalHoldProof.verify(liveBytes,expected:liveExpected,secret:liveSecret,nowMs:time),"future, expired and invalid clocks cannot authorize a hold")
}
check(CodexPhysicalHoldProof.verify(liveBytes,expected:liveExpected,secret:liveSecret,nowMs:3000),"the exact two-second freshness boundary is included")
for encoded in [
    "${holdData(signedHold({held:false}))}",
    "${holdData(signedHold({gestureId:'fixture:new-gesture'}))}",
    "${holdData(signedHold({sourceKeyCode:101}))}",
    "${holdData(signedHold({bindingEpoch:10}))}",
    "${holdData({...validHold,signature:'0'.repeat(64)})}",
    "${holdData({...validHold,held:1})}",
    "${holdData({...validHold,sourceKeyCode:true})}",
    "${holdData({...validHold,bindingEpoch:true})}",
    "${holdData({...validHold,recordedAtMs:'1000'})}",
    "${holdData({...validHold,extra:'private-target-content'})}"
] {
    let bytes=Data(base64Encoded:encoded)!
    check(!CodexPhysicalHoldProof.verify(bytes,expected:liveExpected,secret:liveSecret,nowMs:1000),"release, replacement gestures, epoch/key mismatch, tampering, type coercion and extra fields fail closed")
}
check(!CodexPhysicalHoldProof.verify(Data(repeating:0,count:2049),expected:liveExpected,secret:liveSecret,nowMs:1000),"oversize proof bytes are rejected")
check(!CodexPhysicalHoldProof.verify(liveBytes,expected:liveExpected,secret:Data(repeating:0,count:32),nowMs:1000),"another host key cannot authorize a gesture")
for request:[String:Any] in [[:],["gestureId":"bad/id","sourceKeyCode":103,"bindingEpoch":9],["gestureId":"fixture:hold","sourceKeyCode":true,"bindingEpoch":9],["gestureId":"fixture:hold","sourceKeyCode":58,"bindingEpoch":9],["gestureId":"fixture:hold","sourceKeyCode":128,"bindingEpoch":9],["gestureId":"fixture:hold","sourceKeyCode":103,"bindingEpoch":-1]] {
    expect("CONTROL_PRESS_RELEASED"){_ = try CodexPhysicalHoldProof.request(request)}
}
try CodexPhysicalHoldProof.require(expected:liveExpected,secret:liveSecret,read:{liveBytes},nowMs:{1000})
expect("CONTROL_PRESS_RELEASED"){try CodexPhysicalHoldProof.require(expected:liveExpected,secret:liveSecret,read:{throw failure("FAKE_READ","fixture")},nowMs:{1000})}
let privateProofRoot=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
let verifiedFile=try CodexPhysicalHoldProof.privateFile(privateProofRoot.appendingPathComponent("private/valid.json").path)
check(verifiedFile==liveBytes,"the production file reader accepts only the isolated private fake ledger")
for name in ["private/public.json","private/link.json","private/large.json","open-parent/valid.json","parent-link/valid.json"] {
    expect("CONTROL_PRESS_RELEASED"){_ = try CodexPhysicalHoldProof.privateFile(privateProofRoot.appendingPathComponent(name).path)}
}
// Exercise the production clock closure, not an injected arbitrary1000 clock.
// This file and secret belong only to this isolated fixture, never the host.
let clockProofFile=privateProofRoot.appendingPathComponent("private/clock.json")
let clockRequest:[String:Any]=["gestureId":"fixture:hold","sourceKeyCode":103,"bindingEpoch":9]
func signedClockProof(_ recorded:Int) throws -> Data {
    let canonical=try JSONSerialization.data(withJSONObject:["nuphylab-native-hold-v1","fixture:hold",103,9,true,recorded])
    let signature=HMAC<SHA256>.authenticationCode(for:canonical,using:SymmetricKey(data:liveSecret)).map{String(format:"%02x",$0)}.joined()
    return try JSONSerialization.data(withJSONObject:["gestureId":"fixture:hold","sourceKeyCode":103,
        "bindingEpoch":9,"held":true,"recordedAtMs":recorded,"signature":signature])
}
func writeClockProof(_ data:Data) throws {
    try data.write(to:clockProofFile)
    try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:clockProofFile.path)
}
let currentMonotonic=Int(ProcessInfo.processInfo.systemUptime*1000)
try writeClockProof(signedClockProof(currentMonotonic))
let productionClockCheck=try CodexPhysicalHoldProof.checker(clockRequest,environment:[
    "AIR_STUDIO_NATIVE_HOLD_SECRET":liveSecret.base64EncodedString(),"AIR_STUDIO_NATIVE_HOLD_PATH":clockProofFile.path])
try productionClockCheck()
check(true,"a freshly signed real monotonic record passes the production checker clock")
for environment:[String:String] in [
    ["AIR_STUDIO_NATIVE_KEY_SECRET":liveSecret.base64EncodedString(),"AIR_STUDIO_NATIVE_HOLD_PATH":clockProofFile.path],
    ["AIR_STUDIO_NATIVE_HOLD_PATH":clockProofFile.path],
    ["AIR_STUDIO_NATIVE_HOLD_SECRET":"","AIR_STUDIO_NATIVE_HOLD_PATH":clockProofFile.path],
    ["AIR_STUDIO_NATIVE_HOLD_SECRET":Data(repeating:42,count:31).base64EncodedString(),"AIR_STUDIO_NATIVE_HOLD_PATH":clockProofFile.path],
    ["AIR_STUDIO_NATIVE_HOLD_SECRET":liveSecret.base64EncodedString()+"\\n","AIR_STUDIO_NATIVE_HOLD_PATH":clockProofFile.path]
] {
    expect("CONTROL_PRESS_RELEASED"){_ = try CodexPhysicalHoldProof.checker(clockRequest,environment:environment)}
}
let separateHoldCheck=try CodexPhysicalHoldProof.checker(clockRequest,environment:[
    "AIR_STUDIO_NATIVE_HOLD_SECRET":liveSecret.base64EncodedString(),
    "AIR_STUDIO_NATIVE_KEY_SECRET":Data(repeating:99,count:32).base64EncodedString(),
    "AIR_STUDIO_NATIVE_HOLD_PATH":clockProofFile.path])
try separateHoldCheck()
check(true,"the dedicated hold key works independently of an unrelated main key and never falls back to it")
let wallStamp=Int(Date().timeIntervalSince1970*1000),wallProof=try signedClockProof(wallStamp)
check(CodexPhysicalHoldProof.verify(wallProof,expected:liveExpected,secret:liveSecret,nowMs:Double(wallStamp)),"the wall-time negative fixture has an otherwise valid signature")
try writeClockProof(wallProof)
expect("CONTROL_PRESS_RELEASED"){try productionClockCheck()}
try writeClockProof(signedClockProof(max(0,currentMonotonic-2001)))
expect("CONTROL_PRESS_RELEASED"){try productionClockCheck()}
let readonlyProofDirectory=privateProofRoot.appendingPathComponent("owner-readonly",isDirectory:true)
try FileManager.default.createDirectory(at:readonlyProofDirectory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
let readonlyProofFile=readonlyProofDirectory.appendingPathComponent("current.json")
let freshSignedHold=try signedClockProof(Int(ProcessInfo.processInfo.systemUptime*1000))
try freshSignedHold.write(to:readonlyProofFile)
try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:readonlyProofFile.path)
let readonlyClockCheck=try CodexPhysicalHoldProof.checker(clockRequest,environment:[
    "AIR_STUDIO_NATIVE_HOLD_SECRET":liveSecret.base64EncodedString(),"AIR_STUDIO_NATIVE_HOLD_PATH":readonlyProofFile.path])
try readonlyClockCheck()
check(true,"a fresh isolated0700directory0600file proof passes before permission changes")
try FileManager.default.setAttributes([.posixPermissions:0o500],ofItemAtPath:readonlyProofDirectory.path)
check(try Data(contentsOf:readonlyProofFile)==freshSignedHold,"a readonly owner directory can retain the old signed held record")
expect("CONTROL_PRESS_RELEASED"){try readonlyClockCheck()}
try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:readonlyProofDirectory.path)
try FileManager.default.setAttributes([.posixPermissions:0o400],ofItemAtPath:readonlyProofFile.path)
check(try Data(contentsOf:readonlyProofFile)==freshSignedHold,"owner-readonly file bytes remain a valid fresh signed hold")
expect("CONTROL_PRESS_RELEASED"){try readonlyClockCheck()}
try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:readonlyProofFile.path)

func oneComposer()->[Int:CodexControlNode] {
    var result=twoComposers();result[1]?.children=[2];return result
}
let automatic=Fixture(oneComposer());automatic.allowAutomatic=true;automatic.nodes[0]?.children.append(8)
automatic.nodes[8]=CodexControlNode(role:"AXSearchField");automatic.focused=8
automatic.onPress={id in automatic.nodes[id]=button("Stop dictation")}
verify(try automatic.run(.dictation,phase:"down",composer:true),true,"recording","observed")
check(automatic.focusRequests==[3] && automatic.presses==[4] && automatic.lastDiagnostic?.focusAction=="confirmed","an attested hold can move focus from native chrome to the unique proven multiline composer before recording")
let alreadyFocused=Fixture(oneComposer());alreadyFocused.allowAutomatic=true;alreadyFocused.focused=3
alreadyFocused.onPress={id in alreadyFocused.nodes[id]=button("Stop dictation")}
verify(try alreadyFocused.run(.dictation,phase:"down",composer:true),true,"recording","observed")
check(alreadyFocused.focusRequests.isEmpty && alreadyFocused.lastDiagnostic?.focusAction=="none","an existing correct editable focus needs no mutation")
let twoAutomatic=Fixture(twoComposers());twoAutomatic.allowAutomatic=true
expect("CONTROL_AMBIGUOUS"){_ = try twoAutomatic.run(.dictation,phase:"down",composer:true)}
check(twoAutomatic.focusRequests.isEmpty && twoAutomatic.presses.isEmpty,"two eligible composers never become a first-match recording destination")
for variant in ["disabled","recording","single-line","foreign","not-settable"] {
    let value=Fixture(oneComposer());value.allowAutomatic=true
    switch variant {
    case "disabled":value.nodes[4]?.enabled=false
    case "recording":value.nodes[4]=button("Stop dictation")
    case "single-line":value.nodes[3]=CodexControlNode(role:"AXTextField")
    case "foreign":value.nodes[2]=CodexControlNode(role:"AXWebArea",children:[3,4],url:URL(string:"https://private-fixture.invalid/"))
    default:value.focusable=false
    }
    expect("CONTROL_FOCUS_REQUIRED"){_ = try value.run(.dictation,phase:"down",composer:true)}
    check(value.focusRequests.isEmpty && value.presses.isEmpty,"disabled, existing recording, generic text fields, foreign documents and unsettable editors cannot be automatic destinations")
}
for stage in ["before-scan","during-scan","after-focus","before-start"] {
    let value=Fixture(oneComposer());value.allowAutomatic=true
    switch stage {
    case "before-scan":value.held=false
    case "during-scan":value.onStructure={_ in value.held=false}
    case "after-focus":value.onFocus={_ in value.held=false}
    default:value.onHold={count in count<6}
    }
    expect("CONTROL_PRESS_RELEASED"){_ = try value.run(.dictation,phase:"down",composer:true)}
    check(value.presses.isEmpty && value.lastDiagnostic?.focusAction=="cancelled","release during any autofocus stage cancels before microphone start")
    check(value.focusRequests.count==(stage=="after-focus" || stage=="before-start" ? 1:0),"a released gesture cannot issue a later focus mutation")
}
let automaticChanged=Fixture(oneComposer());automaticChanged.allowAutomatic=true
automaticChanged.onStructure={_ in automaticChanged.current=CodexControlContext(bundleID:"com.openai.codex",pid:43,window:0)}
expect("CONTROL_TARGET_CHANGED"){_ = try automaticChanged.run(.dictation,phase:"down",composer:true)}
check(automaticChanged.focusRequests.isEmpty && automaticChanged.presses.isEmpty,"a process/window identity change during automatic selection causes no focus or recording")
let automaticChangedAfter=Fixture(oneComposer());automaticChangedAfter.allowAutomatic=true
automaticChangedAfter.onFocus={_ in automaticChangedAfter.current=CodexControlContext(bundleID:"com.openai.codex",pid:42,window:1)}
expect("CONTROL_TARGET_CHANGED"){_ = try automaticChangedAfter.run(.dictation,phase:"down",composer:true)}
check(automaticChangedAfter.presses.isEmpty,"a window change after focus cannot start a microphone")
let automaticOwnedUp=Fixture(oneComposer());automaticOwnedUp.allowAutomatic=true;automaticOwnedUp.held=false;automaticOwnedUp.ownedScope=2;automaticOwnedUp.nodes[4]=button("Stop dictation")
automaticOwnedUp.onPress={id in automaticOwnedUp.nodes[id]=button("Dictate")}
verify(try automaticOwnedUp.run(.dictation,phase:"up",composer:true),true,"idle","observed")
check(automaticOwnedUp.holdChecks==0 && automaticOwnedUp.focusRequests.isEmpty,"owned release needs neither a live hold proof nor a new focus")
for existing in [0,2] {
    var activated=0
    expect("TARGET_NOT_FOREGROUND"){try CodexForegroundActivation.prepare(requireHeld:{},sameProcess:{},isForeground:{false},allowActivation:true,existingCount:existing,activate:{activated+=1;return true},now:{0},deadline:1,settle:{})}
    check(activated==0,"missing or nonunique running apps are never activated")
}
var forbiddenActivation=0
expect("TARGET_NOT_FOREGROUND"){try CodexForegroundActivation.prepare(requireHeld:{},sameProcess:{},isForeground:{false},allowActivation:false,existingCount:1,activate:{forbiddenActivation+=1;return true},now:{0},deadline:1,settle:{})}
check(forbiddenActivation==0,"an explicit no-activation request cannot bring the target forward")
var cancelledActivation=0
expect("CONTROL_PRESS_RELEASED"){try CodexForegroundActivation.prepare(requireHeld:{throw CodexPhysicalHoldProof.released()},sameProcess:{},isForeground:{false},allowActivation:true,existingCount:1,activate:{cancelledActivation+=1;return true},now:{0},deadline:1,settle:{})}
check(cancelledActivation==0,"a released hold never activates the target")
var activated=0,foreground=false,activationTime=0.0
try CodexForegroundActivation.prepare(requireHeld:{},sameProcess:{},isForeground:{foreground},allowActivation:true,existingCount:1,activate:{activated+=1;return true},now:{activationTime},deadline:1,settle:{activationTime+=0.02;foreground=true})
check(activated==1 && foreground,"one permitted existing app activation is confirmed before any focus phase")
var liveActivation=true,lateActivation=0
expect("CONTROL_PRESS_RELEASED"){try CodexForegroundActivation.prepare(requireHeld:{guard liveActivation else{throw CodexPhysicalHoldProof.released()}},sameProcess:{},isForeground:{false},allowActivation:true,existingCount:1,activate:{lateActivation+=1;liveActivation=false;return true},now:{0},deadline:1,settle:{})}
check(lateActivation==1,"release while activation is in flight cancels without a later focus or recording")
var expiredActivation=0
expect("CONTROL_TARGET_CHANGED"){try CodexForegroundActivation.prepare(requireHeld:{},sameProcess:{},isForeground:{false},allowActivation:true,existingCount:1,activate:{expiredActivation+=1;return true},now:{2},deadline:1,settle:{})}
check(expiredActivation==0,"an expired shared deadline cannot activate the app")
print(String(data:try! JSONSerialization.data(withJSONObject:["checks":checks,"realAXApplications":0,"eventsPosted":0,"recordingsStarted":0]),encoding:.utf8)!)
`;
  const directory=await mkdtemp(path.join(tmpdir(),'nuphylab-codex-controls-'));
  t.after(async()=>{
    // Restore permissions even if a synthetic assertion failed before cleanup.
    await chmod(path.join(directory,'fake-ledger/owner-readonly'),0o700).catch(()=>{});
    await rm(directory,{recursive:true,force:true});
  });
  const main=path.join(directory,'main.swift'),binary=path.join(directory,'check');
  const fakeLedgerRoot=path.join(directory,'fake-ledger');
  await mkdir(path.join(fakeLedgerRoot,'private'),{recursive:true,mode:0o700});
  await mkdir(path.join(fakeLedgerRoot,'open-parent'),{mode:0o755});
  await chmod(path.join(fakeLedgerRoot,'private'),0o700);
  await chmod(path.join(fakeLedgerRoot,'open-parent'),0o755);
  await writeFile(path.join(fakeLedgerRoot,'private/valid.json'),JSON.stringify(validHold),{mode:0o600});
  await writeFile(path.join(fakeLedgerRoot,'private/public.json'),JSON.stringify(validHold),{mode:0o644});
  await chmod(path.join(fakeLedgerRoot,'private/public.json'),0o644);
  await writeFile(path.join(fakeLedgerRoot,'private/large.json'),'x'.repeat(2049),{mode:0o600});
  await writeFile(path.join(fakeLedgerRoot,'open-parent/valid.json'),JSON.stringify(validHold),{mode:0o600});
  await symlink(path.join(fakeLedgerRoot,'private/valid.json'),path.join(fakeLedgerRoot,'private/link.json'));
  await symlink(path.join(fakeLedgerRoot,'private'),path.join(fakeLedgerRoot,'parent-link'));
  await writeFile(main,fixture);
  const run=promisify(execFile);
  await run('swiftc',['-module-cache-path',path.join(directory,'module-cache'),main,'-framework','AppKit','-framework','ApplicationServices','-o',binary]);
  const result=JSON.parse((await run(binary,[fakeLedgerRoot])).stdout.trim());
  assert.ok(result.checks>=130);
  assert.equal(result.realAXApplications,0);
  assert.equal(result.eventsPosted,0);
  assert.equal(result.recordingsStarted,0);
  t.diagnostic(`${result.checks} synthetic checks; real AX applications, posted events, and recordings: 0`);
});
