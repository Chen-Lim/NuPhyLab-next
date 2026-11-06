// Adapted from Chord ChordCore/AIStreamingParser.swift. See SOURCE-PROVENANCE.json.
import Foundation

public enum AIStreamingFormat: Sendable, Equatable {
    case serverSentEvents, json
}

/// Only duration and response text cross this boundary; raw headers, provider errors,
/// reasoning and credentials are never reported. Durations use a monotonic clock.
public enum AIStreamingEvent: Sendable, Equatable {
    case headers(elapsed: TimeInterval, format: AIStreamingFormat)
    case firstText(elapsed: TimeInterval)
    /// An incremental text fragment, never the accumulated preview.
    case delta(text: String, elapsed: TimeInterval)
}

struct AISSEEvent: Equatable {
    let name: String
    let data: String
}

/// UTF-8 is decoded only after a complete line, so network chunk boundaries cannot
/// split a scalar. Handles BOM, LF / CRLF / CR, comments and multiline data fields.
/// An unterminated event at EOF is deliberately not dispatched (SSE framing rule).
struct AISSEParser {
    private var line = Data()
    private var eventName = ""
    private var dataLines: [String] = []
    private var eventBytes = 0
    private var firstLine = true
    private var previousCR = false
    let maximumEventBytes: Int

    init(maximumEventBytes: Int = AIRequestBuilder.maximumResponseBytes) {
        self.maximumEventBytes = maximumEventBytes
    }

    mutating func append(_ byte: UInt8) throws -> AISSEEvent? {
        if previousCR {
            previousCR = false
            if byte == 10 { return nil }
        }
        if byte == 13 || byte == 10 {
            previousCR = byte == 13
            return try endLine()
        }
        guard line.count < maximumEventBytes, eventBytes < maximumEventBytes else { throw AIError.responseTooLarge }
        line.append(byte)
        eventBytes += 1
        return nil
    }

    private mutating func endLine() throws -> AISSEEvent? {
        if firstLine {
            firstLine = false
            if line.starts(with: [0xEF, 0xBB, 0xBF]) { line.removeFirst(3) }
        }
        guard let value = String(data: line, encoding: .utf8) else { throw AIError.invalidResponse }
        line.removeAll(keepingCapacity: true)
        if value.isEmpty {
            defer { eventName = ""; dataLines.removeAll(keepingCapacity: true); eventBytes = 0 }
            guard !dataLines.isEmpty else { return nil }
            return AISSEEvent(name: eventName.isEmpty ? "message" : eventName, data: dataLines.joined(separator: "\n"))
        }
        if value.hasPrefix(":") { return nil }
        let field: String
        var content: String
        if let colon = value.firstIndex(of: ":") {
            field = String(value[..<colon])
            content = String(value[value.index(after: colon)...])
            if content.hasPrefix(" ") { content.removeFirst() }
        } else { field = value; content = "" }
        switch field {
        case "data":
            // Include inserted newlines in the event bound, including empty data lines.
            guard eventBytes < maximumEventBytes else { throw AIError.responseTooLarge }
            eventBytes += 1
            dataLines.append(content)
        case "event": eventName = content
        default: break // id/retry are not used: a paid request is never reconnected.
        }
        return nil
    }
}

/// Parses only ordinary assistant text. Final Responses output is authoritative;
/// previews must never be treated as a successfully completed result by callers.
struct AIStreamingResponseParser {
    private let configuration: AIConfiguration
    private let maximumTextBytes: Int
    private var text = ""
    private var textBytes = 0
    private var partText: [String: String] = [:]
    private var doneParts: Set<String> = []
    private var lastPart: String?
    private var chatStopped = false
    private var anthropicStarted = false
    private var anthropicStopped = false
    private var anthropicBlocks: [Int: String] = [:]
    private var anthropicClosed: Set<Int> = []
    private(set) var result: String?

    init(configuration: AIConfiguration, maximumTextBytes: Int = AIRequestBuilder.maximumResponseBytes) {
        self.configuration = configuration
        self.maximumTextBytes = maximumTextBytes
    }

    mutating func consume(_ event: AISSEEvent) throws -> [String] {
        guard result == nil else { throw AIError.invalidResponse }
        if event.name == "error" { throw AIError.providerError }
        if event.data.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
            guard configuration.apiProtocol == .chatCompletions, chatStopped else { throw AIError.incompleteResponse }
            result = try completeText()
            return []
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(event.data.utf8)),
              let body = object as? [String: Any] else { throw AIError.invalidResponse }
        if let error = body["error"], !(error is NSNull) { throw AIError.providerError }
        if body["type"] as? String == "error" { throw AIError.providerError }
        switch configuration.apiProtocol {
        case .responses: return try consumeResponse(body, eventName: event.name)
        case .chatCompletions: return try consumeChat(body)
        case .anthropicMessages: return try consumeAnthropic(body, eventName: event.name)
        }
    }

    func finish() throws -> String {
        if let result { return result }
        // Some compatible Chat servers close cleanly after finish_reason=stop.
        // A bare [DONE], missing finish reason or truncated Responses stream is not success.
        if configuration.apiProtocol == .chatCompletions, chatStopped { return try completeText() }
        throw AIError.incompleteResponse
    }

    private mutating func consumeResponse(_ body: [String: Any], eventName: String) throws -> [String] {
        guard let type = body["type"] as? String ?? (eventName == "message" ? nil : eventName) else { throw AIError.invalidResponse }
        if eventName != "message", eventName != type { throw AIError.invalidResponse }
        switch type {
        case "response.failed", "response.error": throw AIError.providerError
        case "response.incomplete", "response.cancelled":
            if let response = body["response"] as? [String: Any],
               let details = response["incomplete_details"] as? [String: Any],
               details["reason"] as? String == "content_filter" { throw AIError.refused }
            throw AIError.incompleteResponse
        case "response.refusal.delta", "response.refusal.done": throw AIError.refused
        case "response.output_text.delta":
            guard let delta = body["delta"] as? String else { throw AIError.invalidResponse }
            let key = try partKey(body)
            guard !doneParts.contains(key) else { throw AIError.invalidResponse }
            guard !delta.isEmpty else { return [] }
            let separator = lastPart != nil && lastPart != key ? "\n" : ""
            let update = separator + delta
            try appendText(update)
            partText[key, default: ""] += delta
            lastPart = key
            return [update]
        case "response.output_text.done":
            guard let final = body["text"] as? String else { throw AIError.invalidResponse }
            let key = try partKey(body)
            if let existing = partText[key] {
                guard existing == final else { throw AIError.invalidResponse }
                doneParts.insert(key)
                return []
            }
            doneParts.insert(key)
            partText[key] = final
            guard !final.isEmpty else { return [] }
            let update = (lastPart == nil ? "" : "\n") + final
            try appendText(update)
            lastPart = key
            return [update]
        case "response.completed":
            guard let response = body["response"] as? [String: Any] else { throw AIError.invalidResponse }
            let data = try JSONSerialization.data(withJSONObject: response)
            let final = try AIRequestBuilder.parse(data: data, configuration: configuration)
            guard final.utf8.count <= maximumTextBytes else { throw AIError.responseTooLarge }
            result = final
            // Avoid replaying deltas from the final full response. The returned string
            // lets the caller replace its preview with canonical final output.
            return text.isEmpty ? [final] : []
        case "response.content_part.added", "response.content_part.done":
            if let part = body["part"] as? [String: Any], part["type"] as? String == "refusal" { throw AIError.refused }
            return []
        case "response.output_item.added", "response.output_item.done":
            if let item = body["item"] as? [String: Any],
               let content = item["content"] as? [[String: Any]],
               content.contains(where: { $0["type"] as? String == "refusal" }) { throw AIError.refused }
            return []
        default:
            guard type.hasPrefix("response.") else { throw AIError.invalidResponse }
            return [] // Lifecycle, reasoning, annotations and tool payloads are not text.
        }
    }

    private mutating func consumeChat(_ body: [String: Any]) throws -> [String] {
        guard let choices = body["choices"] as? [[String: Any]] else { throw AIError.invalidResponse }
        guard !choices.isEmpty else { return [] } // Optional usage-only chunk.
        guard let choice = choices.first(where: { ($0["index"] as? Int ?? 0) == 0 }) else { return [] }
        guard let delta = choice["delta"] as? [String: Any] else { throw AIError.invalidResponse }
        if let refusal = delta["refusal"] as? String, !refusal.isEmpty { throw AIError.refused }
        if let finish = choice["finish_reason"] as? String {
            if finish == "content_filter" { throw AIError.refused }
            guard finish == "stop" else { throw AIError.incompleteResponse }
        }
        // Compatible providers may serialize absent optional fields as JSON null.
        // An empty tool_calls array also contains no calls; actual call fragments
        // are unsupported by this text-only path, even before a finish reason.
        if let value = delta["tool_calls"], !(value is NSNull) {
            guard let calls = value as? [[String: Any]] else { throw AIError.invalidResponse }
            if !calls.isEmpty { throw AIError.incompleteResponse }
        }
        if let value = delta["function_call"], !(value is NSNull) {
            guard value is [String: Any] else { throw AIError.invalidResponse }
            throw AIError.incompleteResponse
        }
        if let role = delta["role"] as? String, role != "assistant" { throw AIError.invalidResponse }
        let content = try AIRequestBuilder.chatText(delta["content"], provider: configuration.provider)
        guard !chatStopped || content.isEmpty else { throw AIError.invalidResponse }
        if choice["finish_reason"] as? String == "stop" { chatStopped = true }
        guard !content.isEmpty else { return [] }
        try appendText(content)
        return [content]
    }

    private mutating func consumeAnthropic(_ body: [String: Any], eventName: String) throws -> [String] {
        guard let type = body["type"] as? String,
              eventName == "message" || eventName == type else { throw AIError.invalidResponse }
        switch type {
        case "ping": return []
        case "message_start":
            guard !anthropicStarted, let message = body["message"] as? [String: Any],
                  message["type"] as? String == "message", message["role"] as? String == "assistant",
                  let content = message["content"] as? [[String: Any]], content.isEmpty else { throw AIError.invalidResponse }
            anthropicStarted = true
            return []
        case "content_block_start":
            guard anthropicStarted, !anthropicStopped,
                  let index = body["index"] as? Int, index >= 0, anthropicBlocks[index] == nil,
                  let block = body["content_block"] as? [String: Any], let kind = block["type"] as? String else { throw AIError.invalidResponse }
            if kind == "refusal" { throw AIError.refused }
            guard ["text", "thinking", "redacted_thinking"].contains(kind) else { throw AIError.incompleteResponse }
            anthropicBlocks[index] = kind
            guard kind == "text" else { return [] }
            guard let value = block["text"] as? String else { throw AIError.invalidResponse }
            guard !value.isEmpty else { return [] }
            let update = (text.isEmpty ? "" : "\n") + value
            lastPart = "anthropic:\(index)"
            try appendText(update)
            return [update]
        case "content_block_delta":
            guard anthropicStarted, !anthropicStopped,
                  let index = body["index"] as? Int, let kind = anthropicBlocks[index], !anthropicClosed.contains(index),
                  let delta = body["delta"] as? [String: Any], let deltaType = delta["type"] as? String else { throw AIError.invalidResponse }
            if deltaType == "text_delta" {
                guard kind == "text", let value = delta["text"] as? String else { throw AIError.invalidResponse }
                guard !value.isEmpty else { return [] }
                let part = "anthropic:\(index)"
                let update = (lastPart != nil && lastPart != part ? "\n" : "") + value
                lastPart = part
                try appendText(update)
                return [update]
            }
            if kind == "thinking", ["thinking_delta", "signature_delta"].contains(deltaType) { return [] }
            if kind == "text", deltaType == "citations_delta" { return [] }
            throw AIError.incompleteResponse
        case "content_block_stop":
            guard anthropicStarted, !anthropicStopped, let index = body["index"] as? Int,
                  anthropicBlocks[index] != nil, !anthropicClosed.contains(index) else { throw AIError.invalidResponse }
            anthropicClosed.insert(index)
            return []
        case "message_delta":
            guard anthropicStarted, !anthropicStopped, anthropicClosed.count == anthropicBlocks.count,
                  let delta = body["delta"] as? [String: Any] else { throw AIError.invalidResponse }
            try AIRequestBuilder.validateAnthropicStop(delta)
            anthropicStopped = true
            return []
        case "message_stop":
            guard anthropicStarted, anthropicStopped else { throw AIError.incompleteResponse }
            result = try completeText()
            return []
        default: throw AIError.invalidResponse
        }
    }

    private func partKey(_ body: [String: Any]) throws -> String {
        let output = body["output_index"] as? Int ?? 0
        let content = body["content_index"] as? Int ?? 0
        guard output >= 0, content >= 0 else { throw AIError.invalidResponse }
        return "\(output):\(content)"
    }

    private mutating func appendText(_ addition: String) throws {
        let count = addition.utf8.count
        guard count <= maximumTextBytes - textBytes else { throw AIError.responseTooLarge }
        textBytes += count
        text += addition
    }

    private func completeText() throws -> String {
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw AIError.emptyResponse }
        return result
    }
}
