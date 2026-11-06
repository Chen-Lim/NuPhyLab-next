#import "ChordAudioBoundary.h"

// AVFAudio's graph assertions use this domain or Foundation's argument /
// consistency exceptions. This is not a general-purpose exception catcher;
// unrelated exceptions propagate, and no surrounding application work runs
// inside any @try block. A recovered engine is discarded, never restarted.
static BOOL IsAudioConfigurationException(NSException *exception) {
    return [exception.name isEqualToString:@"com.apple.coreaudio.avfaudio"] ||
        [exception.name isEqualToString:NSInvalidArgumentException] ||
        [exception.name isEqualToString:NSInternalInconsistencyException];
}

AVAudioInputNode *ChordAudioTryInputNode(AVAudioEngine *engine) {
    @try { return engine.inputNode; }
    @catch (NSException *exception) {
        if (!IsAudioConfigurationException(exception)) { @throw; }
        return nil;
    }
}

BOOL ChordAudioTryInstallTap(AVAudioNode *node, AVAudioNodeBus bus,
    AVAudioFrameCount size, AVAudioFormat *format, AVAudioNodeTapBlock block) {
    @try {
        [node installTapOnBus:bus bufferSize:size format:format block:block];
        return YES;
    } @catch (NSException *exception) {
        if (!IsAudioConfigurationException(exception)) { @throw; }
        return NO;
    }
}

BOOL ChordAudioTryRemoveTap(AVAudioNode *node, AVAudioNodeBus bus) {
    @try { [node removeTapOnBus:bus]; return YES; }
    @catch (NSException *exception) {
        if (!IsAudioConfigurationException(exception)) { @throw; }
        return NO;
    }
}
