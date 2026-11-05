# NuPhy Lab — English guide

[中文 / English home](README.md) · [简体中文指南](README.zh-CN.md)

NuPhy Lab is a macOS lighting studio for **NuPhy AIR75 V3 and Kick75 (ANSI)**. Connect a keyboard by USB to detect the model automatically. Artwork stays separate for each model.

It includes drawing, animation, key-triggered effects, games, audio-reactive lighting, a local artwork library, and Codex / Claude Code task shortcuts and status lights.

## Download and install

**[Download the latest macOS installer](https://github.com/bohu8264/NuPhyLab-next/releases/latest/download/NuPhyLab-macOS-AppleSilicon.dmg)**

Requires **Apple Silicon and macOS 13.5 or later**. The DMG is signed with NuPhy's Developer ID and notarized by Apple.

[Latest release and notes](https://github.com/bohu8264/NuPhyLab-next/releases/latest) · [Previous versions](https://github.com/bohu8264/NuPhyLab-next/releases)

1. Quit the old NuPhy Lab app before installing.
2. Open the DMG and drag **NuPhy Lab** to Applications. Replace the existing app if prompted, and keep one installed copy. Keep the app-data folder to retain your artwork, drafts and settings.
3. Connect the keyboard with a USB data cable and select wired mode. Follow the app's permission and firmware guidance.

Allow Input Monitoring and Accessibility when prompted. The app may automatically close and reopen once to apply newly granted permissions. Audio permissions are requested when using audio-reactive lighting.

If the keyboard needs a firmware update, follow the NuPhyIO reminder, close the website after upgrading, then return to NuPhy Lab.

## AI Assistant

Enable Codex mode in AI Assistant to use the default command keys:

| Key | Action |
| --- | --- |
| F7 | Switch between Standard and Fast |
| F8 | Allow the current approval request once |
| F9 | Deny the current approval request |
| F10 | Open a new chat |
| F11 | Hold to dictate; release to finish |
| F12 | Send from the focused chat composer |

F8 and F9 require a current approval request. F12 requires the chat composer to be focused. Command assignments can be changed in AI Assistant.

## Updates and compatibility

NuPhy Lab includes signed in-app updates. It checks for new releases automatically, or you can choose **Check for Updates** in the application menu or **Settings → About & updates**. Artwork, drafts and settings are retained. Users on 1.1.x need to install the current app once manually.

Lighting requires USB. AIR75 V3 also supports Bluetooth shortcut control. The current keyboard layouts are ANSI.

Diagnostics stay on the Mac. Update checks do not upload task contents, artwork or keyboard input.

## Source and development

[Source code](https://github.com/bohu8264/NuPhyLab-next/tree/main) · [Releases](https://github.com/bohu8264/NuPhyLab-next/releases)

Building requires macOS, Xcode command line tools and Node.js 22 or newer.

```sh
npm run setup
npm run build
npm test
npm start
```

Before `npm start`, quit the installed NuPhy Lab app and other keyboard control software. The source server uses live local data and may automatically connect a keyboard; automated regression tests use isolated fixtures.

The native build downloads a pinned, checksum-verified Sparkle framework. Run `npm run fetch-node` to fetch the standalone runtime, then `npm run package`. Follow the [release workflow](docs/RELEASING.en.md) for distribution signing, notarization and update verification.

[Documentation index](docs/README.md) · [Third-party notices](THIRD_PARTY_NOTICES.md) · [Report an issue](https://github.com/bohu8264/NuPhyLab-next/issues)
