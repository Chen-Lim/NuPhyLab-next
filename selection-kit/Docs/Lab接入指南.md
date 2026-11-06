# Lab 接入指南

## 1. 接入模块

将 `AIKit`、`NativeKit`、`FlowKit`、`HostExample` 保持相邻。Lab 可先把 `HostExample` 加为本地 Swift Package，使用产品 `LabSelectionHostExample`；它依赖另外三个库。验证整个依赖图：

```sh
xcrun swift build --package-path HostExample --scratch-path /tmp/lab-selection-host-build
```

如 Lab 已有输入与窗口基础设施，也可直接依赖三个底层产品 `LabSelectionNative`、`LabSelectionFlow`、`LabSelectionAI`，照着 HostExample 连接。不要把完整 Chord AppModel、Views 或 ChordCore 复制进 Lab；其中包含本次排除的功能和应用身份。

## 2. 唯一一份活动选区

`SingleSelectionFeature` 是可编译的接线示例，不创建窗口或监听键鼠。宿主按以下顺序调用：

| Lab 发生的事件 | 调用 |
| --- | --- |
| 用户开始按住 | `try feature.begin(listen: true/false, defaultAction: ...)`；必须在激活 Lab 选区界面之前调用，以保留原前台应用 |
| 拖动中 | 仅更新 Lab 的选区边框，不调用捕获或网络 |
| 松开并确定矩形 | `feature.release(selection: .region(bounds, excludingWindowIDs: ...))` |
| 松开并确定点中对象 | `.accessibilityPoint(point)` |
| 使用原应用已选中文字 | `.selectedText` |
| 用户点击动作 | `feature.choose(.translate(targetLanguage: "English"))` 或 `.summarize/.rewrite/.explain/.extractText` |
| 用户输入自由问题 | `feature.choose(.ask(instruction: question))` |
| Esc／关闭／暂停／锁屏／睡眠／显示器变化／监听失败 | `feature.cancel()`，同时撤销宿主自己的手势和选区界面 |
| 权限或安全输入变化 | `feature.safetyDidChange()`；暂停还应设置 `feature.paused = true` |

`onChange` 通知宿主读取 `session.phase`、`session.preview`、`session.result` 和 `error`。`onTranscript` 用于显示实时识别文字，**不能**把每次识别更新当作发送事件。`onRecordingChanged` 用于明确显示麦克风状态。`voiceIssue` 是原生语音失败原因，最终用户文案由 Lab 本地化。

直接使用 NativeKit 时，`onResolved(.partial)` 既可能表示正常收尾超时，也可能伴随识别失败；只有 `voice.phase == .ready` 才可按正常终态处理。失败调用 FlowKit 的 `voiceFailed(for:)`，让选区等待明确动作，不能把失败片段自动送出。HostExample 已处理这个区别，也会在同步状态回调后重新检查当前手势，避免取消后重新开麦。

矩形和点使用 **Quartz 全局屏幕点坐标**，主显示器左上为原点。SwiftUI/AppKit 的坐标必须正确转换；多屏可能有负坐标。不能只把 `NSEvent.mouseLocation` 的 y 直接当 Quartz y。截图需完整位于一个显示器，`excludingWindowIDs` 传 Lab 选区边框等窗口 ID；服务同时排除当前进程窗口。

示例中的窗口、设置、API key 读取仍由 Lab 提供。不要在应用启动时调用 `begin(listen:true)`；语音和屏幕内容只由明确手势触发。

## 3. 按键／侧键接入

若 Lab 已有全局输入路由，复用它，并将按下、移动、松开和取消接到上述接口。不要为同一绑定再装第二个 event tap。

如果没有现成输入层，NativeKit 提供 `SelectionHoldMonitor`：

```swift
let monitor = SelectionHoldMonitor()
monitor.onEvent = { event in
    switch event.edge {
    case .began: /* 建立新手势，记录 event.token */ break
    case .moved: /* 仅更新同 token 的框选预览 */ break
    case .released: /* 对同 token 确定最终选区并调用 release */ break
    case .cancelled: /* 取消同 token 的手势 */ break
    }
}
monitor.onCancel = { feature.cancel() }
monitor.onFailure = { _ in feature.cancel() }
try monitor.start(binding: chosenBinding)
```

上例中的 `chosenBinding`、`feature` 与注释中的 UI 路由由 Lab 实现；这是接线片段。鼠标侧键按住拖动可配合 `IntentSideSelectionState` 计算区域；键盘按住后的左键框选由宿主 overlay 负责。不要把鼠标移动监听当作持续截图。

绑定先经过 `InputBindingPolicy`，不占用普通打字、安全键、系统保留组合或鼠标主键。普通输入在故障时放行；已经消费的 down/up 需成对结束。`monitor.stop()` 后若 `isDrainingInput` 为 true，应继续持有该 monitor，直到已拥有的物理释放排空，不能立即销毁；不会继续产生新的业务手势。退出、暂停和重新配置要同时使会话失效。

## 4. 服务配置与密钥

宿主给 `SingleSelectionFeature` 提供异步 `context` 闭包，每次实际 AI 请求才读取选定的配置及对应 key：

```swift
let feature = SingleSelectionFeature(voiceLocaleIdentifier: userSpeechLocale) {
    let configuration = selectedAIConfiguration
    let account = try configuration.credentialAccount()
    let apiKey = try await labKeychain.read(account: account)
    return SelectionRequestContext(
        configuration: configuration,
        apiKey: apiKey,
        outputLanguage: userAnswerLanguage,
        translationTargetLanguage: userTranslationTarget
    )
}
```

这是宿主接口示意，`labKeychain` 和用户设置是 Lab 自己的类型。需要 `import LabSelectionHostExample`、`LabSelectionAI`、`LabSelectionFlow`。key 只能存 Lab 自己的 Keychain service，不能用 Chord 的 bundle ID、service 或已有凭据。

`AIConfiguration` 保存服务、协议、**完整请求 URL**、模型、输出长度、图片能力及可选 Anthropic workspace。`credentialAccount()` 将服务／协议／端点／workspace 绑定，换域名或区域时不自动沿用旧 key。不要将 API key 放入 UserDefaults、工程配置、请求日志或错误文本。

`imageInputConfirmed` 默认 false；Lab 应按官方资料及所选模型能力赋值，不用模型名包含某字符串的猜测。它是能力配置，不要求每次发送额外弹窗。没有可用图片能力时用户可明确选 OCR 文字操作；不要静默丢图、自动换服务或重试收费请求。

`AIClient.listModels` 提供部分官方目录及 Anthropic 游标；Qwen 目录 schema 本次未实现，手填模型 ID。模型列表不等于调用权限。详细端点、区域、鉴权与订阅差异见 [API 调研](API调研与接入建议.md)。

## 5. 权限与生命周期

| 系统能力 | 用途／宿主责任 |
| --- | --- |
| Accessibility | 明确对象／选中文字读取，以及绑定输入的安全检查 |
| Input Monitoring | 全局按住手势；当前示例也把它作为发送前置条件 |
| Screen Recording | 明确框选截图；AX 文字流程不要求此权限 |
| Microphone + Speech Recognition | 仅使用语音时需要；应用 Info.plist 配置 `NSMicrophoneUsageDescription`、`NSSpeechRecognitionUsageDescription` |

`SelectionPermissions.current()` 只检查状态，不请求权限。Lab 自己的权限引导按需请求。语音 `start` 可触发用户请求所需的系统授权；不在验证程序中启动它。若 Lab 启用 App Sandbox，需按其现有签名方式配置出站网络、音频输入等 entitlement 并实测；本包不是签名应用，不替 Lab 改这些配置。

按住监控有安全输入和系统状态观察；宿主仍须在关闭、暂停、锁屏、睡眠、屏幕变化和权限撤销时取消完整 feature。只停止 HTTP 不足以结束录音和截图，直接用 HostExample 的 `cancel()` 可一并停止本模块效果。Lab 自己的监听与 overlay 也要取消；恢复权限不恢复已取消的旧手势。

FlowKit 用会话 UUID 和请求 UUID 隔离迟到的截图、语音、流和最终结果。发送前等待 capture＋语音终态＋release；提交前标记 requesting 防重；加载 key 后复查安全状态；新会话、撤权和取消都会使旧回调失效。`extractText` 直接走本地路径，不触发 context 闭包。

## 6. Lab 验收建议

先在完整 Xcode 环境构建并运行各模块检查，再验真实链路：选中文字、纯文字截图、照片／图表、中文和英文口述、未说话、无默认动作、快速取消及重新选择、锁屏／撤权／更换显示器。覆盖普通输入放行和按键成对释放；不能因已跑纯状态检查就宣称实体设备通过。

用目标地区自己的 API 账号验文字、视觉、流式和取消，并检查 401／403／429、超时、拒绝、截断、断流；验证端点更换后密钥隔离。macOS 14/Intel、目标沙盒及签名环境需单独实测。本次没有发布可安装应用，也没有对 Lab UI、API 账单或真实账号作已验证承诺。
