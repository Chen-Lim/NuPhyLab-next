# 框选提问 / Ask about a selection

使用快捷键框选屏幕上的内容，让你选择的模型翻译、总结或回答问题。本功能需要 **macOS 14 或更新版本**；原有键盘功能仍支持 macOS 13.5。

Select a region of the screen with a shortcut and ask your chosen model to translate, summarize or answer a question. Selection requires **macOS 14 or later**; keyboard features still support macOS 13.5.

## 首次设置 / First setup

1. 在 **设置 → 模型与 API** 选择服务、模型，填写并保存自己的 API Key。可使用服务预设，读取受支持服务的账户模型列表，或填写模型 ID 和兼容端点。
2. 打开 **实验室 → 框选提问** 并开启功能，按提示为 **NuPhy Lab** 授予辅助功能、输入监控和屏幕录制。返回软件后会重新检查；若系统要求重新打开，可使用界面中的重开按钮。
3. 默认快捷键为 **⌥ ⇧ Q**，可录制其他单键或组合。与 AI 模式占用的按键发生冲突时，换用其他快捷键即可。
4. 按住快捷键拖动框选，松开后执行默认动作。框选时可滚轮切换翻译、总结和解释；回答浮窗中可继续提问。

1. Choose a service and model in **Settings → Models & API**, then save your own API key. Use presets, load account models where supported, or enter a custom model ID and compatible endpoint.
2. Enable **Labs → Ask about a selection** and grant **NuPhy Lab** Accessibility, Input Monitoring and Screen Recording access. The app rechecks access when you return. Use the reopen button if macOS requires it.
3. The default shortcut is **Option–Shift–Q**. You can record another key or combination. Choose another shortcut if it conflicts with an active AI keyboard binding.
4. Hold the shortcut, drag over a region, and release to run the default action. Scroll during selection to switch between translation, summary and explanation. Ask follow-up questions in the answer panel.

## 翻译语言与界面 / Translation and interface languages

“翻译为”提供 16 种目标语言，回答浮窗中也可调整并重新翻译。选择会保存，且独立于中英文界面设置。内置作品名、实验室和框选操作文字随界面语言变化；自定义作品名和模型回答保留原文。

**Translate to** offers 16 target languages. You can also change the target in a translation answer to translate again. The choice is saved independently of the interface language. Built-in artwork titles, Labs and selection controls follow the interface language; custom artwork titles and model answers retain their original text.

[完整语言列表与规则 / Language list and behavior](SELECTION_LANGUAGES.md)

## 语音与图片 / Voice and images

新用户默认关闭框选与语音。开启“按住说话”后，允许麦克风和语音识别，即可在保持快捷键按住时口述问题。语音在本机转写，录音不上传；关闭语音仍可使用文字功能。框选不需要系统声音权限。

Selection and voice start disabled for new users. Enable **Hold to speak** and grant Microphone and Speech Recognition access to dictate a question while holding the shortcut. Speech is transcribed locally; recordings are not uploaded. Text features work with voice off. Selection does not require System Audio access.

“发送图片”位于“按住说话”下方。关闭时只发送本机识别到的文字；开启后，提问可附带选区图片，翻译、总结和解释在没有识别到文字时可附图。“提取文字”只在本机执行。图片输入需要所选模型和接口支持，开启开关并不会使纯文字模型具备看图能力。

The image switch sits below **Hold to speak**. When off, only locally recognized text is sent. When on, questions can include the selected image; translation, summary and explanation may include an image when no text was recognized. Extract Text runs locally. The selected model and endpoint must support images; enabling the switch does not add vision support to a text-only model.

## 数据与权限 / Data and permissions

提交后，选区文字、问题及已启用且本次操作需要的图片会发送至你配置的模型服务。API Key 保存在本机钥匙串，不包含在安装包或作品中。

After submission, selected text, questions and any enabled images needed for the selected action are sent to your configured model service. API keys are stored in the local Keychain, outside installers and artwork files.

软件会分别检查配置、权限、快捷键冲突及实际监听状态。如果仍未就绪，按页面显示处理对应项目，再重新检查。系统要求重开时，仍需完成该步骤。

The app checks configuration, permissions, shortcut conflicts and the actual listener separately. If it is not ready, address the item shown on the page and recheck. If macOS requires reopening the app, that step still needs to be completed.

[模型、图片和权限详情 / Models, images and permissions](SELECTION_R2.md) · [返回首页 / Home](../README.md)
