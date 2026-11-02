# NuPhy Lab 1.2.14

NuPhy Lab for macOS 13.5 and later on Apple Silicon, with NuPhy Air75 V3 and Kick75 ANSI support qualified by model and firmware.

## Changes

- Add One stone, two birds: each keystroke sends a cross from its key, with overlapping waves, adjustable colour and speed.
- Play artworks directly from the Library. Open edit enters the matching Studio mode and protects unsaved drafts.
- Keep the original lighting duration deadline after idle activity. On supported Air75 V3 keyboards, temporarily manage device sleep during Lab lighting and restore it afterwards.
- Complete the English interface while preserving user-entered artwork and task names.
- Add Settings update controls and a dot for firmware updates verified for the connected keyboard. Open firmware settings directly in NuPhyIO.
- Show version-specific release notes and update controls in the application language. Later pauses automatic reminders for the same version for at least 24 hours.

The release also includes the white Air75 V3 USB wake animation and the curated artwork library from the intervening local development versions.

## Verification scope

- 873 automated regression tests passed, with no failures or skipped tests.
- 6679 native offline self-test checks passed, without opening physical HID devices or input monitoring.
- Source inputs remained unchanged during the regression run.
- Continuous physical typing and long idle observation remain separate from these isolated checks. The previously reported premature lighting shutdown has not been reproduced.
- Hardware capabilities remain firmware-specific. Kick75 per-key support on 4.0.18.6 and legacy PID 0x1027 are not certified here as new physical acceptance results.

The app and DMG are company Developer ID signed, Apple notarization Accepted, and stapled. Strict signatures, Gatekeeper assessments with assessments enabled, and syspolicy distribution checks passed. The final mounted package passed the 6679-check offline native self-test. See [package verification](RELEASE_1.2.14_VERIFICATION.json) for its SHA-256 and exact scope. Both the versioned and fixed Latest public downloads were downloaded and verified byte-for-byte against the final package. Live in-app installation verification is recorded after the production feed becomes available.
