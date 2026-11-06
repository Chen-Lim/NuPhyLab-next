import AppKit
import QuartzCore
import SwiftUI

/// The overlay, thinking state and answer share one contour, including the
/// concave shoulders. AppKit and SwiftUI only differ in coordinate direction.
enum LabNotchStyle {
 static let radius:CGFloat=18
 static func bodyPath(in rect:CGRect,camera:Bool,flipped:Bool)->CGPath {
  let p=CGMutablePath(),k:CGFloat=0.5522847498
  let b=min(radius,rect.width/2,rect.height/(camera ? 1:2)),t:CGFloat=camera ? 0:b
  let x=rect.minX,y=rect.minY,X=rect.maxX,Y=rect.maxY
  p.move(to:CGPoint(x:x+t,y:y));p.addLine(to:CGPoint(x:X-t,y:y))
  p.addCurve(to:CGPoint(x:X,y:y+t),control1:CGPoint(x:X-t+k*t,y:y),control2:CGPoint(x:X,y:y+t-k*t))
  p.addLine(to:CGPoint(x:X,y:Y-b))
  p.addCurve(to:CGPoint(x:X-b,y:Y),control1:CGPoint(x:X,y:Y-b+k*b),control2:CGPoint(x:X-b+k*b,y:Y))
  p.addLine(to:CGPoint(x:x+b,y:Y))
  p.addCurve(to:CGPoint(x:x,y:Y-b),control1:CGPoint(x:x+b-k*b,y:Y),control2:CGPoint(x:x,y:Y-b+k*b))
  p.addLine(to:CGPoint(x:x,y:y+t))
  p.addCurve(to:CGPoint(x:x+t,y:y),control1:CGPoint(x:x,y:y+t-k*t),control2:CGPoint(x:x+t-k*t,y:y));p.closeSubpath()
  guard !flipped else{return p}
  var transform=CGAffineTransform(a:1,b:0,c:0,d:-1,tx:0,ty:y+Y)
  return p.copy(using:&transform)!
 }
}
struct SelectionNotchBody:Shape {
 var camera:Bool
 func path(in rect:CGRect)->Path{Path(LabNotchStyle.bodyPath(in:rect,camera:camera,flipped:true))}
}

/// Interactive content stays below the camera. The decorative cap is click-through.
struct LabNotchLayout {
 let frame:NSRect
 let capFrame:NSRect?
 let hasCameraHousing:Bool
 let cameraWidth:CGFloat
 let maximumHeight:CGFloat
 static let shoulder=LabNotchStyle.radius

 static func place(screen:NSRect,visible:NSRect,safeTop:CGFloat,left:NSRect?,right:NSRect?,width:CGFloat,height:CGFloat,scale:CGFloat=2)->LabNotchLayout {
  let inset=max(0,min(safeTop,screen.height/3))
  let gap=(right?.minX ?? 0)-(left?.maxX ?? 0)
  let hasHousing=inset>0 && left != nil && right != nil && gap>0 && gap<screen.width/2
  let usable=visible.intersection(screen)
  let area=usable.isEmpty ? screen:usable
  let center=hasHousing ? ((left!.maxX+right!.minX)/2):screen.midX
  let top=hasHousing ? min(screen.maxY-inset,area.maxY):area.maxY-8
  let maxHeight=max(24,min(420,top-area.minY-16))
  let panelWidth=max(40,min(width,area.width-32))
  let panelHeight=max(24,min(height,maxHeight))
  let x=min(max(center-panelWidth/2,area.minX+16),area.maxX-panelWidth-16)
  let overlap=1/max(1,scale)
  let cap=hasHousing ? NSRect(x:x-shoulder,y:top-overlap,width:panelWidth+shoulder*2,height:screen.maxY-top+overlap):nil
  return LabNotchLayout(frame:NSRect(x:x,y:top-panelHeight,width:panelWidth,height:panelHeight),capFrame:cap,hasCameraHousing:hasHousing,cameraWidth:hasHousing ? gap:0,maximumHeight:maxHeight)
 }

 static func place(on screen:NSScreen,width:CGFloat,height:CGFloat)->LabNotchLayout {
  place(screen:screen.frame,visible:screen.visibleFrame,safeTop:screen.safeAreaInsets.top,left:screen.auxiliaryTopLeftArea,right:screen.auxiliaryTopRightArea,width:width,height:height,scale:screen.backingScaleFactor)
 }
}

/// Original geometry: concave shoulders join the display edge to the body.
final class SelectionNotchCapView:NSView {
 override func setFrameSize(_ newSize:NSSize){super.setFrameSize(newSize);needsDisplay=true}
 override func hitTest(_ point:NSPoint)->NSView?{nil}
 override func draw(_ dirtyRect:NSRect){NSColor.black.setFill();Self.path(in:bounds,shoulder:LabNotchLayout.shoulder).fill()}
 static func path(in rect:NSRect,shoulder:CGFloat)->NSBezierPath {
  let r=min(shoulder,rect.height),p=NSBezierPath()
  p.move(to:NSPoint(x:rect.minX,y:rect.maxY));p.line(to:NSPoint(x:rect.maxX,y:rect.maxY))
  p.curve(to:NSPoint(x:rect.maxX-r,y:rect.maxY-r),controlPoint1:NSPoint(x:rect.maxX-r,y:rect.maxY),controlPoint2:NSPoint(x:rect.maxX-r,y:rect.maxY-r/2))
  p.line(to:NSPoint(x:rect.maxX-r,y:rect.minY));p.line(to:NSPoint(x:rect.minX+r,y:rect.minY));p.line(to:NSPoint(x:rect.minX+r,y:rect.maxY-r))
  p.curve(to:NSPoint(x:rect.minX,y:rect.maxY),controlPoint1:NSPoint(x:rect.minX+r,y:rect.maxY-r/2),controlPoint2:NSPoint(x:rect.minX+r,y:rect.maxY))
  p.close();return p
 }
}

/// Measurements carry their text width; an old narrow measurement must not size
/// the newly expanded answer. Height is content-driven in both reading modes.
struct LabAnswerMeasurement:Equatable {
 var width:CGFloat=0
 var height:CGFloat=0
}
enum LabAnswerSizing {
 static let chromeHeight:CGFloat=46
 static let minimumHeight:CGFloat=64
 static func width(expanded:Bool,available:CGFloat)->CGFloat{min(available,expanded ? 630:340)}
 static func height(content:CGFloat?,expanded:Bool,fallback:CGFloat=64,chromeHeight:CGFloat=LabAnswerSizing.chromeHeight)->CGFloat {
  let limit:CGFloat=expanded ? 420:240
  let natural=content.map{ceil(max(0,$0))+chromeHeight} ?? fallback
  return min(limit,max(minimumHeight,natural.isFinite ? natural:minimumHeight))
 }
 static func accepts(_ measurement:LabAnswerMeasurement,width:CGFloat)->Bool {
  measurement.height.isFinite && measurement.height>=0 && abs(measurement.width-width)<0.5
 }
}

/// Exact critically damped spring integration. Retargeting preserves position and
/// velocity; frequent line arrivals never restart an ease-in or wait for silence.
struct LabNotchSpring {
 var value:CGFloat
 var velocity:CGFloat=0
 mutating func step(to target:CGFloat,seconds:TimeInterval,frequency:CGFloat=32){
  guard seconds.isFinite,seconds>0,target.isFinite else{return}
  let dt=CGFloat(min(seconds,0.05)),offset=value-target,c=velocity+frequency*offset,decay=exp(-frequency*dt)
  value=target+(offset+c*dt)*decay
  velocity=(velocity-frequency*c*dt)*decay
 }
 func settled(at target:CGFloat)->Bool{abs(value-target)<0.18 && abs(velocity)<2}
}

/// One display-synchronised driver moves cap and body. SwiftUI keeps text at its
/// destination width; only the viewport grows, and the link stops when settled.
@available(macOS 14, *)
@MainActor final class SelectionNotchSurface:NSObject {
 let panel:SelectionResultPanel
 private let cap:NSPanel
 private var displayLink:CADisplayLink?
 private var lastTimestamp:CFTimeInterval=0
 private var destination:LabNotchLayout?
 private var width=LabNotchSpring(value:0),height=LabNotchSpring(value:0),opacity=LabNotchSpring(value:1)
 private var dismissing=false
 /// Synthetic QA observes only geometry/cadence, never answer text or user input.
 var onFrame:((NSRect,NSRect,CFTimeInterval,Bool)->Void)?
 init(panel:SelectionResultPanel){
  self.panel=panel
  cap=NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
  super.init()
  cap.isReleasedWhenClosed=false;cap.isOpaque=false;cap.backgroundColor = .clear;cap.hasShadow=false
  cap.ignoresMouseEvents=true;cap.hidesOnDeactivate=false
  cap.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];cap.level=panel.level
  cap.contentView=SelectionNotchCapView()
 }
 func place(_ layout:LabNotchLayout,animated:Bool){
  let animate=animated && panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  if !animate {
   stop();dismissing=false;destination=layout
   width=LabNotchSpring(value:layout.frame.width);height=LabNotchSpring(value:layout.frame.height);opacity=LabNotchSpring(value:1)
   apply(layout.frame,capFrame:layout.capFrame,alpha:1);return
  }
  let same=destination?.frame==layout.frame && destination?.capFrame==layout.capFrame && !dismissing
  guard !same else{return}
  if displayLink==nil {width=LabNotchSpring(value:panel.frame.width);height=LabNotchSpring(value:panel.frame.height);opacity=LabNotchSpring(value:panel.alphaValue)}
  destination=layout;dismissing=false
  if layout.capFrame != nil,!cap.isVisible{cap.orderFrontRegardless()}
  start()
 }
 private func start(){
  guard displayLink==nil else{return}
  lastTimestamp=0
  let link=panel.displayLink(target:self,selector:#selector(tick(_:)))
  let maximum=Float(panel.screen?.maximumFramesPerSecond ?? 60)
  link.preferredFrameRateRange=CAFrameRateRange(minimum:min(60,maximum),maximum:maximum,preferred:maximum)
  displayLink=link;link.add(to:.main,forMode:.common)
 }
 private func stop(){displayLink?.invalidate();displayLink=nil;lastTimestamp=0}
 @objc private func tick(_ link:CADisplayLink){
  guard let target=destination,panel.isVisible else{stop();return}
  if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
   if dismissing{hide()}else{stop();apply(target.frame,capFrame:target.capFrame,alpha:1)};return
  }
  let now=link.targetTimestamp,dt=lastTimestamp>0 ? now-lastTimestamp:max(1/240,link.duration)
  lastTimestamp=now
  let targetHeight:CGFloat=dismissing ? 1:target.frame.height,targetAlpha:CGFloat=dismissing ? 0:1,frequency:CGFloat=dismissing ? 44:32
  let widthInFlight=abs(width.value-target.frame.width)>0.5 || abs(width.velocity)>6
  let heightFrequency:CGFloat=dismissing ? 44:(widthInFlight ? 32:56)
  width.step(to:target.frame.width,seconds:dt,frequency:frequency);height.step(to:targetHeight,seconds:dt,frequency:heightFrequency);opacity.step(to:targetAlpha,seconds:dt,frequency:frequency)
  let settled=width.settled(at:target.frame.width) && height.settled(at:targetHeight) && opacity.settled(at:targetAlpha)
  if settled {
   if dismissing{hide();onFrame?(panel.frame,target.frame,now,true);return}
   apply(target.frame,capFrame:target.capFrame,alpha:1);stop();onFrame?(target.frame,target.frame,now,true);return
  }
  let frame=NSRect(x:target.frame.midX-width.value/2,y:target.frame.maxY-height.value,width:width.value,height:height.value)
  let capFrame=target.capFrame.map{NSRect(x:frame.minX-LabNotchLayout.shoulder,y:$0.minY,width:frame.width+LabNotchLayout.shoulder*2,height:$0.height)}
  apply(frame,capFrame:capFrame,alpha:max(0,min(1,opacity.value)));onFrame?(frame,target.frame,now,false)
 }
 private func apply(_ frame:NSRect,capFrame:NSRect?,alpha:CGFloat){
  CATransaction.begin();CATransaction.setDisableActions(true)
  panel.setFrame(frame,display:false);panel.alphaValue=alpha
  if let capFrame {
   cap.setFrame(capFrame,display:false);cap.alphaValue=1
   if !cap.isVisible{cap.orderFrontRegardless()}
  }else{cap.orderOut(nil)}
  CATransaction.commit()
 }
 var windowIDs:Set<CGWindowID>{Set([panel,cap].map{CGWindowID($0.windowNumber)})}
 func show(){dismissing=false;panel.alphaValue=1;cap.alphaValue=1;panel.orderFrontRegardless()}
 func hide(){stop();dismissing=false;destination=nil;panel.orderOut(nil);cap.orderOut(nil)}
 func dismiss(to layout:LabNotchLayout){
  guard panel.isVisible,!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else{hide();return}
  if displayLink==nil {width=LabNotchSpring(value:panel.frame.width);height=LabNotchSpring(value:panel.frame.height);opacity=LabNotchSpring(value:panel.alphaValue)}
  destination=layout;dismissing=true;start()
 }
}
