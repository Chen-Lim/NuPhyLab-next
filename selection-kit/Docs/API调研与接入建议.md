# Lab 单次框选 AI：API 调研与接入建议

核对日期：**2026-11-04**。范围是一次框选后的翻译、总结、解释、改写、提取文字和自由提问；**不包含收集、保存多份材料后一起提问**。UI 由 Lab 重新设计。

本报告核对的是官方公开文档，没有读取用户密钥、调用真实模型或验证各地区账号。交付包的 AIKit 提供 **OpenAI Responses、Chat Completions 兼容、Anthropic Messages** 三种协议；Gemini 通过官方 OpenAI 兼容入口接入。下文的原生 Gemini 接口属于调研资料，未包含原生适配器。代码测试结果以交付包的验证记录为准，不能据此宣称所有供应商已实测可用。

## 建议的接入顺序

1. **优先验收 OpenAI、Claude、Gemini，以及 DeepSeek、Qwen 北京／国际两个独立配置。** 前三者覆盖主要海外直连选择，后两者承接原项目配置习惯。这是工程优先级建议，不是模型效果、速度或价格排名。
2. **同时保留 OpenRouter、Groq、Mistral、xAI 预设和自定义兼容端点。** 它们可共用 Chat 适配层，但图片、推理参数和结束事件仍须按实际模型验证。OpenRouter 是聚合服务；选择它意味着请求也受其上游路由和数据处理配置影响。
3. 模型 ID 默认留空，让使用者刷新目录或从服务控制台填写。目录存在不代表该账号已有余额、区域授权或图片权限；不要凭模型名称推断图片能力。

## 官方接口矩阵

表中 **Chat** 指向所列 Base URL 追加 `/chat/completions`；所有地址均为 HTTPS。除 Claude 的额外头字段外，下列兼容入口均使用 `Authorization: Bearer <该服务的 API key>`。所有供应商都有文字输出和 SSE 流式方案；图片输入必须选择对应的视觉模型，不能对整个供应商统一标为支持或不支持。

**AIKit 的 `AIConfiguration.endpoint` 接收完整请求 URL，不是 SDK Base URL。** 预设已包含正确路径；自定义配置不要漏掉或重复追加 `/chat/completions`。

| 服务 | 本次使用的协议／Base URL | 官方模型目录 | 图片与接入要点、官方来源 |
| --- | --- | --- | --- |
| OpenAI | Responses：`https://api.openai.com/v1/responses`；也可用 Chat，Base 为 `https://api.openai.com/v1` | `GET https://api.openai.com/v1/models` | 新集成官方推荐 Responses；两种协议均有图片输入，但字段不同。[流式与协议](https://developers.openai.com/api/docs/guides/streaming-responses)、[图片](https://developers.openai.com/api/docs/guides/images-vision)、[模型目录](https://developers.openai.com/api/reference/resources/models/methods/list) |
| Anthropic / Claude | Messages：`POST https://api.anthropic.com/v1/messages` | `GET https://api.anthropic.com/v1/models` | 独立 Messages 结构和图像块；需要版本头，工作空间要求见下文。[接口／鉴权](https://platform.claude.com/docs/en/api/overview)、[Messages](https://platform.claude.com/docs/en/api/messages/create) |
| Google Gemini | Chat：`https://generativelanguage.googleapis.com/v1beta/openai` | 兼容目录：`GET …/v1beta/openai/models` | 使用 Gemini key；兼容入口支持图片与 `stream:true`。不是把 OpenAI key 交给 Google。[兼容接口、图片与目录](https://aistudio.google.com/docs/openai) |
| OpenRouter | Chat：`https://openrouter.ai/api/v1` | `GET https://openrouter.ai/api/v1/models` | 按目录中的输入模态选择视觉模型；SSE 有注释和特殊 usage 尾块。[协议](https://openrouter.ai/docs/api_reference/overview)、[目录](https://openrouter.ai/docs/api/api-reference/models/list-all-models-and-their-properties)、[流式差异](https://openrouter.ai/docs/api_reference/streaming) |
| Groq | Chat：`https://api.groq.com/openai/v1` | `GET https://api.groq.com/openai/v1/models` | 只给已核对的视觉模型开启图片；不要将预览模型当长期稳定默认。[兼容入口](https://console.groq.com/docs/openai)、[视觉](https://console.groq.com/docs/vision)、[目录](https://console.groq.com/docs/models)、[流式](https://console.groq.com/docs/text-chat) |
| Mistral | Chat：`https://api.mistral.ai/v1` | `GET https://api.mistral.ai/v1/models` | 视觉模型经 Chat 接收 URL 或 base64 图片。[Chat](https://docs.mistral.ai/api/endpoint/chat)、[视觉](https://docs.mistral.ai/studio/conversations/vision)、[目录](https://docs.mistral.ai/api/endpoint/models) |
| xAI | Chat：`https://api.x.ai/v1` | `GET https://api.x.ai/v1/models` | 当前官方优先推荐 Responses，Chat 兼容仍有文档；文字／视觉流式均受支持。可另读 `/v1/language-models` 获取模态，不能当成普通目录同一结构。[鉴权](https://docs.x.ai/developers/rest-api-reference/inference)、[Chat](https://docs.x.ai/developers/rest-api-reference/inference/chat-completions)、[流式](https://docs.x.ai/developers/model-capabilities/text/streaming)、[目录](https://docs.x.ai/developers/rest-api-reference/inference/models) |
| DeepSeek | Chat：`https://api.deepseek.com` | `GET https://api.deepseek.com/models` | 当前官方已有部分视觉模型，不能沿用“DeepSeek 全部只支持文字”的旧判断；按具体模型能力决定。[Chat](https://api-docs.deepseek.com/api/create-chat-completion/)、[视觉](https://api-docs.deepseek.com/guides/vision/)、[目录](https://api-docs.deepseek.com/api/list-models/) |
| Qwen / Model Studio | Chat；北京共享入口：`https://dashscope.aliyuncs.com/compatible-mode/v1`；新加坡共享入口：`https://dashscope-intl.aliyuncs.com/compatible-mode/v1` | 官方新目录使用 `/api/v1/models`，**不是**在兼容 Base 后追加 `/models` | 国内／国际区域需独立 key、模型和配置；生产优先使用控制台给出的工作空间域名。目录详情见下文。[区域地址](https://www.alibabacloud.com/help/en/model-studio/base-url)、[目录](https://help.aliyun.com/en/model-studio/list-models)、[图文流式](https://help.aliyun.com/en/model-studio/stream) |

## 需要单独处理的协议差异

**Responses 与 Chat 不应只换 URL。** Responses 的图文块是 `input_text`／`input_image`，主要文字增量事件是 `response.output_text.delta`；Chat 使用 `messages`、`text`／`image_url`，读取 `choices[].delta.content`。结束时要区分完成、截断、拒绝和错误，网络 EOF 不能自动算成功。建议只发送本动作必要的参数，避免把一个模型的 temperature、推理或输出长度字段无条件发给所有服务。[OpenAI 流式](https://developers.openai.com/api/docs/guides/streaming-responses)、[图像字段](https://developers.openai.com/api/docs/guides/images-vision)

**Claude。** 官方当前推荐 `anthropic-version: 2026-10-21`；这一版本不接受 `temperature`、`top_p`、`top_k`。鉴权优先 Bearer，`x-api-key` 仍是官方支持的兼容方式；未限定到单一工作空间的 key 需要 `anthropic-workspace-id`。请求的 `system` 位于顶层，图片使用 `image` 块及 base64 `source`。流式正文从 `content_block_delta` 的 `text_delta` 读取，并结合 `message_delta` 和 `message_stop` 判定终态。解析器要兼容 `stop_reason: refusal` 与 `stop_details.type: refusal`；`max_tokens`、`model_context_window_exceeded` 属于未完整输出，`tool_use`／`pause_turn` 不能当作普通答案完成。[版本差异](https://platform.claude.com/docs/en/api/versioning)、[鉴权](https://platform.claude.com/docs/en/api/overview)、[请求结构](https://platform.claude.com/docs/en/api/messages/create)、[流式](https://platform.claude.com/docs/en/build-with-claude/streaming)、[结束原因](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons)

**Gemini 原生路线。** 当前官方入门使用 `POST https://generativelanguage.googleapis.com/v1beta/interactions`，头字段为 `x-goog-api-key` 和示例版本 `Api-Revision: 2026-05-20`；流式文字使用 `step.delta` 事件。参考文档也保留 `POST /v1beta/models/{model}:generateContent` 与 `:streamGenerateContent`，使用 `contents/parts`、`inlineData` 等原生结构；原生模型目录为 `GET /v1beta/models`。这些都不能送进 Chat 解析器。本包选用官方兼容入口完成单次图文处理，今后确有原生特性需求再增加适配器。[原生入门](https://aistudio.google.com/docs/get-started)、[流式](https://aistudio.google.com/docs/text-generation)、[GenerateContent](https://aistudio.google.com/api-reference/generate-content)、[模型](https://aistudio.google.com/api-reference/models)

**SSE 尾块。** 兼容服务可能发送空 `choices` usage 块、空文字或保活注释。OpenRouter 的 Chat usage 尾块还会重复 `finish_reason`，不能把它当第二次完成或格式错误。错误也可能发生在 HTTP 200 的流中。取消应停止本地接收并释放任务；尤其经聚合服务时，不能承诺断开连接一定终止上游计费。[OpenRouter 流式约定](https://openrouter.ai/docs/api_reference/streaming)、[Qwen 流式约定](https://help.aliyun.com/en/model-studio/stream)

**Mistral 内容块。** 某些模型的 `message.content` 是 `thinking`／`text` 块数组；流式 `delta.content` 也可能先是数组，过渡块同时含思考块和第一段正文，之后变为字符串。部分模型不存在纯字符串模式，因此不能靠不传推理参数来保证该结构不出现。本包在 Mistral 预设下只提取 `text` 作为答案，跳过已知思考块，拒绝不支持的工具块；没有把思考内容展示为正文。[Mistral 推理与流式结构](https://docs.mistral.ai/studio/conversations/reasoning)

## Qwen 国内、国际与目录

Qwen 的区域 key、端点和模型集合相互独立。北京工作空间兼容 Base 示例为 `https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1`，新加坡为 `https://{WorkspaceId}.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1`；占位符必须替换为控制台的真实工作空间。官方还列有香港、东京、法兰克福和美国区域，应让宿主接受控制台提供的完整端点，不能将“国际”理解成一个通用 key。新加坡国际部署也不等于所有推理都固定发生在新加坡。[地址与区域约束](https://www.alibabacloud.com/help/en/model-studio/base-url)、[新加坡部署范围](https://www.alibabacloud.com/help/en/model-studio/singapore-regional-access-information)

官方目录示例：北京 `GET https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/api/v1/models`；新加坡 `GET https://dashscope-intl.aliyuncs.com/api/v1/models`。返回 `output.models[].model`，并有 `page_no/page_size/total`，与 OpenAI 的 `data[].id` 不同。**本包 Qwen 默认采用手填模型 ID；不要将这份官方目录写成已实现的自动刷新能力。** 后续如添加目录适配，应处理这个结构、分页和区域绑定，不能为了刷新目录把 key 自动发到另一主机。[官方模型目录](https://help.aliyun.com/en/model-studio/list-models)

## 账号、额度与 Lab 配置边界

服务网页订阅、API 凭据和 API 计费配置需要分别核对；Lab 不根据“已订阅”推断 API 可用或免费。当前 OpenAI 的部分 Pro／Business 订阅可以绑定 API 组织领取额度；Claude 的部分 Max／Ultra／Team 计划也有 API credits，但仍需设置 Console 访问。因此也不能一概写“所有商业订阅都不含 API 额度”。以各账号当时的权益、额度有效期和 API 控制台为准。[OpenAI 订阅额度](https://developers.openai.com/api/docs/guides/chatgpt-api-credits)、[Claude 订阅与 API](https://support.claude.com/en/articles/9876003-why-is-claude-api-usage-billed-separately-from-my-paid-claude-plan)

本功能应使用普通模型 API 服务；阿里云 Coding Plan／Token Plan 的专用入口和 key 有适用场景约束，不能因为价格合适就当成通用应用推理套餐。Google 的 API 付费层也有独立项目和 Cloud Billing 配置。[阿里云入口说明](https://www.alibabacloud.com/help/en/model-studio/base-url)、[Gemini API 配置](https://aistudio.google.com/docs/get-started)

Lab 集成时应保存“服务／区域／协议／完整端点／模型／图片能力”配置，将 key 放在 Lab 自己的 Keychain 命名空间。仅发送用户本次选中的文字或截图；图片能力未确认时提示选择视觉模型或使用明确的 OCR 文字流程，不静默丢图。不自动跨服务切换或重发收费请求。UI、错误提示和当前目标服务由 Lab 呈现；取消、换一次框选和关闭结果不应把材料累积到下一次请求。

正式验收需在目标账号和地区补做：短文字、单张截图、长答案流式、取消、401／403／429、拒绝、截断和中途断流。没有完成这些真实调用前，应标为“协议适配已提供，实际服务待配置验证”。官方来源及核对日期同时保存在 `research-sources.json`。
