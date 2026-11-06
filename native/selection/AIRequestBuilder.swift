// Adapted request/validation policies from ChordCore/AIRequestBuilder.swift.
import Foundation

public struct AIImageAttachment: Equatable, Sendable {
    public let label: String
    public let png: Data
    public init(label: String = "", png: Data) { self.label = label; self.png = png }
}

public enum AIRequestBuilder {
    public static let maximumTextBytes = 128 * 1024
    public static let maximumImageBytes = 8 * 1024 * 1024
    public static let maximumPayloadBytes = 12 * 1024 * 1024
    public static let maximumResponseBytes = 2 * 1024 * 1024
    public static let timeout: TimeInterval = 60
    public static let anthropicVersion = "2026-10-21"

    public static func build(configuration: AIConfiguration, prompt: AIRequestPrompt,
                             images: [AIImageAttachment] = [], apiKey: String, stream: Bool = false) throws -> URLRequest {
        let url = try configuration.validatedEndpoint()
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, model.utf8.count <= 256,
              model.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else { throw AIError.missingModel }
        try validateKey(apiKey)
        guard (1...32768).contains(configuration.maximumOutputTokens) else { throw AIError.invalidOutputFormat }
        let text = prompt.user, system = prompt.system ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty else { throw AIError.emptyInput }
        guard text.utf8.count <= maximumTextBytes, system.utf8.count <= maximumTextBytes - text.utf8.count else { throw AIError.textTooLarge }
        guard images.count <= 1 else { throw AIError.tooManyImages }
        for image in images {
            guard configuration.imageInputConfirmed else { throw AIError.imagesDisabled }
            guard image.label.utf8.count <= 64 else { throw AIError.payloadTooLarge }
            guard image.png.count <= maximumImageBytes else { throw AIError.imageTooLarge }
            guard image.png.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else { throw AIError.invalidImage }
        }
        var body: [String: Any] = ["model": model, "stream": stream]
        switch configuration.apiProtocol {
        case .responses:
            var content: [[String: Any]] = []
            if !text.isEmpty { content.append(["type": "input_text", "text": text]) }
            for image in images {
                if !image.label.isEmpty { content.append(["type": "input_text", "text": "Object \(image.label):"]) }
                content.append(["type": "input_image", "image_url": "data:image/png;base64," + image.png.base64EncodedString()])
            }
            var input: [[String: Any]] = []
            if !system.isEmpty { input.append(["role": "system", "content": [["type": "input_text", "text": system]]]) }
            input.append(["role": "user", "content": content])
            body["input"] = input
            body["store"] = false
            body["max_output_tokens"] = configuration.maximumOutputTokens
        case .chatCompletions:
            var messages: [[String: Any]] = []
            if !system.isEmpty { messages.append(["role": "system", "content": system]) }
            if images.isEmpty { messages.append(["role": "user", "content": text]) }
            else {
                var content: [[String: Any]] = []
                if !text.isEmpty { content.append(["type": "text", "text": text]) }
                for image in images {
                    if !image.label.isEmpty { content.append(["type": "text", "text": "Object \(image.label):"]) }
                    content.append(["type": "image_url", "image_url": ["url": "data:image/png;base64," + image.png.base64EncodedString()]])
                }
                messages.append(["role": "user", "content": content])
            }
            body["messages"] = messages
            // Official OpenAI uses max_completion_tokens; compatible implementations
            // generally document max_tokens. No model-name heuristics or reasoning flags.
            let officialOpenAI = configuration.provider == .openAI && url.host?.lowercased() == "api.openai.com"
            body[officialOpenAI ? "max_completion_tokens" : "max_tokens"] = configuration.maximumOutputTokens
        case .anthropicMessages:
            var content: [[String: Any]] = []
            if !text.isEmpty { content.append(["type": "text", "text": text]) }
            for image in images {
                if !image.label.isEmpty { content.append(["type": "text", "text": "Object \(image.label):"]) }
                content.append(["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": image.png.base64EncodedString()]])
            }
            body["messages"] = [["role": "user", "content": content]]
            if !system.isEmpty { body["system"] = system }
            body["max_tokens"] = configuration.maximumOutputTokens
        }
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        guard data.count <= maximumPayloadBytes else { throw AIError.payloadTooLarge }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        try authenticate(&request, configuration: configuration, apiKey: apiKey)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(stream ? "text/event-stream, application/json" : "application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpShouldHandleCookies = false
        request.httpBody = data
        return request
    }

    static func validateKey(_ key: String) throws {
        guard !key.isEmpty else { throw AIError.missingKey }
        guard key.utf8.count <= 4096, key.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else { throw AIError.invalidKey }
    }

    static func authenticate(_ request: inout URLRequest, configuration: AIConfiguration, apiKey: String) throws {
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        if configuration.apiProtocol == .anthropicMessages {
            request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
            if let workspace = configuration.anthropicWorkspaceID {
                guard !workspace.isEmpty, workspace.utf8.count <= 256,
                      workspace.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else { throw AIError.invalidOutputFormat }
                request.setValue(workspace, forHTTPHeaderField: "anthropic-workspace-id")
            }
        }
    }

    public static func parse(data: Data, configuration: AIConfiguration) throws -> String {
        guard data.count <= maximumResponseBytes else { throw AIError.responseTooLarge }
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw AIError.invalidResponse }
        if let error = body["error"], !(error is NSNull) { throw AIError.providerError }
        var texts: [String] = []
        switch configuration.apiProtocol {
        case .responses:
            guard body["status"] as? String == "completed" else { throw AIError.incompleteResponse }
            guard let output = body["output"] as? [[String: Any]] else { throw AIError.invalidResponse }
            for item in output {
                let type = item["type"] as? String
                if type == "reasoning" { continue }
                guard type == "message", item["role"] as? String == "assistant" else { throw AIError.incompleteResponse }
                if let status = item["status"] as? String, status != "completed" { throw AIError.incompleteResponse }
                for content in item["content"] as? [[String: Any]] ?? [] {
                    if content["type"] as? String == "refusal" { throw AIError.refused }
                    if content["type"] as? String == "output_text", let text = content["text"] as? String { texts.append(text) }
                }
            }
        case .chatCompletions:
            guard let choices = body["choices"] as? [[String: Any]],
                  let choice = choices.first(where: { ($0["index"] as? Int ?? 0) == 0 }),
                  let message = choice["message"] as? [String: Any] else { throw AIError.invalidResponse }
            if choice["finish_reason"] as? String == "content_filter" { throw AIError.refused }
            guard choice["finish_reason"] as? String == "stop" else { throw AIError.incompleteResponse }
            try validateNoTools(message)
            if let refusal = message["refusal"] as? String, !refusal.isEmpty { throw AIError.refused }
            if let role = message["role"] as? String, role != "assistant" { throw AIError.invalidResponse }
            texts.append(try chatText(message["content"], provider: configuration.provider))
        case .anthropicMessages:
            guard body["type"] as? String == "message", body["role"] as? String == "assistant",
                  let content = body["content"] as? [[String: Any]] else { throw AIError.invalidResponse }
            try validateAnthropicStop(body)
            for part in content {
                switch part["type"] as? String {
                case "text":
                    guard let text = part["text"] as? String else { throw AIError.invalidResponse }
                    texts.append(text)
                case "thinking", "redacted_thinking": continue
                case "refusal": throw AIError.refused
                default: throw AIError.incompleteResponse
                }
            }
        }
        let result = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw AIError.emptyResponse }
        return result
    }

    static func validateNoTools(_ value: [String: Any]) throws {
        if let calls = value["tool_calls"], !(calls is NSNull) {
            guard let calls = calls as? [[String: Any]] else { throw AIError.invalidResponse }
            if !calls.isEmpty { throw AIError.incompleteResponse }
        }
        if let call = value["function_call"], !(call is NSNull) { throw AIError.incompleteResponse }
    }

    /// Mistral documents content chunks for reasoning models, including a
    /// mixed transition chunk containing thinking + visible text. Never expose
    /// the thinking field; do not confuse it with a tool or a completed answer.
    static func chatText(_ content: Any?, provider: AIProvider) throws -> String {
        guard let content, !(content is NSNull) else { return "" }
        if let text = content as? String { return text }
        guard let chunks = content as? [[String: Any]] else { throw AIError.invalidResponse }
        var visible = ""
        for chunk in chunks {
            if chunk["type"] as? String == "thinking", provider == .mistral { continue }
            guard chunk["type"] as? String == "text", let text = chunk["text"] as? String else { throw AIError.invalidResponse }
            visible += text
        }
        return visible
    }

    static func validateAnthropicStop(_ value: [String: Any]) throws {
        let reason = value["stop_reason"] as? String
        if reason == "refusal" || (value["stop_details"] as? [String: Any])?["type"] as? String == "refusal" {
            throw AIError.refused
        }
        guard reason == "end_turn" || reason == "stop_sequence" else { throw AIError.incompleteResponse }
    }

    static func validateStatus(_ status: Int) throws {
        switch status {
        case 200...299: return
        case 300...399: throw AIError.redirected
        case 401, 403: throw AIError.authentication
        case 429: throw AIError.rateLimited
        case 500...599: throw AIError.serviceUnavailable
        default: throw AIError.rejected(status)
        }
    }
}
