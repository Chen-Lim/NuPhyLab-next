# NuPhy Lab 1.2.39

## 更新内容

- 改进 Codex 命令键的界面识别和首次使用体验。
- 默认分配：F7 普通／极速、F8 批准一次、F9 拒绝、F10 新聊天、F11 按住听写、F12 发送。
- 修正系统已授权但软件仍显示未授权的问题；必要时安全恢复键盘，并自动重新打开 NuPhy Lab 一次以应用新权限。
- 保留 Air75 V3 连接动画以及原有作品、草稿和设置。

首次授权时可能看到软件自动关闭后重新打开，这是权限生效流程。批准、拒绝需要当前存在审批请求；发送需聚焦聊天输入框。

适用于 Apple Silicon，macOS 13.5 及以上。

## Changes

- Improve Codex control discovery and first-use behavior.
- Defaults: F7 standard/fast, F8 allow once, F9 deny, F10 new chat, F11 hold to dictate, and F12 send.
- Recover from stale permission state. When needed, safely restore the keyboard and automatically reopen NuPhy Lab once to apply newly granted permissions.
- Preserve the Air75 V3 connection animation and existing artwork, drafts and settings.

A brief automatic close and reopen during first authorization is expected. Approval commands require a current request; sending requires the chat composer to be focused.

For Apple Silicon on macOS 13.5 or later.

## Verification

This release reuses the exact signed and notarized 1.2.39 R2 package tested locally. Both app and DMG passed Apple notarization and were stapled. The R1 frozen source passed 904 regressions and 6679 native offline checks; R2 adds fixed permission-result logging and passed 3 native host checks and 54 packaged-runtime checks. These counts are separate validation scopes.

Physical F7 switching and F11 hold/release dictation, clean exit, data retention and Accessibility grant automatic recovery were confirmed on the test Mac. Independent-Mac acceptance, minimum-OS/two-keyboard coverage, a complete signed update installation, action-specific F8/F9/F12 verification and rotary/shared-media-key independence remain unverified. Publication does not change those test results.

The app's embedded release notes retain their original candidate wording so the tested, signed package remains byte-for-byte identical.
