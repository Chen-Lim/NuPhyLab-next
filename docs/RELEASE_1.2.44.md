# NuPhy Lab 1.2.44

## 中文

- 新增 **实验室 → 演奏模式**：六种音色、八个鼓垫、16 步鼓机和八个可自由分配的片段槽位。
- 作品库提供 **18 首原创预设和 36 个片段**。选择目标槽位后放入素材，支持录制、叠录、量化、撤销和循环播放。
- 个人作品自动保存在本机，可复制、改名、删除后恢复，并导出工程或 WAV。声音随应用提供，无需 API 或麦克风权限。
- 加强作品保存保护：删除或恢复与保存同时发生时，暂停旧页面保存，保留当前草稿供导出；退出和更新前等待保存完成。

保留模拟声浪、键盘灯效、连接动画、AI 助手与框选提问。演奏界面和使用说明均提供中英文。

**使用方式：** 打开“实验室 → 演奏模式”，开启演奏后按界面标示的键演奏。演奏按键仅在该窗口前台生效。切换应用会释放按住的音符；最小化、关闭窗口或休眠会停止播放。前台演奏暂停模拟声浪；本软件的听写和麦克风录音会暂停演奏。若听写结束未能确认，请确认 Codex 已停止录音后再恢复演奏。

遇到保存冲突时，请先导出当前工程，再从 **窗口 → 恢复演奏页面** 打开已保存作品。升级保留原有作品、草稿和设置；本机音乐实验版作品会尝试非覆盖导入，原文件保留。

**要求与验证范围：** Apple Silicon，macOS 13.5+；框选提问需要 macOS 14+。本次完成保存冲突、草稿保护等隔离回归，以及签名、包内资源和界面可重建性核对。新 Mac 首次安装与授权、各键盘实体演奏、外接音频、最低系统、原生页面崩溃恢复和完整自动升级尚未逐项验证。

## English

- Add **Labs → Performance** with six instruments, eight drum pads, a 16-step sequencer and eight assignable clip slots.
- Start with **18 original presets and 36 clips**. Choose a destination slot before adding a clip, then record, overdub, quantize, undo and loop your arrangement.
- Personal works autosave locally. Duplicate, rename, restore deleted works, and export projects or WAV audio. Sounds are bundled; no API or microphone permission is needed.
- Improve save protection: when deletion or restoration overlaps a save, the old page pauses saving and retains its draft for export. Quitting and updating wait for saves to finish.

Typing Sounds, keyboard lighting, connection animations, AI Assistant and selection features are retained. Performance and its documentation are available in Chinese and English.

**Usage:** Open **Labs → Performance**, enable it, and play the keys shown on screen. Performance keys work only while that window is in front. Switching apps releases held notes; minimizing, closing the window or sleeping stops playback. Foreground performance pauses Typing Sounds. This app's dictation and microphone capture pause performance. If dictation completion cannot be confirmed, check that Codex has stopped recording before resuming performance.

If saving pauses because of a conflict, export the current project first, then use **Window → Recover Performance Page** to reopen saved works. Updating preserves existing works, drafts and settings. The app attempts to import local music-experiment works without overwriting existing works or removing the originals.

**Requirements and validation:** Apple Silicon, macOS 13.5+; selection requires macOS 14+. This release completed isolated save-conflict and draft-preservation regression checks, plus signature, bundled-resource and reproducible UI-build verification. First installation and permissions on a new Mac, physical playing on every keyboard, external audio devices, the minimum OS, native page-crash recovery and the full automatic upgrade flow have not been individually verified.

## 下载与使用 / Download and use

- [下载最新版 / Download the latest installer](https://github.com/bohu8264/NuPhyLab-next/releases/latest/download/NuPhyLab-macOS-AppleSilicon.dmg)
- [中文指南](https://github.com/bohu8264/NuPhyLab-next/blob/main/README.zh-CN.md) · [English guide](https://github.com/bohu8264/NuPhyLab-next/blob/main/README.en.md)
- [演奏说明与音源 / Performance guide and sound credits](https://github.com/bohu8264/NuPhyLab-next/blob/main/docs/PERFORMANCE.md)
