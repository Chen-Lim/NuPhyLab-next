import Foundation

/// Worker-owned admission and cleanup for one engine's input tap. Injection
/// tests exercise this same production state without opening an audio device.
public struct VoiceInputLifecycle {
    public enum Failure: Error, Equatable { case invalidFormat, alreadyAttempted, installationFailed }
    private var attempted = false
    private var removalNeeded = false
    public init() {}

    public mutating func install(sampleRate: Double, channelCount: UInt32,
        install: () -> Bool, remove: () -> Void) throws {
        guard !attempted else { throw Failure.alreadyAttempted }
        attempted = true
        guard sampleRate.isFinite, sampleRate > 0, channelCount > 0 else { throw Failure.invalidFormat }
        // An exception can occur after partial native setup. Own removal before
        // entering AVFAudio so failure and cancellation cannot lose cleanup.
        removalNeeded = true
        guard install() else {
            stop(remove: remove)
            throw Failure.installationFailed
        }
    }

    public mutating func stop(remove: () -> Void) {
        guard removalNeeded else { return }
        removalNeeded = false
        remove()
    }
}
