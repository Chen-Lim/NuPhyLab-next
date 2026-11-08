# NuPhy Lab 1.2.43

## 中文

- 新增 **模拟声浪**，位于侧栏“灯光游戏”下方：麻将、奶油、木质、轻柔、段落和复古六类，每类三款，共 18 款声音。
- 支持后台打字播放、试听、收藏、总音量、回弹强度和自然变化。空格、回车、退格、左右 Shift、Tab、Caps Lock 可分别调节音量。
- 声音随应用提供，无需联网下载或 API。首次默认关闭；点击试听不需要输入监控，开启打字播放需要输入监控权限。声浪不记录文字、不保留按键历史、不上传输入。

原有键盘适配、连接动画、AI 功能键和框选提问保留。升级保留作品、草稿和设置。

**系统要求：** Apple Silicon；键盘与声浪功能 macOS 13.5+，框选提问 macOS 14+。声音通过 Mac 当前音频输出播放。12 款调校音色来自三段公开录音，6 款经典音色来自授权采样，完整来源与许可随应用提供。

**使用提示：** 声浪会在本软件听写、语音框选、麦克风律动，以及安全输入、锁屏、休眠和快捷键录制期间暂停。若无法确认 F11 听写已停止，请先在 Codex 停止听写，再关闭并重新开启模拟声浪。设置窗口异常后若录制暂停持续，可退出重开 NuPhy Lab。

本次完成隔离回归、音频解码与混音检查，以及本机安装和界面检查。新 Mac 首次授权、实际听写与声浪共用、外接音频设备切换和各键盘实体按键尚未逐项验证。

## English

- Add **Typing Sounds** below **Lighting Games** in the sidebar: 18 sounds, with three each in Marbly, Creamy, Woody, Soft, Tactile and Retro.
- Play sounds while typing in other apps, preview sounds and save favorites. Adjust master volume, release strength, natural variation, and separate levels for Space, Return, Backspace, left/right Shift, Tab and Caps Lock.
- Sounds are bundled and need no download or API. The feature starts off. Click previews need no Input Monitoring permission; typing playback does. Typing Sounds does not record text, retain key history or upload input.

Existing keyboard support, connection animations, AI function keys and selection features are retained. Updating preserves artwork, drafts and settings.

**Requirements:** Apple Silicon; macOS 13.5+ for keyboard and typing sounds, and macOS 14+ for selection. Sounds play through the Mac's current audio output. Twelve tuned sounds derive from three public recordings; six classics use licensed samples. Full credits and licenses are bundled.

**Usage notes:** Sounds pause during this app's dictation, voice selection and microphone lighting capture, as well as Secure Input, screen lock, sleep and shortcut recording. If F11 dictation cannot be confirmed stopped, stop dictation in Codex, then turn Typing Sounds off and on. If an interrupted settings window leaves the recording pause active, quit and reopen NuPhy Lab.

This update completed isolated regression, audio decoding and mixing checks, plus local installation and interface checks. First-time permissions on a new Mac, actual dictation alongside typing sounds, external audio-device switching and physical keys on every keyboard have not been individually verified.

## 下载与使用 / Download and use

- [下载最新版 / Download the latest installer](https://github.com/bohu8264/NuPhyLab-next/releases/latest/download/NuPhyLab-macOS-AppleSilicon.dmg)
- [中文指南](https://github.com/bohu8264/NuPhyLab-next/blob/main/README.zh-CN.md) · [English guide](https://github.com/bohu8264/NuPhyLab-next/blob/main/README.en.md)
- [模拟声浪说明 / Typing Sounds guide](https://github.com/bohu8264/NuPhyLab-next/blob/main/docs/TYPING_SOUNDS.md)
