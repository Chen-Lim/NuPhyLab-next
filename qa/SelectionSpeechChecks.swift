import Foundation
import AppKit

/// Isolated production capture-service checks. The driver substitutes OS audio
/// effects only; it never opens a microphone, accesses TCC, or sends API traffic.
@main struct SelectionSpeechChecks {
 @MainActor static func main() async throws {
  var checks=0
  func check(_ value:Bool,_ message:String){checks+=1;precondition(value,message)}
  let safety=SelectionSafety(paused:false,secureInput:false,accessibility:true,inputMonitoring:true,screenCapture:true)
  let silence=VoiceAudioResult(text:nil,isFinal:false,failureDomain:"kAFAssistantErrorDomain",failureCode:1110)
  func service(_ language:AppLanguage)->VoiceCaptureService {
   let value=VoiceCaptureService();value.language=language
   value.captureTestDriver = .init(onStart:{_ in},onFinishInput:{_ in},finalizationTimeout:0.03)
   return value
  }
  for language in [AppLanguage.zh,.en] {
   for action:SelectionAction in [.translate(targetLanguage:"Japanese"),.summarize,.explain] {
    for finishFirst in [false,true] {for captureFirst in [false,true] {for incoming:String? in [nil," \n"] {
     let voice=service(language);var selection=SelectionSession()
     let handle=selection.begin(voiceExpected:true,defaultAction:action)
     var results=[InteractionTranscript]();var ended=0
     voice.onRecordingEnded={ended+=1}
     voice.onResolved={_,result in
      results.append(result)
      switch result {case .final(let text):selection.voiceFinished(text,for:handle)
       case .partial,.unavailable:selection.voiceFailed(for:handle)}
     }
     voice.start(objectIDs:[]);let token=voice.session.generation
     if captureFirst{selection.captured(.init(text:"Only selected text"),for:handle)}
     if finishFirst{voice.stop()}
     voice.receiveTestResult(.init(text:incoming,isFinal:finishFirst,failureDomain:"kAFAssistantErrorDomain",failureCode:1110),token:token)
     check(results == [.final("")],"silence resolves empty once in both UI languages")
     check(voice.issue==nil && voice.diagnostic==nil && voice.session.phase == .ready,"no silence error")
     check(ended==1 && !voice.isActive,"audio ends exactly once")
     check(try selection.takeWork(safety:safety)==nil,"held selection cannot auto-submit")
     if !captureFirst{selection.captured(.init(text:"Only selected text"),for:handle)}
     selection.release(handle)
     check(try selection.takeWork(safety:safety)?.action==action,"silence preserves translate/summarize/explain")
     voice.receiveTestResult(silence,token:token)
     check(results.count==1 && ended==1,"late terminal callback ignored")
     check(try selection.takeWork(safety:safety)==nil,"one request per selection")
    }}}
   }
   for (domain,code,prior,incoming) in [
    ("kAFAssistantErrorDomain",1110,"spoken partial",nil as String?),
    ("kAFAssistantErrorDomain",1110,"","spoken final"),
    ("other-domain",1110,"",nil),
    ("kAFAssistantErrorDomain",1101,"",nil),
    ("kAFAssistantErrorDomain",1700,"",nil),
    ("kLSRErrorDomain",102,"",nil)
   ] {
    let voice=service(language);var selection=SelectionSession();let handle=selection.begin(voiceExpected:true,defaultAction:.summarize)
    selection.captured(.init(text:"Only selected text"),for:handle);selection.release(handle)
    var results=[InteractionTranscript]()
    voice.onResolved={_,result in results.append(result);switch result{case .final(let text):selection.voiceFinished(text,for:handle);case .partial,.unavailable:selection.voiceFailed(for:handle)}}
    voice.start(objectIDs:[]);let token=voice.session.generation
    if !prior.isEmpty{voice.receiveTestResult(.init(text:prior,isFinal:false,failureDomain:nil,failureCode:nil),token:token)}
    voice.receiveTestResult(.init(text:incoming,isFinal:true,failureDomain:domain,failureCode:code),token:token)
    check(results == [prior.isEmpty ? .unavailable:.partial(prior)],"real failures remain distinct from silence")
    check(voice.issue != nil && voice.session.phase == .unavailable,"real failure visible")
    check(try selection.takeWork(safety:safety)==nil,"failure never submits default or partial instruction")
   }
   let voice=service(language);var results=[InteractionTranscript]()
   voice.onResolved={_,value in results.append(value)}
   voice.start(objectIDs:[]);let token=voice.session.generation
   check(voice.captureTestLocaleIdentifier==SpeechRecognitionPolicy.preferredLocaleIdentifier(),"UI does not override system speech locale")
   voice.language = language == .en ? .zh:.en
   check(voice.captureTestLocaleIdentifier==SpeechRecognitionPolicy.preferredLocaleIdentifier() && voice.isActive,"UI change does not cancel/reconfigure audio")
   voice.receiveTestResult(.init(text:"Explain this sentence",isFinal:true,failureDomain:nil,failureCode:nil),token:token)
   check(results == [.final("Explain this sentence")],"spoken instruction is preserved")
   voice.start(objectIDs:[]);let cancelled=voice.session.generation;voice.cancel()
   voice.receiveTestResult(silence,token:cancelled);check(results.count==1,"cancelled callback ignored")
   voice.localeIdentifierOverride="ja-JP";voice.start(objectIDs:[])
   check(voice.captureTestLocaleIdentifier=="ja-JP","explicit speech locale preserved")
   voice.receiveTestResult(silence,token:cancelled);check(results.count==1 && voice.isActive,"old session cannot resolve new recording")
   voice.cancel()
  }
  for (languages,expected) in [(["zh-Hans-CN","en-US"],"zh-CN"),(["zh-Hant"],"zh-TW"),(["en-GB","zh-CN"],"en-GB"),(["en"],"en-US"),(["ja-JP"],"ja-JP"),([],"en-US")] {
   check(SpeechRecognitionPolicy.preferredLocaleIdentifier(preferredLanguages:languages)==expected,"system locale retained and normalized")
  }
  let cancelled=service(.en);var callbacks=0;cancelled.onResolved={_,_ in callbacks+=1}
  cancelled.onTranscript={_ in cancelled.cancel()};cancelled.start(objectIDs:[])
  cancelled.receiveTestResult(silence,token:cancelled.session.generation)
  check(callbacks==0 && !cancelled.isActive,"synchronous cancellation cannot revive result")
  let timeout=service(.en);var timedOut=[InteractionTranscript]()
  timeout.onResolved={_,value in timedOut.append(value)};timeout.start(objectIDs:[]);timeout.stop()
  try await Task.sleep(for:.milliseconds(100))
  check(timedOut == [.partial("")],"missing terminal callback remains a timeout, not silence")
  print("Selection speech checks passed: \(checks); no microphone, permissions or network used")
 }
}
