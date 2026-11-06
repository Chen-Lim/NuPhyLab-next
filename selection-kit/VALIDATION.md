# 本次验证记录

日期：2026-11-04。工具链：Apple Swift 6.3.3、macOS 26.5 SDK、arm64 主机；包使用 Swift 5 语言模式，部署下限 macOS 14。

| 项目 | 实际结果 | 证据 |
| --- | --- | --- |
| AIKit 源码编译 | 通过 | `Validation/ai-build.log`、`AIKit/VALIDATION.json` |
| AI 请求／流式／传输独立检查 | 25 个案例通过 | `AIKit/Validation/last-run.txt` |
| NativeKit debug/release 源码编译 | 通过 | `Validation/native-release-build.log`、`Validation/native-checks.log` |
| Native 输入／语音状态及合成图片独立检查 | 69 项通过 | `Validation/native-checks.log` |
| FlowKit 会话与异步效果独立检查 | 43 项通过 | `Validation/flow-checks.log` |
| HostExample 完整依赖图编译 | 通过 | `Validation/host-build.log` |
| XCTest 测试源 | 提供，未执行通过 | 当前 Command Line Tools 缺少 XCTest，实际报 `no such module 'XCTest'`；失败日志保留 |

独立检查直接编译／导入交付的实际源码，使用合成状态、PNG、HTTP、SSE 和本地 URLProtocol fixture。它们不是 XCTest 替身，也不等于真人操作或真实服务验收。未将原 Chord 历史测试数量计入本包结果。

检查覆盖三种协议的编码和终态、Mistral 混合内容、拒绝／截断／断流、分片 UTF-8、重定向拒绝、取消／超时、接收大小、不自动重试；输入归属与取消代际、按键释放排空、截图像素与缩图限额；等待截图与语音、防重、旧回调隔离、权限撤销后不能复活、失败语音等待明确动作、OCR 无网络和最终结果提交。

源码复核修正了：捕获尚未返回时的撤权取消、Mistral 文字／思考数组解析、语音错误片段禁止自动提交，以及同步状态回调后的手势复核。HostExample 的录音／截屏接线本次仅完成编译和源码复核，没有启动真实录音或屏幕捕获。

NativeKit 保留一项原 VoiceAudioWorker 的 Sendable 编译告警；串行 worker 运行时约束仍在。未验 Swift 6 严格语言模式；未为消除告警擅自把类型标记成 `@unchecked Sendable`。详见 `NativeKit/README.md`。

没有读取 Keychain、请求真实模型、触发权限弹窗、安装 App、签名公证、改官网或修改 NuPhyLab。实际模型账号／区域可用性、计费、实体键鼠、真人语音、跨屏、macOS 14/Intel、沙盒及 Lab UI 集成需后续验证。

`MANIFEST.json` 记录交付文件长度及 SHA-256；`python3 verify_manifest.py` 可在解压后验证。各模块 provenance 同时记录提取来源和适配差异。日志中的本机项目／临时路径已替换为占位符，未修改检查结果和告警内容。
