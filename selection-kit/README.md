# Chord → NuPhyLab 单次框选 AI 源码

交付日期：2026-11-04。给 Lab 接入的独立源码包，最低 macOS 14；不包含成品 UI，也没有修改 Lab 项目。

本包实现一次选中文字／屏幕区域后，进行翻译、总结、改写、解释、OCR 文字提取或自由提问。支持按住时口述要求，等待松开、截图和语音结束后再发送；也可以不说话，松开后选动作或输入问题。

**不包含保存多份材料后一起提问的功能。** 没有收集键、材料队列、收集面板、批量问答、跨次历史、数据库或截图持久化。每次新手势替换上一份选区；每个请求最多一张图片。也不包含 Chord 的旧界面、更新器、规则／宏、图文备注导出或自动执行电脑操作。

## 从这里开始

- [现有功能与交付范围](Docs/现有功能与交付范围.md)：现在如何使用、哪些内容发给 AI、已有能力与这次新适配的区别。
- [Lab 接入指南](Docs/Lab接入指南.md)：模块接口、手势事件、权限、Keychain、取消及模型配置。
- [API 调研与接入建议](Docs/API调研与接入建议.md)：10 个服务／区域预设、自定义端点和官方资料。
- [验证记录](VALIDATION.md)：本次实际执行结果，以及仍需 Lab 验证的部分。

## 源码组成

| 目录 | 内容 |
| --- | --- |
| `NativeKit/` | 标准键鼠输入、单次选区、Accessibility 文字读取、ScreenCaptureKit 截图、Vision OCR、本地系统语音、网络图片缩放 |
| `AIKit/` | Responses、Chat Completions、Anthropic Messages；请求校验、流式解析、取消与部分模型目录 |
| `FlowKit/` | 单次会话、固定动作、语音／截图等待、发送防重、失效回调隔离 |
| `HostExample/` | 可编译的无 UI 接线示例 `SingleSelectionFeature`，把前三者连接起来 |

这些是从 Chord 当前工作树提取、裁剪并扩展的模块，不是完整 Chord 应用的原样复制。来源及改动说明见各模块的 provenance JSON。FlowKit 和 HostExample 是本次为独立接入新写的协调层；原 Chord 业务源码保持不变。

## 构建与校验

保持四个目录相邻，在包根目录执行：

```sh
python3 verify_manifest.py
xcrun swift build --package-path HostExample --scratch-path /tmp/lab-selection-host-build
bash AIKit/Validation/run.sh
xcrun swift run --package-path NativeKit --scratch-path /tmp/lab-selection-native-build LabSelectionNativeValidation
xcrun swift run --package-path FlowKit --scratch-path /tmp/lab-selection-flow-build FlowChecks
```

不需要第三方 Swift 依赖。SwiftPM 清单为 tools 5.9、Swift 5 语言模式；**本次编译环境为 Swift 6.3.3 和 macOS 26 SDK**，新版系统语音代码需要相应 SDK。macOS 14 是运行部署下限，不代表旧版 Xcode 已验证可构建。

协议适配和本地检查已完成；真实 API 账号、海外网络、实体键鼠、真人语音及 Lab 内部运行仍待接入后验收。配置必须使用用户自己的服务端点、模型 ID 和 API key；包内没有密钥，也没有读取任何用户 Keychain。
