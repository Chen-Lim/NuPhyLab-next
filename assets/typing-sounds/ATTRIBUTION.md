# 模拟声浪 R3 · 音源来源 / Audio credits

## 调校音色 / Tuned sound designs

12 个调校音色以三段 CC0 1.0 公开键盘录音为基础。它们是声音设计，不是12种新轴体实录；“木质”“绒面”等描述调校听感，不代表录音包含相应材质。

Twelve tuned profiles derive from three CC0 recordings. They are designed timbres, not recordings of twelve new switch models. Woody and felted describe acoustic design, not the material of the recorded keyboard.

| 音色组 / Family | 原作者与录音 / Recording | 使用方式 / Use |
|---|---|---|
| 麻将、奶油 / Marbly, creamy | [Typing on a rainy 75 — Techrul](https://freesound.org/people/Techrul/sounds/815614/) | 重新切片、碰撞及腔体调校 / sliced and tuned |
| 木质 / Woody | [Modified Technics keyboard — zrrion](https://freesound.org/people/zrrion/sounds/665075/) | 改装 Gateron 黄轴录音，短尾木质风格 / short woody designs from modified Gateron Yellow recording |
| 轻柔 / Soft | [HHKB Professional Hybrid / Topre — grcekh](https://freesound.org/people/grcekh/sounds/546033/) | 柔化接触、阻尼与回弹设计 / softened contact and damping |

[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) applies to all three sources and the derived WAV assets. Only the freely accessible HQ previews were used; no login-only original was downloaded and no commercial app's derived sound pack was copied.

Each source contributes eight distinct stronger contacts and four lighter contacts. Individual keys and release events were not labeled by the recordists. Large-key and release variants are modeled and disclosed as tuned. 原录音均未标注具体按键/松键时点，大键与回弹不声称对应键位的原始录音。

| Source | Public preview SHA-256 |
|---|---|
| Techrul / 815614 | `c426ec057d1d2e52dd6cb97cf12269c9c5c76bc32eab003fe9fd3741737f13b0` |
| zrrion / 665075 | `0f70bd54f17941eeb8f2d7cb5b1d1b362c55f25322e0421448a9d04d072e5a16` |
| grcekh / 546033 | `a4cffe3b457f69b645b32da45e21dc6e83d8c520f4a27fd85618981e734297f3` |

## 经典采样 / Classic recordings

Holy Panda, Cherry MX Brown, Topre, Kailh Box Navy, SKCM Blue Alps and Buckling Spring are from **Thomas Lai / [tplai/kbsim](https://github.com/tplai/kbsim)**, pinned commit `ba103f3b0afa9dab80447aa2e7e2ed80b6bd80e4`. Original paths: `src/assets/audio/<pack>/press|release/*.mp3`.

The 72 active MP3 files are unmodified and distributed under the original MIT notice in `audio/KBSIM_LICENSE.txt`. Each active pack contains five distinct regular press recordings, plus separate Space, Return and Backspace press/release samples. Shift, Tab and Caps use the prototype's disclosed modeling. Names identify the upstream audio; they are not official NuPhy recordings or endorsements.

仅收录以上6套经典音源；R1/R2其余经典音源不在本轮播放或嵌入清单中。品牌名称用于识别上游录音，不代表NuPhy官方实录或代言。

## Rebuild

`tools/build-custom-sounds.py INPUT_RAINY_48K_MONO.wav --technics INPUT_TECHNICS.wav --hhkb INPUT_HHKB.wav` requires numpy and scipy. Exact cuts and parameters: `audio/CUSTOM_MANIFEST.json`.

`tools/export-catalog.mjs` writes the active catalog. The standalone build embeds only that catalog's assets. `tools/render-auditions.py` renders all 18 styles and six category previews using macOS afconvert for classic MP3 decoding. No recording, system keyboard capture or private user data is used.
