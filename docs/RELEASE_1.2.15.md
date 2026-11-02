# NuPhy Lab 1.2.15

## 更新内容

- 修正软件更新窗口比例与排版：提示随内容收紧，按钮置于右下角，更新说明可独立滚动。
- 合并“关于”和“更新”为“关于与更新”，集中显示版本、软件与固件更新、帮助、许可和诊断。
- 保留旧更新入口及固件提示的跳转，兼容中英文界面。

适用于 Apple Silicon，macOS 13.5 及以上。作品、草稿及设置沿用原有数据。

## Changes

- Size software update prompts to their content, align actions at the lower right, and keep release notes independently scrollable.
- Combine About and Updates in Settings into About & updates, including version, software and firmware updates, help, licenses and diagnostics.
- Preserve existing update links and firmware notifications in both interface languages.

For Apple Silicon on macOS 13.5 or later. Existing artwork, drafts and settings remain compatible.

## Verification scope

- 875 regression tests passed, with no failures or skipped tests. All 299 test and production input fingerprints remained unchanged.
- 6679 native offline self-test checks passed without opening physical HID devices or input monitoring.
- Actual AppKit geometry checks cover Chinese and English prompts, compact states, independently scrollable long notes, lower-right actions and shrinking after notes are hidden.
- The merged Settings page was inspected in both languages at 1080 × 720 and 720 × 640. Legacy update navigation, firmware notification clearing and Help remain covered by regression tests.
- These tests use isolated data and simulated keyboards. They do not certify physical typing, long idle intervals or new hardware/firmware combinations.

The app and final DMG are company Developer ID signed, Apple notarization Accepted and stapled. Strict signatures, Gatekeeper assessments with assessments enabled, and syspolicy distribution checks passed. The mounted final package also passed all 6679 native offline self-test checks, and 80 packaged runtime source files match the release worktree. See [package verification](RELEASE_1.2.15_VERIFICATION.json) for SHA-256 and exact scope. Public download verification is the remaining publication step. A live 1.2.14 → 1.2.15 installation check has not been performed; the release Mac is left on its existing version.
