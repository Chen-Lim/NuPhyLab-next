# LabSelectionNative

Chord 原生选择与本机语音能力的独立 SwiftPM 源码包。它为 Lab 提供单次按住、取文字/截取区域、OCR 和口述指令的底层接口；Lab 负责选框、状态反馈、动作选择、结果界面及最终请求编排。没有接入或修改 Lab 应用。

本包不含保存后集中提问、收集组、跨次选择库、双对象 A/B 比较、截图备注编辑器、常用动作/规则/宏、主设置页、品牌资产、更新器或模型密钥管理。所有 `Sources` 文件均参与编译，没有以未编译参考文件代替已实现能力。

## 构建与验证

最低运行系统 macOS 14，Swift 5 语言模式；构建需要带 macOS 26+ SDK 的工具链（代码保留生产版 macOS 26 SpeechAnalyzer 分支，以 `#available` 做运行时判断）。SwiftPM 不拉取第三方依赖，ObjC 的 `ChordAudioBoundary` 是原项目音频异常边界源码。

```sh
swift build --package-path . -c release --scratch-path /private/tmp/chord-lab-native-build
swift run --package-path . --scratch-path /private/tmp/chord-lab-native-build LabSelectionNativeValidation
# 安装完整 Xcode、可导入 XCTest 的环境中：
swift test --package-path . --scratch-path /private/tmp/chord-lab-native-build
```

2026-11-04 实际验证：Swift 6.3.3、macOS SDK 26.5（CLT）下 debug/release 源码均编译成功；独立 `LabSelectionNativeValidation` 可执行程序通过 69 项检查，包括输入归属/取消代际、Fn 与普通输入放行、坐标/像素限额、语音状态/启动取消/音频清理，以及合成高熵 PNG 的缩图/字节限制/原图不变。它是普通可执行验证程序，不是 XCTest 替身，也没有启动事件监听、权限弹窗、录音、真实截图或模型调用。

本机 `swift test` 实际失败于 `no such module 'XCTest'`，因此附带的 16 个 XCTest 方法未在本机执行，不能算作通过。Release 编译保留原 `VoiceAudioWorker` 在 Swift 5 模式下的一项并发告警：`@Sendable` 闭包捕获未声明 Sendable 的 worker；worker 的生产实现以串行队列与运行时 queue precondition 约束访问，未为消除告警贸然添加 `@unchecked Sendable`。本交付未验证 Swift 6 严格语言模式，也未做实际设备、TCC、跨屏、AV/Speech 或 Lab 运行验收。

## 公开入口

| 接口 | 输入和返回 | Lab 需要提供的工作 |
| --- | --- | --- |
| `SelectionHoldMonitor` | `start(binding:) throws`；`onEvent(IntentPressEvent)`、`onCancel`、`onFailure` | 明示触发键、处理 began/moved/released/cancelled，显示状态与选框 |
| `IntentInputBridge` / `IntentSideSelectionState` | 纯状态输入归属、代际 token、按住侧键移动得到 point/region | 已有统一设备路由时直接调用，避免为同一按键安装两个 tap |
| `SelectionCapture.selectedText(target:)` | `@MainActor`，目标 `NSRunningApplication?`，返回明确选中的字符串 | 先保留外部目标应用，别让选框焦点覆盖它 |
| `ScreenAwarenessService().snapshot(at:)` | actor，Quartz 屏幕点，返回单个 `IntentSelection` | 点选对象时调用；不支持的对象回退为用户框选 |
| `ScreenAwarenessService().regionContext(at:)` | actor，返回窗口/应用信息并检查受保护字段 | 需要在宿主 DTO 带应用出处时使用 |
| `RegionCaptureService.capture(_:excludingWindowIDs:preferredLanguages:)` | async，`IntentBounds` → PNG 原图 + OCR 文本 | 用户完成框选后调用；传宿主额外排除的窗口 ID |
| `ScreenshotNetworkImage.prepare(png:)` | sync throws，单张 PNG → 限额网络 PNG 副本 | 在 `Task.detached` 或工作队列运行；保留原始图片用于用户查看 |
| `LocalVoiceCapture` | `start(objectIDs:onPrepared:)` → UUID；`finish()` / `cancel()` | 明确录音反馈；松开 finish，等待同代际 resolved 后决定是否发送 |
| `SelectionPermissions.current()` | 只读 AX / 输入监控 / 屏幕录制 / Secure Input 状态 | 自己设计权限说明与明确请求入口 |

`IntentSelection` 仅描述当前一项内容：`id`、`kind`、应用/窗口/AX 角色、`name`、`text`、`bounds`、可选 `imagePNG`、`selectedAt`。没有对象组、标签 A/B、保存方法或持久化目录。

## 按住与选框衔接

键盘按住通常使用 `.fnGlobe`、`.modifierChord(...)` 或一个明确配置的 `.keyboard(keyCode:modifiers:)`；宿主选框层接收鼠标左键/触控板点击与拖选。本模块的 tap 不拦截左键、右键、滚轮或安全键。标准侧键使用 `.mouseButton(index: 3)` 等索引 3…31，收到 began 后以起点进入 `IntentSideSelectionState`，moved 更新矩形，released 完成；无需再按鼠标左键。

公开的 `IntentPressEvent` 带 `token`、`source`、`edge`、可选 `point`。`point` 与所有 `IntentBounds` 都是 Quartz 全局屏幕坐标，单位为点，主屏左上为原点、Y 向下。宿主用 AppKit 窗口/视图坐标绘制时需正确转换；不要直接把 AppKit 的底部原点坐标传给捕获。范围必须位于同一显示器；显示器配置变化、休眠/会话退出会取消当前选择。

`setEnabled(false)` 用于暂停或宿主快捷键录制。`stop()` 立即取消逻辑交付，并在仍有已消费的物理 down 时排空对应 up；`isDrainingInput == true` 期间保留 monitor 对象，避免销毁对象导致排空中断。结束或取消后使用生产状态机的 300ms 连续物理释放采样恢复孤立归属；采样缺失不会把仍活跃的按住动作当作松开。tap 超时或禁用会失败放行并报告，宿主提供恢复入口。系统 Fn 自带动作仍可能触发；厂商私有 Fn、DPI、灯效等没有统一支持承诺。

```swift
import LabSelectionNative

// 在 MainActor 持有整个应用生命周期内的 monitor。
let monitor = SelectionHoldMonitor()
monitor.onEvent = { event in
    // 宿主：根据 token 驱动单次交互与选框。
    // released 表示输入松开；语音未到正常终态、捕获未完成时不能抢先提交。
}
monitor.onCancel = { /* 取消捕获任务、语音和当前请求 */ }
try monitor.start(binding: .fnGlobe)
```

## 取字、截图与 OCR

AX 点选只访问用户指定对象，不递归遍历页面子树；文本编辑对象优先读取明确选择或当前可见范围，最多 20,000 字符。显式选中文本使用 AX API，不发 Command-C、不读写剪贴板。已知 AX 安全文本角色/父级（最多 12 层）和系统 Secure Input 会拒绝操作；这不是图片中所有敏感内容的自动识别或脱敏保证。

区域捕获采用 macOS 14 `SCScreenshotManager` 单帧接口，没有连续屏幕流，排除宿主自身所有窗口。默认也执行焦点/区域中心的受保护元数据检查，因此需要辅助功能和屏幕录制权限。最小区域 8×8 点，按显示器 backing scale 保留像素；单边不超过 8192 像素，总计不超过 32 MP。捕获/OCR 任务取消会阻止迟到结果进入后续交互。

OCR 在本地 Vision 执行。宿主可传 `preferredLanguages`，默认 `Locale.preferredLanguages`；只把当前系统 `supportedRecognitionLanguages()` 支持的标识传给 Vision，同时启用自动语言识别。语言覆盖随 macOS 与识别模型变化，不承诺任意语言。OCR 失败时返回有效截图和空文本，宿主仍可向支持图像的模型发送图片。

网络副本使用 ImageIO 按 2048/1600/1200/800 最大边尝试编码 PNG，限制为 3 MiB，不放大小图，也不修改源 `Data`。它只接收单帧 PNG，并检查 8192/32 MP 输入上限。原图保留在调用方内存；无文件保存行为。取消在 ImageIO 操作边界检查，无法强行中断已进入的系统解码调用。

## 本机语音

`LocalVoiceCapture(localeIdentifier: "en-US")` 可指定系统支持的 locale；`supportedLocaleIdentifiers` 是 Speech 语言清单，不等于当前设备已具备对应本机模型。`language` 仅控制内置中文/英文提示语，Lab 可以用状态字段自己显示其他语言 UI。

首次明确调用 `start` 可请求麦克风/语音权限，宿主应用必须带 `NSMicrophoneUsageDescription` 和 `NSSpeechRecognitionUsageDescription`；Hardened Runtime / Sandbox 的音频 entitlement 由 Lab 工程配置。本模块不代替宿主请求 AX、输入监控和录屏权限。

语音只读麦克风，最长 60 秒，不存音频、不用网络转写、不自动下载语音模型。macOS 26+ 尝试已安装的 SpeechTranscriber，否则使用要求 on-device 的 SFSpeechRecognizer；设备或语言不支持时给出不可用状态，让用户键入。音频引擎/监听安装与移除在生产串行 worker，保留启动取消、lease 代际隔离和 ObjC 异常边界。

`onPrepared` 必须先将返回 UUID 关联到当前单次交互；随后才能接收 started/result。`finish()` 停止输入并等待尾部转写，实际 final 到达时回调 `.final(text)`；正常收尾超时也可能回调 `.partial(text)`。宿主必须同时检查回调对应的 `voice.phase`：处于 `.ready` 的 final / partial 都是正常转写终态，等同代际的触发键已松开、捕获已完成后，按此次手势直接发送，无需再额外确认。

识别失败时，`voice.phase == .unavailable` 的 `.partial(text)` 只是已识别的可编辑草稿，`.unavailable` 则表示没有可用转写。HostExample 对这些失败终态调用 `Flow.voiceFailed`，清除默认动作并保留选区，等待用户显式输入；不会把失败尾文或原默认动作自动提交。`cancel()` 后的旧录音结果不能复活当前交互。切换任务、暂停、退出时宿主同步取消 voice 和 capture/API task。

## 来源与边界

`source-provenance.json` 逐文件列出原始相对路径、原始 SHA-256、交付文件 SHA-256 及 `copied` / `adapted` / `new` 分类。原样复制的文件未添加头注释，仍可按 hash 验证；所有适配文件有 `Adapted from` 标记。核心输入桥、语音 session/执行器与 ObjC 异常边界复用当前生产源码；monitor 是去掉多工作流路由/全应用耦合后的单输入适配，不能把此次构建视为 Chord 或 Lab 的完整设备验收。

Lab 的完整单选会话编排和模型网络连接属于相邻的 FlowKit / AIKit / HostExample。此包不读取 Keychain、不保存用户设置、不向任何服务发送数据。
