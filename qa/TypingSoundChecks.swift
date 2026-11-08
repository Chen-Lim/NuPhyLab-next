import Foundation
import AVFoundation
import AudioToolbox

@main struct TypingSoundChecks {
    static func main() throws {
        var checks = [[String:Any]]()
        func check(_ name: String, _ result: Bool) { checks.append(["name":name,"passed":result]) }
        let root=URL(fileURLWithPath:CommandLine.arguments[1])
        let catalog=try JSONDecoder().decode(TypingSoundCatalog.self,from:Data(contentsOf:root.appendingPathComponent("catalog.json")))
        try catalog.validate();let ids=Set(catalog.packs.map(\.id))
        check("18 packs / 636 licensed assets",ids.count==18 && catalog.assets.count==636)
        var state=TypingPressState()
        check("first down",state.down(0,repeated:false) == .regular)
        check("duplicate down",state.down(0,repeated:false)==nil)
        check("repeat",state.down(0,repeated:true)==nil)
        check("paired up",state.up(0) == .regular && state.up(0)==nil)
        check("orphan repeat",state.down(0,repeated:true)==nil && state.up(0)==nil)
        for code in [122,120,99,118,96,97,98,100,101,109,103,111,54,55,58,59,61,62,63,53] {
            check("function/modifier/escape excluded \(code)",state.down(code,repeated:false)==nil)
        }
        for (code,group) in [(49,TypingKeyGroup.space),(36,.enter),(76,.enter),(51,.backspace),(117,.backspace),(56,.shiftLeft),(60,.shiftRight),(48,.tab),(57,.caps)] {
            check("key class \(code)",state.down(code,repeated:false)==group && state.up(code)==group)
        }
        _=state.down(49,repeated:false);state.clear();check("clear discards held releases",state.up(49)==nil && state.held.isEmpty)
        let prefs=TypingSoundPreferences()
        check("first install off",!prefs.enabled && prefs.pack=="mahjong-crisp" && prefs.volume==50)
        for bad: [String:Any] in [["pack":"../../other"],["volume":101],["volume":true],["release":-1],["enabled":1],["gains":["space":151]],["gains":["unknown":100]],["favorites":["missing"]],["text":"secret"]] {
            check("invalid settings rejected \(bad.keys.sorted())",(try? prefs.patch(bad,ids:ids))==nil)
        }
        let next=try prefs.patch(["gains":["space":75],"favorites":["wood-bamboo"],"enabled":true],ids:ids)
        check("partial group merge",next.gains["space"]==75 && next.gains["enter"]==100)
        check("preferences round trip",try JSONDecoder().decode(TypingSoundPreferences.self,from:JSONEncoder().encode(next))==next)
        check("mute exactly zero",try prefs.patch(["muted":true],ids:ids).masterGain==0)
        check("volume zero exactly zero",try prefs.patch(["volume":0],ids:ids).masterGain==0)
        check("release zero",try prefs.patch(["release":0],ids:ids).gain(group:.space,release:true)==0)
        var buffers=0,maxPeak:Float=0
        var firstBank:TypingSoundBank?
        for pack in catalog.packs {
            let bank=try TypingSoundBank(pack:pack,root:root);if firstBank==nil {firstBank=bank}
            check("complete bank \(pack.id)",bank.samples.count==16)
            for (key,list) in bank.samples {
                check("nonempty variants \(pack.id)/\(key)",!list.isEmpty)
                for b in list {
                    buffers+=1
                    let pcm=Array(UnsafeBufferPointer(start:b.floatChannelData![0],count:Int(b.frameLength)))
                    let peak=pcm.map{abs($0)}.max() ?? 0;maxPeak=max(maxPeak,peak/2)
                    check("valid PCM \(pack.id)/\(key)/\(buffers)",b.format.sampleRate==48_000 && b.format.channelCount==1 && pcm.allSatisfy{$0.isFinite} && peak>0 && pcm.last==0)
                }
            }
        }
        // CPU-only manual rendering exercises the same AU peak limiter with an
        // intentionally overloaded 32-voice mix. No audio device/input is opened.
        let e=AVAudioEngine(),format=AVAudioFormat(standardFormatWithSampleRate:48_000,channels:1)!
        let limiter=AVAudioUnitEffect(audioComponentDescription:AudioComponentDescription(componentType:kAudioUnitType_Effect,componentSubType:kAudioUnitSubType_PeakLimiter,componentManufacturer:kAudioUnitManufacturer_Apple,componentFlags:0,componentFlagsMask:0))
        e.attach(limiter);e.connect(e.mainMixerNode,to:limiter,format:format);e.connect(limiter,to:e.outputNode,format:format)
        let nodes=(0..<32).map{_ -> AVAudioPlayerNode in let p=AVAudioPlayerNode();e.attach(p);e.connect(p,to:e.mainMixerNode,format:format);return p}
        try e.enableManualRenderingMode(.offline,format:format,maximumFrameCount:1024);try e.start()
        let sample=firstBank!.samples["space/press"]![0]
        for p in nodes {p.scheduleBuffer(sample);p.play()}
        let out=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:1024)!
        var peak:Float=0,energy:Double=0,frames=0
        while frames<48_000 {
            let result=try e.renderOffline(1024,to:out)
            if result == .success { for i in 0..<Int(out.frameLength) {let value=out.floatChannelData![0][i];peak=max(peak,abs(value));energy+=Double(value*value)} }
            frames+=1024
        }
        e.stop()
        check("32 voice limiting finite and bounded",peak.isFinite && peak<=1.001 && peak>0 && energy>0)
        let result:[String:Any]=["checks":checks,"count":checks.count,"passed":checks.allSatisfy{$0["passed"] as? Bool==true},"decodedBuffers":buffers,"maxBankPeak":maxPeak,"limitedPeak":peak,"audioDeviceOpened":false,"inputMonitorStarted":false]
        print(String(data:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),encoding:.utf8)!)
        if !checks.allSatisfy({$0["passed"] as? Bool==true}) {exit(1)}
    }
}
