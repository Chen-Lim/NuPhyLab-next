# Keyboard compatibility / 键盘兼容性

NuPhy Lab 1.2.40 adds the following ANSI USB profiles. Use a USB data cable and select wired mode. Keep other keyboard control software closed while NuPhy Lab controls the keyboard.

NuPhy Lab 1.2.40 新增以下 ANSI 布局的 USB 适配。请使用数据线并选择有线档位；Lab 控制键盘时，请关闭其他键盘控制软件。

| Model / 型号 | Qualified firmware / 已适配固件 | Per-key LEDs / 按键灯位 | Function row / F 区 |
| --- | --- | --- | --- |
| AIR75 V3 | 1.0.23.6 | 84 | F1–F12 |
| Kick75 | 4.0.18.6 | 80 | F1–F12 |
| NODE75 LP | 1.0.10.6 | 84 | F1–F12 |
| NODE75 HP | 1.0.10.6 | 82 | F1–F12 |
| NODE100 LP | 1.0.7.6 | 103 | F1–F12 |
| NODE100 HP | 1.0.7.6 | 109 | F1–F12 |
| AIR65 V3 | 1.0.5.6 | 68 | No physical F row / 无实体 F 区 |
| AIR100 V3 | 1.0.6.6 | 99 | F1–F12 |

Firmware versions were checked against [official NuPhyIO](https://drive.nuphy.io/) on November 5, 2026. For newly added models, an older or unrecognized newer firmware stays read-only until compatibility is confirmed. Follow the app's firmware guidance; do not choose a different model's firmware. Existing AIR75 V3 compatibility and Kick75 stock effects remain available where supported.

固件版本于 2026 年 11 月 5 日核对官方 NuPhyIO。新增型号遇到旧固件或尚未确认的新固件时保持只读；请按软件提示更新，勿安装其他型号固件。AIR75 V3 原有兼容范围及 Kick75 已支持的原生灯效保留。

All profiles include model-specific drawing, animation, game and audio canvases, plus the connection animation on compatible firmware. Artwork and drafts are separated by model. NODE's touch strip is not a paintable key; its indicator apertures show the side-light group together.

各型号提供对应的绘图、动画、游戏和声音律动画布，兼容固件可播放连接动画。作品和草稿按型号保存。NODE 触摸条不作为绘图按键；指示灯孔共同显示侧灯组颜色。

AIR65 V3 does not offer automatic F1–F12 takeover. Bluetooth shortcut support remains specific to AIR75 V3. NODE75 / NODE100 touch gestures are kept separate from AI function-key inputs; custom key assignments are preserved.

AIR65 V3 不提供 F1–F12 自动接管。蓝牙快捷控制目前仍仅适用于 AIR75 V3。NODE75 / NODE100 的触摸手势与 AI 功能键输入分开处理，保留自定义键位。

Physical verification for the newly added models currently covers NODE75 LP only. The other new profiles have source, protocol, simulated lifecycle and interface checks; they still require hardware verification. First-install permission behavior on another Mac and actual AI command effects must be checked separately.

新增型号的实体检查目前仅覆盖 NODE75 LP。其他新增型号已做源码、协议、模拟生命周期和界面检查，仍需实机验证。另一台 Mac 的首次安装授权流程，以及 AI 命令的实际效果，需要分别验收。
