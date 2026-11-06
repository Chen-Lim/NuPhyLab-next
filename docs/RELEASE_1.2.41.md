# NuPhy Lab 1.2.41

## 中文

- 新增 **实验室 → 框选提问**：按住快捷键框选屏幕内容，翻译、总结或提问；可按需开启本机语音转写。
- 增加模型选择，支持 OpenAI、Claude、Gemini、DeepSeek、通义千问和 OpenRouter 预设，以及受支持服务的账户模型列表、手动模型 ID 和兼容端点。
- 新增 **16 种翻译目标语言**，可在设置和翻译回答中切换，自动保存并独立于界面语言。
- 补齐内置作品名称、实验室、框选提示和回答操作的英文显示，统一框选灰色界面。
- 将 **发送图片** 开关移到 **按住说话** 下方。图片输入需要所选模型和接口支持；开启后按操作需要附带选区图片。
- 完善权限与实际监听状态检查，修复键盘未连接时正常备份导致的退出误提示，并让主窗口以适中大小启动。

**系统要求：** Apple Silicon；键盘功能 macOS 13.5+，框选提问 macOS 14+。框选使用自己的模型 API，服务可用性与费用由服务商和账户决定。语音在本机转写；提交的文字、问题和已启用且需要的图片发送至配置的模型服务。

保留键盘适配、连接动画及默认命令键：**F7 普通/极速、F8 批准、F9 拒绝、F10 新聊天、F11 听写、F12 发送**。升级保留作品、草稿和设置。

本次完成了本机安装、英文界面、语言设置保存及退出/重开检查；独立新 Mac 首次授权、所有语言与第三方模型组合尚未逐项验证。各型号固件与兼容范围见[键盘兼容性](https://github.com/bohu8264/NuPhyLab-next/blob/main/docs/KEYBOARD_COMPATIBILITY.md)。

## English

- Add **Labs → Ask about a selection**: hold a shortcut to select screen content for translation, summaries or questions, with optional local speech transcription.
- Expand model choices with OpenAI, Claude, Gemini, DeepSeek, Qwen and OpenRouter presets, supported account model catalogs, manual model IDs and compatible endpoints.
- Add **16 translation-language choices**, available in settings and translation answers. Your choice is saved independently of the interface language.
- Complete English labels for built-in artwork titles, Labs, selection hints and answer controls, with a consistent gray selection interface.
- Move the **image switch** below **Hold to speak**. Image input requires support from the chosen model and endpoint; enabled images are included when needed for the selected action.
- Improve permission and listener-readiness checks, fix an unnecessary quit warning for valid backups when the keyboard is disconnected, and restore a moderate launch-window size.

**Requirements:** Apple Silicon; macOS 13.5+ for keyboard features and macOS 14+ for selection. Selection uses your own model API; access and charges depend on the provider and account. Speech is transcribed locally. Submitted text, questions and any enabled images needed for the action are sent to your configured model service.

Keyboard support, connection animations and default commands remain: **F7 Standard/Fast, F8 Allow, F9 Deny, F10 New chat, F11 Dictate, F12 Send**. Updating preserves artwork, drafts and settings.

Local checks covered installation, English UI, saved language settings, quitting and reopening. First-time permissions on an independent Mac and every language/provider combination have not been individually verified. See [keyboard compatibility](https://github.com/bohu8264/NuPhyLab-next/blob/main/docs/KEYBOARD_COMPATIBILITY.md) for model and firmware coverage.

## 下载与使用 / Download and use

- [下载最新版 / Download the latest installer](https://github.com/bohu8264/NuPhyLab-next/releases/latest/download/NuPhyLab-macOS-AppleSilicon.dmg)
- [中文指南](https://github.com/bohu8264/NuPhyLab-next/blob/main/README.zh-CN.md) · [English guide](https://github.com/bohu8264/NuPhyLab-next/blob/main/README.en.md)
- [框选使用说明 / Selection guide](https://github.com/bohu8264/NuPhyLab-next/blob/main/docs/SELECTION.md)
