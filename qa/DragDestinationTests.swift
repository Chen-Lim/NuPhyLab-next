import AppKit
import QuartzCore

final class TestDrag: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .copy
    var draggingLocation = NSPoint.zero
    var draggedImageLocation = NSPoint.zero
    var draggedImage: NSImage? = nil
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSource: Any? = nil
    var draggingSequenceNumber = 1
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight = .none
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    deinit { draggingPasteboard.releaseGlobally() }
}

@main struct DragDestinationTests {
    static var checks = 0
    static func check(_ condition: Bool, _ name: String) { guard condition else {fatalError(name)};checks += 1 }
    static func main() throws {
        _ = NSApplication.shared
        let file = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL.appendingPathComponent("transparent.png")
        let window = NSWindow(contentRect: CGRect(x:0,y:0,width:252,height:252),styleMask:.borderless,backing:.buffered,defer:false)
        let view = DragConvertWheelView(frame: CGRect(x:0,y:0,width:252,height:252));window.contentView = view
        let drag = TestDrag();drag.draggingDestinationWindow = window
        drag.draggingPasteboard.clearContents();check(drag.draggingPasteboard.writeObjects([file as NSURL]),"fixture file URL writes")
        var picked: DragFormat?;var count = 0
        view.onDrop = { format,urls in picked = format;count += 1;check(urls == [file],"actual pasteboard files delivered");return true }
        func setup() {
            view.configure(urls:[file],english:false);view.activationPoint = DragWheelGeometry.center;view.hasMovedFromActivation = false
            drag.draggingSourceOperationMask = .copy;drag.draggingLocation = DragWheelGeometry.center;picked = nil
        }
        setup()
        check(view.draggingEntered(drag).isEmpty,"initial centre does not accept")
        check(!view.prepareForDragOperation(drag),"centre prepare rejects")
        check(!view.performDragOperation(drag),"centre cannot convert")
        drag.draggingLocation=DragWheelGeometry.labelPoint(0, count: 9)
        check(view.draggingUpdated(drag) == .copy,"hover copy accepted")
        // Releasing at PNG after the last hover reported JPG must choose PNG.
        drag.draggingLocation=DragWheelGeometry.labelPoint(1, count: 9)
        check(view.prepareForDragOperation(drag),"fresh location prepare")
        let accepted=view.performDragOperation(drag)
        check(accepted && picked == .png,"release location wins over stale hover")
        check(!view.performDragOperation(drag) && count == 1,"duplicate callback cannot submit twice")
        setup();drag.draggingLocation=DragWheelGeometry.labelPoint(0, count: 9)
        _=view.draggingUpdated(drag);drag.draggingLocation=CGPoint(x:1,y:1)
        check(!view.performDragOperation(drag),"outside release cannot submit stale selection")
        setup();drag.draggingLocation=DragWheelGeometry.labelPoint(0, count: 9);drag.draggingSourceOperationMask=[.move,.delete]
        check(!view.performDragOperation(drag),"move-only sources refused")
        setup();drag.draggingLocation=DragWheelGeometry.labelPoint(0, count: 9)
        drag.draggingPasteboard.clearContents();drag.draggingPasteboard.writeObjects([file.deletingLastPathComponent().appendingPathComponent("portrait.jpg") as NSURL])
        check(!view.performDragOperation(drag),"pasteboard replacement refused")
        drag.draggingPasteboard.clearContents();drag.draggingPasteboard.clearContents();check(drag.draggingPasteboard.writeObjects([file as NSURL]),"fixture file URL writes")
        setup();view.activationPoint=DragWheelGeometry.labelPoint(5, count: 9);drag.draggingLocation=view.activationPoint
        check(!view.performDragOperation(drag),"edge clamp cannot auto-select on first frame")
        drag.draggingLocation.x += 9
        check(view.performDragOperation(drag) && picked == .small,"intentional motion arms clamped menu")
        setup();drag.draggingLocation=DragWheelGeometry.labelPoint(2,count:9)
        check(view.performDragOperation(drag) && picked == .webp,"WebP actual drop chooses encoder action")
        setup();view.invalidateSession();drag.draggingLocation=DragWheelGeometry.labelPoint(0, count: 9)
        check(!view.performDragOperation(drag),"hidden cancelled session rejects drop")
        setup();var ended=false;view.onSessionEnd={ended=true};view.draggingEnded(drag)
        check(ended,"system drag end dismisses")
        let frameBefore=window.frame
        let start=CACurrentMediaTime()
        for _ in 0..<1_000 { for i in 0..<9 { view.trackPoint(DragWheelGeometry.labelPoint(i, count: 9)) } }
        let elapsed=(CACurrentMediaTime()-start)*1000
        check(window.frame==frameBefore,"hover never moves the destination window")
        let result:[String:Any]=["passed":true,"checks":checks,"hoverCalls":9000,"hoverAverageMilliseconds":elapsed/9000,"scope":"production native view with synthetic NSDraggingInfo; not Finder/physical end-to-end"]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:file.deletingLastPathComponent().appendingPathComponent("DESTINATION_RESULT.json"))
        print(result)
        window.orderOut(nil)
    }
}
