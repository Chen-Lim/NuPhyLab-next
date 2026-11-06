// Keyboard/updater unit harness: selection is a separate boundary under test.
// A no-op factory prevents test AppDelegate instances loading real user preferences,
// Keychain state, screen capture or global input monitors. Product integration is
// separately compiled/checked using the production SelectionFeatureFactory.
import AppKit
enum AppLanguage {case zh,en}
@MainActor protocol SelectionFeature: AnyObject {
 var showSettings:(()->Void)? {get set}
 var requestRelaunch:(()->Bool)? {get set}
 var recordingChanged:((Bool)->Void)? {get set}
 var isBusy:Bool {get}
 func updateLanguage(_ language:AppLanguage)
 func updateReservedKeys(_ codes:Set<UInt32>)
 func handle(_ body:[String:Any],reply:@escaping(Any?,String?)->Void)
 func consumeLocal(_ event:NSEvent)->Bool
 func cancel()
 func cancelShortcutRecording()
 func refreshAuthorization()
 func shutdown()
}
@MainActor enum SelectionFeatureFactory {
 static func make(directory:URL)->any SelectionFeature {SelectionBoundaryFixture()}
}
@MainActor private final class SelectionBoundaryFixture:SelectionFeature {
 var showSettings:(()->Void)?;var requestRelaunch:(()->Bool)?;var recordingChanged:((Bool)->Void)?;var isBusy=false
 func updateLanguage(_ language:AppLanguage){}
 func updateReservedKeys(_ codes:Set<UInt32>){}
 func handle(_ body:[String:Any],reply:@escaping(Any?,String?)->Void){reply(nil,"Selection boundary fixture")}
 func consumeLocal(_ event:NSEvent)->Bool{false}
 func cancel(){};func cancelShortcutRecording(){};func refreshAuthorization(){};func shutdown(){}
}
