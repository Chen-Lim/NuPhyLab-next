# NuPhy Lab 1.2.42

## 中文

- 修复英文界面下，只框选、不说话时出现“本机转录已停止”提示，阻止翻译、总结和解释的问题。
- 界面语言与本机语音识别语言独立；切换软件语言不再改变正在进行的录音识别语言或中止录音。
- 语言选择中的 **简体中文** 始终保留中文名称。

现有键盘适配、连接动画、AI 功能键和翻译目标语言设置保留。升级保留作品、草稿和设置。

**系统要求：** Apple Silicon；键盘功能 macOS 13.5+，框选提问 macOS 14+。框选使用你配置的模型服务与 API Key。语音在本机转写，录音不上传。

本次已完成隔离回归及本机英文界面实体框选验证，翻译、总结、解释均正常。独立新 Mac 首次授权、所有语言与模型组合仍未逐项验证。

## English

- Fix the “Local transcription stopped” message blocking translation, summaries and explanations when selecting without speaking in the English interface.
- Keep the interface language independent from local speech recognition. Changing the app language no longer changes the recognition language or cancels an active recording.
- Keep **简体中文** as the Simplified Chinese option's label in language menus.

Keyboard support, connection animations, AI function keys and saved translation targets are retained. Updating preserves artwork, drafts and settings.

**Requirements:** Apple Silicon; macOS 13.5+ for keyboard features and macOS 14+ for selection. Selection uses your configured model service and API key. Speech is transcribed locally; recordings are not uploaded.

This update passed isolated regression checks and local physical-shortcut tests for silent selections in the English interface: Translate, Summarize and Explain all worked. First-time permissions on an independent Mac and every language/model combination have not been individually verified.

## 下载与使用 / Download and use

- [下载最新版 / Download the latest installer](https://github.com/bohu8264/NuPhyLab-next/releases/latest/download/NuPhyLab-macOS-AppleSilicon.dmg)
- [中文指南](https://github.com/bohu8264/NuPhyLab-next/blob/main/README.zh-CN.md) · [English guide](https://github.com/bohu8264/NuPhyLab-next/blob/main/README.en.md)
- [框选使用说明 / Selection guide](https://github.com/bohu8264/NuPhyLab-next/blob/main/docs/SELECTION.md)
