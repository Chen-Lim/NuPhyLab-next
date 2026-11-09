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
