# NuPhy Lab

[简体中文指南](README.zh-CN.md) · [English guide](README.en.md)

为 **NuPhy AIR75 V3 和 Kick75（ANSI）** 提供灯光创作、键盘游戏、声音律动，以及 Codex / Claude Code 任务快捷键和状态灯。

A macOS lighting studio for **NuPhy AIR75 V3 and Kick75 (ANSI)**, with keyboard games, audio-reactive lighting, and Codex / Claude Code task shortcuts and status lights.

## 下载 / Download

### [直接下载最新版安装包 · Download the latest macOS installer](https://github.com/bohu8264/NuPhyLab-next/releases/latest/download/NuPhyLab-macOS-AppleSilicon.dmg)

**Apple Silicon · macOS 13.5 或以上 / macOS 13.5 or later**

- [最新版本与更新说明 / Latest release and notes](https://github.com/bohu8264/NuPhyLab-next/releases/latest)
- [当前维护的源码 / Current maintained source](https://github.com/bohu8264/NuPhyLab-next/tree/main)
- [历史版本 / Previous releases](https://github.com/bohu8264/NuPhyLab-next/releases)

安装包使用 NuPhy 公司 Developer ID 签名并完成 Apple 公证。上方下载链接始终指向最新正式版，后续更新无需更换分享地址。

The installer is signed with NuPhy's Developer ID and notarized by Apple. The download link always points to the latest stable release, so it can be reused for future updates.

## 安装与更新 / Install and update

1. 退出旧版 NuPhy Lab，打开 DMG，将 **NuPhy Lab** 拖入「应用程序」。保留本机应用数据，继续使用原有作品、草稿和设置。

   Quit the old NuPhy Lab app, open the DMG, and drag **NuPhy Lab** to Applications. Keep the app-data folder to retain your artwork, drafts and settings.

2. 用 USB 数据线连接键盘并切到有线模式。按软件提示授予输入监控和辅助功能权限；首次授权后，软件可能自动关闭并重新打开一次，使新权限生效。

   Connect the keyboard by USB and select wired mode. Follow the Input Monitoring and Accessibility prompts. The app may automatically close and reopen once to apply newly granted permissions.

3. 软件会自动检查更新，也可打开 **设置 → 关于与更新 → 检查更新**。旧 1.1.x 用户需先手动安装一次新版。

   The app checks for updates automatically. You can also use **Settings → About & updates → Check for Updates**. Users on 1.1.x need to install the current version once manually.

灯效需要 USB 连接；AIR75 V3 另支持蓝牙快捷控制。需要更新键盘固件时，请按软件指引前往 NuPhyIO。

Lighting requires USB. AIR75 V3 also supports Bluetooth shortcut control. Follow the app's NuPhyIO guidance if a firmware update is needed.

## Codex 默认命令键 / Default Codex command keys

在 AI 助手中开启 Codex 模式后使用。/ Enable Codex mode in AI Assistant to use these defaults.

| 按键 / Key | 功能 | Action |
| --- | --- | --- |
| F7 | 普通 / 极速 | Standard / Fast |
| F8 | 批准一次 | Allow once |
| F9 | 拒绝 | Deny |
| F10 | 新聊天 | New chat |
| F11 | 按住听写，松开结束 | Hold to dictate, release to finish |
| F12 | 发送 | Send |

批准与拒绝需要当前存在审批请求；发送时需聚焦聊天输入框。

Approval commands require a current request. Sending requires the chat composer to be focused.

## 功能 / Features

- 逐键 RGB 绘图、动画与本地作品库。/ Per-key RGB painting, animation and a local artwork library.
- 按键触发、键盘游戏和声音律动。/ Key-triggered effects, keyboard games and audio-reactive lighting.
- Codex / Claude Code 任务快捷键和状态灯。/ Codex / Claude Code task shortcuts and status lights.
- USB 自动识别键盘型号，各型号的作品分别保存。/ Automatic USB model detection, with separate artwork for each keyboard model.

## 文档与源码 / Documentation and source

- [中文安装、使用与开发指南](README.zh-CN.md) · [English installation, usage and development guide](README.en.md)
- [文档目录 / Documentation index](docs/README.md)
- [发布流程（中文）](docs/RELEASING.md) · [Release workflow (English)](docs/RELEASING.en.md)
- [第三方声明 / Third-party notices](THIRD_PARTY_NOTICES.md)
- [问题反馈 / Report an issue](https://github.com/bohu8264/NuPhyLab-next/issues)

本仓库维护当前版本。[市场分享页](https://github.com/NuPhyLab/Air75-V3-RGB-Lab)继续作为固定入口；其中的早期 AIR 专用源码属于历史资料。需要与某个安装包一致的源码时，请使用对应发行页的 **Source code**。

This repository maintains the current app. The [marketing page](https://github.com/NuPhyLab/Air75-V3-RGB-Lab) remains a permanent entry point; its early AIR-only source is historical. For source matching an installer, use **Source code** on that release's page.
