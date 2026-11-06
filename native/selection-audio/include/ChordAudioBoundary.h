#import <AVFAudio/AVFAudio.h>

NS_ASSUME_NONNULL_BEGIN
/// These boundaries cover only AVAudio input/tap operations. No exception
/// reason, userInfo, audio data or device identifier leaves this module.
AVAudioInputNode * _Nullable ChordAudioTryInputNode(AVAudioEngine *engine);
BOOL ChordAudioTryInstallTap(AVAudioNode *node, AVAudioNodeBus bus,
    AVAudioFrameCount size, AVAudioFormat *format, AVAudioNodeTapBlock block);
BOOL ChordAudioTryRemoveTap(AVAudioNode *node, AVAudioNodeBus bus);
NS_ASSUME_NONNULL_END
