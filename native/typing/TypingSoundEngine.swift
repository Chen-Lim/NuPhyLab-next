import Foundation
import AVFoundation
import AudioToolbox

// Buffers are decoded once on a worker queue. The event callback never reads files.
final class TypingSoundBank {
    let id: String
    let samples: [String:[AVAudioPCMBuffer]]
    let gain: Float
    init(pack: TypingSoundPack, root: URL) throws {
        id = pack.id
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        var decoded = [String:[Float]]()
        for group in TypingKeyGroup.allCases { for release in [false,true] {
            for path in pack.paths(group, release: release) where decoded[path] == nil {
                let file = try AVAudioFile(forReading: root.appendingPathComponent("audio/\(pack.id)/\(path)"))
                guard file.length > 0, file.length < 2_000_000,
                      let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw TypingSoundError.audio }
                try file.read(into: input)
                guard let converter = AVAudioConverter(from: input.format, to: format),
                      let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(ceil(Double(input.frameLength) * 48_000 / input.format.sampleRate)) + 128) else { throw TypingSoundError.audio }
                var supplied = false, error: NSError?
                let result = converter.convert(to: output, error: &error) { _, status in
                    if supplied { status.pointee = .endOfStream; return nil }
                    supplied = true; status.pointee = .haveData; return input
                }
                guard error == nil, result != .error, output.frameLength > 0, let channel = output.floatChannelData?[0] else { throw TypingSoundError.audio }
                var values = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
                guard values.allSatisfy({ $0.isFinite }) else { throw TypingSoundError.audio }
                let first = values.firstIndex { abs($0) >= 0.001 } ?? 0
                values.removeFirst(max(0, first - 48))
                decoded[path] = values
            }
        } }
        let peak = decoded.values.flatMap { $0 }.map { abs($0) }.max() ?? 0
        guard peak > 0 else { throw TypingSoundError.audio }
        let normalization: Float = pack.designed == true ? 1 : min(8, 0.65 / max(0.01,peak))
        gain = normalization
        var bank = [String:[AVAudioPCMBuffer]]()
        for group in TypingKeyGroup.allCases { for release in [false,true] {
            let key = Self.key(group, release)
            bank[key] = try pack.paths(group, release: release).map { path in
                var samples = decoded[path]!
                if pack.designed != true, [.shiftLeft,.shiftRight,.tab,.caps].contains(group) {
                    let hz: Double = [.shiftLeft:620,.shiftRight:720,.tab:1100,.caps:880][group]!
                    samples = Self.filter(samples, hz: hz, peak: true)
                    samples = Self.filter(samples, hz: [.shiftLeft,.shiftRight].contains(group) ? 7000 : 11000, peak: false)
                    let rate: Double = [.shiftLeft:0.96,.shiftRight:0.98,.tab:1.02,.caps:0.99][group]!
                    let original = samples
                    samples = (0..<Int(Double(original.count)/rate)).map { i in
                        let position = Double(i)*rate, left = min(original.count-1,Int(position)), right = min(original.count-1,left+1)
                        return original[left] + (original[right]-original[left])*Float(position-Double(left))
                    }
                }
                let count = min(samples.count,144)
                for i in 0..<count { samples[samples.count-count+i] *= Float(count-1-i)/Float(max(1,count-1)) }
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { throw TypingSoundError.audio }
                buffer.frameLength = buffer.frameCapacity
                // AVAudioMixing.volume is limited to 0...1. Bake normalization and
                // 2x headroom into float PCM; apply 0.5x at playback so 150% key
                // gain and natural variation stay inside the supported volume range.
                for i in samples.indices { buffer.floatChannelData![0][i] = samples[i] * normalization * 2 }
                return buffer
            }
        } }
        samples = bank
    }
    static func key(_ group: TypingKeyGroup, _ release: Bool) -> String { group.rawValue + (release ? "/release" : "/press") }
    private static func filter(_ x: [Float], hz: Double, peak: Bool) -> [Float] {
        let w = 2 * Double.pi * hz / 48_000, c = cos(w), a = sin(w) / (2 * (peak ? 1.7 : sqrt(0.5))), A = pow(10,3.0/40)
        let b0 = peak ? 1+a*A : (1-c)/2, b1 = peak ? -2*c : 1-c, b2 = peak ? 1-a*A : (1-c)/2
        let a0 = peak ? 1+a/A : 1+a, a1 = -2*c, a2 = peak ? 1-a/A : 1-a
        var x1=0.0,x2=0.0,y1=0.0,y2=0.0
        return x.map { f in
            let value=Double(f), y=(b0*value+b1*x1+b2*x2-a1*y1-a2*y2)/a0
            x2=x1;x1=value;y2=y1;y1=y;return Float(y)
        }
    }
}

// All engine and player operations use one serial queue; max 32 concurrent voices.
final class TypingSoundEngine {
    private let queue = DispatchQueue(label:"NuPhyLab.TypingAudio", qos:.userInteractive)
    private let loader = DispatchQueue(label:"NuPhyLab.TypingSamples", qos:.userInitiated)
    private var engine: AVAudioEngine?
    private var limiter: AVAudioUnitEffect?
    private var players = [AVAudioPlayerNode]()
    private var tokens = [Int](repeating:0,count:32)
    private var active = [Bool](repeating:false,count:32)
    private var order = 0
    private var epoch = 0
    private var settings = TypingSoundPreferences()
    private var cache = [String:TypingSoundBank]()
    private var cacheOrder = [String]()
    private var previous = [String:Int]()
    private var configurationObserver: NSObjectProtocol?
    private let configurationLock=NSLock()
    private var configurationEpoch=UUID()
    private func changeEpoch() { configurationLock.lock();configurationEpoch=UUID();configurationLock.unlock() }
    private func currentEpoch() -> UUID { configurationLock.lock();defer { configurationLock.unlock() };return configurationEpoch }
    var configurationChanged: (() -> Void)?

    func load(_ pack: TypingSoundPack, root: URL, completion: @escaping (Result<TypingSoundBank,Error>)->Void) {
        loader.async {
            let result: Result<TypingSoundBank,Error>
            do {
                let bank: TypingSoundBank
                if let existing = self.cache[pack.id] { bank=existing }
                else { bank=try TypingSoundBank(pack:pack,root:root); self.cache[pack.id]=bank }
                self.cacheOrder.removeAll { $0 == pack.id };self.cacheOrder.append(pack.id)
                while self.cacheOrder.count > 3 { self.cache.removeValue(forKey:self.cacheOrder.removeFirst()) }
                result = .success(bank)
            } catch { result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }
    }
    func prepare(completion: @escaping (Bool)->Void) {
        queue.async {
            do { try self.start();DispatchQueue.main.async { completion(true) } }
            catch { DispatchQueue.main.async { completion(false) } }
        }
    }
    private func start() throws {
        if engine == nil {
            let e=AVAudioEngine()
            let output=e.outputNode.outputFormat(forBus:0)
            guard output.sampleRate > 0,output.channelCount > 0 else { throw TypingSoundError.audio }
            let limit=AVAudioUnitEffect(audioComponentDescription:AudioComponentDescription(componentType:kAudioUnitType_Effect,componentSubType:kAudioUnitSubType_PeakLimiter,componentManufacturer:kAudioUnitManufacturer_Apple,componentFlags:0,componentFlagsMask:0))
            e.attach(limit)
            e.connect(e.mainMixerNode,to:limit,format:nil);e.connect(limit,to:e.outputNode,format:nil)
            let format=AVAudioFormat(standardFormatWithSampleRate:48_000,channels:1)!
            players=(0..<32).map { _ in let p=AVAudioPlayerNode();e.attach(p);e.connect(p,to:e.mainMixerNode,format:format);return p }
            engine=e;limiter=limit
            let origin=currentEpoch()
            configurationObserver=NotificationCenter.default.addObserver(forName:.AVAudioEngineConfigurationChange,object:e,queue:nil) { [weak self] _ in
                // Never tear down the engine synchronously on Core Audio's callback.
                DispatchQueue.main.async { guard let self,self.currentEpoch()==origin else { return };self.configurationChanged?() }
            }
        }
        let hardware=engine!.outputNode.outputFormat(forBus:0)
        guard hardware.sampleRate > 0,hardware.channelCount > 0 else { throw TypingSoundError.audio }
        engine!.mainMixerNode.outputVolume=settings.masterGain
        if !engine!.isRunning { engine!.prepare();try engine!.start() }
    }
    func update(_ value: TypingSoundPreferences) {
        queue.async { self.settings=value;self.engine?.mainMixerNode.outputVolume=value.masterGain;if value.muted || value.volume==0 { self.stopVoices() } }
    }
    func hit(_ bank: TypingSoundBank, group: TypingKeyGroup, release: Bool, received: TimeInterval) {
        queue.async {
            // A stalled queue never replays old typing as a burst.
            guard ProcessInfo.processInfo.systemUptime-received < 0.08 else { return }
            self.play(bank,group:group,release:release)
        }
    }
    private func play(_ bank: TypingSoundBank, group: TypingKeyGroup, release: Bool) {
        guard let engine,engine.isRunning,settings.masterGain > 0 else { return }
        let key=TypingSoundBank.key(group,release)
        guard let buffers=bank.samples[key],!buffers.isEmpty else { return }
        let previousKey=bank.id+key, last=previous[previousKey] ?? -1
        let choices=Array(buffers.indices).filter { $0 != last }
        let index=settings.variation ? (choices.randomElement() ?? 0) : buffers.count/2
        previous[previousKey]=index
        let slot=active.firstIndex(of:false) ?? (order % 32);order+=1
        let player=players[slot];tokens[slot]+=1;let token=tokens[slot]
        player.stop();active[slot]=true
        player.volume=settings.gain(group:group,release:release)*0.5*(settings.variation ? Float.random(in:0.97...1.03) : 1)
        player.scheduleBuffer(buffers[index],completionCallbackType:.dataPlayedBack) { [weak self] _ in
            guard let self else { return };self.queue.async { if self.tokens[slot]==token { self.active[slot]=false } }
        }
        player.play()
    }
    func preview(_ bank: TypingSoundBank, groups: [TypingKeyGroup], completion: @escaping ()->Void) {
        queue.async {
            self.epoch+=1;let token=self.epoch;self.stopVoices()
            for (i,group) in groups.enumerated() { for release in [false,true] {
                self.queue.asyncAfter(deadline:.now()+0.012+Double(i)*0.2+(release ? 0.075 : 0)) {
                    guard self.epoch==token else { return };self.play(bank,group:group,release:release)
                }
            } }
            self.queue.asyncAfter(deadline:.now()+Double(groups.count)*0.2+0.6) {
                guard self.epoch==token else { return };DispatchQueue.main.async { completion() }
            }
        }
    }
    private func stopVoices() {
        for (i,p) in players.enumerated() { tokens[i]+=1;p.stop();active[i]=false }
    }
    func stop(pause: Bool = false, rebuild: Bool = false) {
        if rebuild { changeEpoch() }
        queue.async {
            self.epoch+=1;self.stopVoices()
            if pause { self.engine?.stop() }
            if rebuild {
                self.changeEpoch()
                if let observer=self.configurationObserver { NotificationCenter.default.removeObserver(observer) };self.configurationObserver=nil
                self.engine?.stop();self.players=[];self.engine=nil;self.limiter=nil
            }
        }
    }
}
