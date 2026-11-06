# LabSelectionAI

给 NuPhyLab 的独立 Swift Package，macOS 14+、Swift 5.9 包格式、Swift 5 语言模式。无第三方依赖、无 UI、无数据库；只处理本次选区文字/PNG与用户明确要求。原 Chord 工作树没有被修改。

## 已实现的 API 适配

| 服务/区域预设 | 请求与响应协议 | 模型列表 |
| --- | --- | --- |
| OpenAI | Responses；可显式配置 Chat Completions | 对应 origin 的 `/models` |
| Anthropic | 原生 Messages、JSON/SSE，API version `2026-10-21` | 原生 `/v1/models`，支持 `after_id` 分页 |
| Google Gemini | 官方 OpenAI Chat Completions 兼容接口 | 兼容 `/models` |
| OpenRouter | Chat Completions 兼容接口 | 兼容 `/models` |
| Groq | Chat Completions 兼容接口 | 兼容 `/models` |
| Mistral | Chat Completions 兼容接口 | 兼容 `/models` |
| xAI | Chat Completions 兼容接口 | 兼容 `/models` |
| DeepSeek | Chat Completions 兼容接口 | 兼容 `/models` |
| Qwen 中国 / 国际 | 分区域 Chat Completions 兼容接口 | 本次仅手填；官方目录使用独立 schema |
| 自定义 | 显式选择上述三种协议之一 | 安全推导或显式同 origin URL；必须是已支持目录 schema |

预设表示已实现请求编码和解析路径，真实账号、网络、地区及模型端到端尚未测试。没有内置“默认可用模型”：宿主读取目录或让用户手填，再保留其选择。列表有 ID 不等于有调用权限或支持图片。`imageInputConfirmed` 默认 false，由宿主对具体模型能力做明确确认；这不是每次请求都再次弹确认框。本次范围限定为单次框选，每个请求最多一张 PNG。

Gemini 原生 Interactions/generateContent 未实现。Qwen 预设采用文档保留的区域兼容域名；新账号若使用工作空间域名，宿主应按控制台提供地址配置完整 `endpoint`，并为新地址读取独立密钥。Qwen 官方模型目录是 `output.models[].model` 加页码；本包拒绝把它当 OpenAI `data[].id`，采用手填模型。Mistral 已兼容文档中的 string 与 text/thinking chunk 数组，只输出 text，思考内容始终忽略。

官方链接和核实日期见上层 `Docs/API调研与接入建议.md`。本包 Anthropic 版本根据 2026-11-04 查阅的官方版本说明固定为 `2026-10-21`，省略新版本已移除的 temperature/top_p/top_k；使用 Bearer 认证，可填 `anthropicWorkspaceID`。没有启用工具调用、远程检索、思考模式或供应商特有服务端工具。

## 宿主调用

```swift
import LabSelectionAI

let configuration = AIConfiguration(
    provider: .anthropic,
    model: modelIDChosenByUser,
    imageInputConfirmed: selectedModelAcceptsImages
)
// 使用 Lab 自己的 Keychain service；不要沿用 Chord 的应用身份。
let keychainAccount = try configuration.credentialAccount()
let apiKey = try await hostKeychain.read(account: keychainAccount)
let prompt = try AIRequestPrompt.selection(
    text: selectedText,
    instruction: "请翻译成简体中文，保留段落。"
)
let images = selectedPNG.map { [AIImageAttachment(png: $0)] } ?? []

let requestTask = Task {
    let finalText = try await AIClient().sendStreaming(
        configuration: configuration,
        prompt: prompt,
        images: images,
        apiKey: apiKey,
        onEvent: { event in
            // 在主线程更新前检查宿主捕获的 sessionID 仍有效。
            // 回调应很短；不要在回调中等待用户操作。
            if case .delta(let text, _) = event {
                await hostPreview.append(text, ifSessionIs: sessionID)
            }
        }
    )
    // 返回值是唯一正式完成的答案，应替换预览；不能将 partial 当成功结果。
    await hostPreview.finish(finalText, ifSessionIs: sessionID)
}
// Esc、暂停、权限撤销、新会话替换、窗口关闭：
requestTask.cancel()
```

示例中的 `hostKeychain`、`hostPreview`、`sessionID`、`modelIDChosenByUser` 等均是宿主接口占位，UI与交互编排由 Lab 实现。`AIRequestPrompt.selection` 用 JSON 将明确要求与不可信选区数据分开，并有独立系统要求；没有代码或系统操作执行能力。模型提示不能保证抵御所有提示注入，因此模型结果始终只是待显示的文字。

还提供非流式 `AIClient.send(configuration:prompt:images:apiKey:)`；模型列表为 `listModels(configuration:apiKey:afterID:) -> AIModelPage`。Anthropic `nextCursor` 非空时，由用户/宿主明确触发下一页。其它服务不自动翻页，不修改当前模型，也不把请求失败改成另一个模型重发。

## 网络与宿主责任

- 请求 HTTPS、拒绝 URL 内凭据/查询/片段和全部重定向；显式模型目录必须与生成端点同 origin。API Key 只作为调用参数进入内存。包不读写 Keychain、日志或磁盘缓存。
- 每次调用发送一次 POST；HTTP 错误、不支持 stream、超时、截断和失败均不自动重试。若同一个 stream 请求直接返回 JSON，解析该响应而不重发。
- 无 cookie、URL credential storage 或共享 URL cache；流式邮箱合并数据并限量，响应上限 2 MiB，文字输入 128 KiB、每图 8 MiB、总体请求 12 MiB，默认总等待/空闲上限 60 秒。每次最多输出 4096 token，宿主可设 1...32768，实际模型上限由服务校验。
- 图片校验仅检查 PNG 签名及大小；宿主应从可靠截图/编码器传入合法 PNG，并约束像素尺寸。模型图片能力、区域政策、用户 API 账单由宿主展示和核对。
- `Task.cancel()`取消本地网络等待，不保证服务商撤回处理或退款。错误正文、思考文本与凭据不暴露；公开 `AIError` 为可本地化的枚举。宿主负责中英错误文案。
- 流式事件需宿主检查当前 sessionID，避免旧请求覆盖新会话；长答案显示节流、Markdown安全渲染、复制按钮等属于新的 Lab 界面。

## 验证

```sh
xcrun swift build --package-path AIKit --scratch-path /tmp/lab-ai-build
bash AIKit/Validation/run.sh
```

`Validation/run.sh`使用真实 `Sources/LabSelectionAI/*.swift` 编译独立断言程序，运行合成 HTTP/SSE fixtures，覆盖协议、拒绝/截断、UTF-8分片、终态、大小边界、取消、超时、重定向拒绝、不自动重试等。它不是 XCTest，也没有真实服务调用。此脚本自己创建和删除临时编译目录，不生成 `.app`。

`Tests/LabSelectionAITests/` 另提供 XCTest 测试源。当前电脑只有缺少 XCTest 模块的 Command Line Tools，`swift test`无法执行；不能把独立断言程序冒充 XCTest 通过。在具备完整 Xcode XCTest 环境的 Mac 上可执行：

```sh
xcrun swift test --package-path AIKit --scratch-path /tmp/lab-ai-tests
```

当前结果见 `VALIDATION.json`。本包未做真实模型、实体键鼠/语音、安装、签名、公证或海外网络验证。来源与适配差异见 `SOURCE-PROVENANCE.json`；源码不是原 Chord 完整应用的逐字节副本。
