# NuPhy Lab — 中文指南

[中文 / English 首页](README.md) · [English guide](README.en.md)

NuPhy Lab 是适用于 macOS 的 **NuPhy AIR75 V3 / Kick75（ANSI）** 灯光创作软件。USB 插入后自动识别型号，作品按键盘分别保存。

提供绘图、动画、按键触发、游戏、声音律动、作品库，以及 Codex / Claude Code 任务快捷键和状态灯。

## 下载与安装

**[直接下载最新版 Mac 安装包](https://github.com/bohu8264/NuPhyLab-next/releases/latest/download/NuPhyLab-macOS-AppleSilicon.dmg)**

适用于 **Apple Silicon 和 macOS 13.5 及以上版本**。安装包使用 NuPhy 公司 Developer ID 签名并经过 Apple 公证。后续正式版继续使用同一下载地址。

[最新版本与验证范围](https://github.com/bohu8264/NuPhyLab-next/releases/latest) · [历史版本](https://github.com/bohu8264/NuPhyLab-next/releases)

1. 安装前先退出旧版 NuPhy Lab。
2. 打开 DMG，将 **NuPhy Lab** 拖入「应用程序」。如提示则替换旧应用，只保留一个已安装副本。保留本机应用数据，继续使用原有作品、草稿和设置。
3. 用 USB 数据线连接键盘并切到有线模式，按软件提示完成授权和固件检查。

首次使用按提示授予输入监控和辅助功能权限。软件可能自动关闭并重新打开一次，使新权限生效。声音权限在实际启用声音律动时请求。

需要更新键盘固件时，请按 NuPhyIO 提示操作；升级完成后关闭官网页面，再回到 NuPhy Lab。

## AI 助手

在 AI 助手中开启 Codex 模式后，默认命令键如下：

| 按键 | 功能 |
| --- | --- |
| F7 | 切换普通 / 极速模式 |
| F8 | 批准当前请求一次 |
| F9 | 拒绝当前请求 |
| F10 | 新建聊天 |
| F11 | 按住听写，松开结束 |
| F12 | 发送聊天输入框中的内容 |

F8、F9 需要当前存在审批请求；F12 需要聚焦聊天输入框。命令键分配可在 AI 助手中修改。

## 更新与兼容

应用内置签名更新，会自动检查新版；也可在应用菜单或 **设置 → 关于与更新** 点击 **检查更新**。安装会保留作品、草稿和设置。旧 1.1.x 用户需要先手动安装一次当前最新版。

灯效需要 USB 连接；AIR75 V3 蓝牙另支持快捷键控制。当前键盘布局为 ANSI。

原有本机数据目录和 bundle ID 保持兼容。诊断记录仅保存在本机；更新检查不上传任务内容、作品或键盘输入。固件必须通过型号、几何结构、灯位数量、会话和读回验证才能启用写入。

## 源码与开发

[当前维护的源码](https://github.com/bohu8264/NuPhyLab-next/tree/main)。需要与某个安装包一致的源码时，请使用对应发行页的 **Source code**。[市场入口仓库](https://github.com/NuPhyLab/Air75-V3-RGB-Lab)中的早期 AIR 专用源码为历史资料。

需要 macOS、Xcode 命令行工具和 Node.js 22 以上版本。

```sh
npm run setup
npm run build
npm test
npm start
```

运行 `npm start` 前先正常退出已安装的 NuPhy Lab 和其他键盘控制程序。源码服务读取真实本机数据，并可能自动连接键盘；自动回归使用隔离数据。

原生构建会下载固定版本的 Sparkle，并验证 SHA-256。运行 `npm run fetch-node` 获取独立运行时，再使用 `npm run package` 打包。对外发布请遵循[发布流程](docs/RELEASING.md)，包括签名、公证、安装包及应用内更新验证。

[文档目录](docs/README.md) · [第三方声明](THIRD_PARTY_NOTICES.md) · [问题反馈](https://github.com/bohu8264/NuPhyLab-next/issues)
