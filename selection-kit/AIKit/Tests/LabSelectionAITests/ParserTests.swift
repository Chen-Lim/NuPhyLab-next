import XCTest
@testable import LabSelectionAI

final class ParserTests: XCTestCase {
    private func event(_ value: [String: Any], name: String = "message") throws -> AISSEEvent {
        .init(name: name, data: String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self))
    }
    private func json(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private func anthropicStart(_ parser: inout AIStreamingResponseParser) throws {
        _ = try parser.consume(event(["type": "message_start", "message": ["type": "message", "role": "assistant", "content": []]]))
        _ = try parser.consume(event(["type": "content_block_start", "index": 0, "content_block": ["type": "text", "text": ""]]))
    }

    func testSSEHandlesBOMCRLFCommentsMultilineAndSplitUnicode() throws {
        var parser = AISSEParser()
        let bytes = Data("\u{FEFF}: keepalive\r\nevent: sample\r\ndata: 中文\r\ndata: more\r\n\r\n".utf8)
        var events: [AISSEEvent] = []
        for byte in bytes { if let e = try parser.append(byte) { events.append(e) } }
        XCTAssertEqual(events, [.init(name: "sample", data: "中文\nmore")])
    }

    func testSSEBoundsAndInvalidUTF8() {
        var small = AISSEParser(maximumEventBytes: 4)
        XCTAssertThrowsError(try Data("data: long\n\n".utf8).forEach { _ = try small.append($0) }) { XCTAssertEqual($0 as? AIError, .responseTooLarge) }
        var invalid = AISSEParser()
        XCTAssertThrowsError(try [UInt8(0xFF), 10].forEach { _ = try invalid.append($0) }) { XCTAssertEqual($0 as? AIError, .invalidResponse) }
    }

    func testChatDeltasUsageAndRepeatedStop() throws {
        var parser = AIStreamingResponseParser(configuration: .init(provider: .openRouter))
        let first = try parser.consume(event(["choices": [["index": 0, "delta": ["role": "assistant", "content": "Hello", "tool_calls": NSNull()], "finish_reason": NSNull()]]]))
        XCTAssertEqual(first, ["Hello"])
        _ = try parser.consume(event(["choices": [["index": 0, "delta": ["content": " world"], "finish_reason": "stop"]]]))
        _ = try parser.consume(event(["choices": [["index": 0, "delta": [:], "finish_reason": "stop"]], "usage": ["total_tokens": 5]]))
        _ = try parser.consume(event(["choices": [], "usage": ["total_tokens": 5]]))
        _ = try parser.consume(.init(name: "message", data: "[DONE]"))
        XCTAssertEqual(try parser.finish(), "Hello world")
    }

    func testChatCannotSucceedWithoutStopOrWithTools() throws {
        var parser = AIStreamingResponseParser(configuration: .init(provider: .groq))
        _ = try parser.consume(event(["choices": [["delta": ["content": "partial"]]]]))
        XCTAssertThrowsError(try parser.finish()) { XCTAssertEqual($0 as? AIError, .incompleteResponse) }
        XCTAssertThrowsError(try parser.consume(.init(name: "message", data: "[DONE]"))) { XCTAssertEqual($0 as? AIError, .incompleteResponse) }
        for reason in ["length", "tool_calls"] {
            var p = AIStreamingResponseParser(configuration: .init(provider: .groq))
            XCTAssertThrowsError(try p.consume(event(["choices": [["delta": [:], "finish_reason": reason]]]))) { XCTAssertEqual($0 as? AIError, .incompleteResponse) }
        }
        var p = AIStreamingResponseParser(configuration: .init(provider: .groq))
        XCTAssertThrowsError(try p.consume(event(["choices": [["delta": ["tool_calls": [["id": "tool"]]]]]]))) { XCTAssertEqual($0 as? AIError, .incompleteResponse) }
    }

    func testResponsesUsesCanonicalCompletedAnswerAndNoDoubleDeltas() throws {
        var parser = AIStreamingResponseParser(configuration: .init(provider: .openAI))
        XCTAssertEqual(try parser.consume(event(["type": "response.output_text.delta", "delta": "Preview", "output_index": 0, "content_index": 0])), ["Preview"])
        let response: [String: Any] = ["status": "completed", "output": [["type": "message", "role": "assistant", "status": "completed", "content": [["type": "output_text", "text": "Canonical final"]]]]]
        XCTAssertEqual(try parser.consume(event(["type": "response.completed", "response": response])), [])
        XCTAssertEqual(try parser.finish(), "Canonical final")
    }

    func testResponsesTruncationRefusalAndToolOutputsFail() throws {
        var parser = AIStreamingResponseParser(configuration: .init(provider: .openAI))
        XCTAssertThrowsError(try parser.consume(event(["type": "response.incomplete"]))) { XCTAssertEqual($0 as? AIError, .incompleteResponse) }
        parser = .init(configuration: .init(provider: .openAI))
        XCTAssertThrowsError(try parser.consume(event(["type": "response.refusal.delta"]))) { XCTAssertEqual($0 as? AIError, .refused) }
        let body: [String: Any] = ["status": "completed", "output": [["type": "function_call", "name": "run"]]]
        XCTAssertThrowsError(try AIRequestBuilder.parse(data: json(body), configuration: .init(provider: .openAI))) { XCTAssertEqual($0 as? AIError, .incompleteResponse) }
    }

    func testAnthropicStreamNeedsBothStopReasonAndMessageStop() throws {
        var parser = AIStreamingResponseParser(configuration: .init(provider: .anthropic))
        try anthropicStart(&parser)
        XCTAssertEqual(try parser.consume(event(["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": "你好"]])), ["你好"])
        _ = try parser.consume(event(["type": "content_block_stop", "index": 0]))
        _ = try parser.consume(event(["type": "message_delta", "delta": ["stop_reason": "end_turn"]]))
        XCTAssertThrowsError(try parser.finish()) { XCTAssertEqual($0 as? AIError, .incompleteResponse) }
        _ = try parser.consume(event(["type": "message_stop"]))
        XCTAssertEqual(try parser.finish(), "你好")
    }

    func testAnthropicRefusalNewStopDetailsAndOldReason() throws {
        for delta: [String: Any] in [["stop_reason": "refusal"], ["stop_reason": "end_turn", "stop_details": ["type": "refusal"]]] {
            var parser = AIStreamingResponseParser(configuration: .init(provider: .anthropic))
            try anthropicStart(&parser)
            _ = try parser.consume(event(["type": "content_block_stop", "index": 0]))
            XCTAssertThrowsError(try parser.consume(event(["type": "message_delta", "delta": delta]))) { XCTAssertEqual($0 as? AIError, .refused) }
        }
    }

    func testAnthropicRejectsToolAndUnclosedBlocks() throws {
        var parser = AIStreamingResponseParser(configuration: .init(provider: .anthropic))
        try anthropicStart(&parser)
        XCTAssertThrowsError(try parser.consume(event(["type": "content_block_start", "index": 1, "content_block": ["type": "tool_use"]]))) { XCTAssertEqual($0 as? AIError, .incompleteResponse) }
        XCTAssertThrowsError(try parser.consume(event(["type": "message_delta", "delta": ["stop_reason": "end_turn"]]))) { XCTAssertEqual($0 as? AIError, .invalidResponse) }
    }

    func testAnthropicJSONOnlyAcceptsCompletedText() throws {
        var body: [String: Any] = ["type": "message", "role": "assistant", "stop_reason": "end_turn", "content": [["type": "text", "text": "Answer"]]]
        XCTAssertEqual(try AIRequestBuilder.parse(data: json(body), configuration: .init(provider: .anthropic)), "Answer")
        for reason in ["max_tokens", "pause_turn", "tool_use"] {
            body["stop_reason"] = reason
            XCTAssertThrowsError(try AIRequestBuilder.parse(data: json(body), configuration: .init(provider: .anthropic))) { XCTAssertEqual($0 as? AIError, .incompleteResponse) }
        }
        body["stop_reason"] = "end_turn";body["stop_details"] = ["type": "refusal"]
        XCTAssertThrowsError(try AIRequestBuilder.parse(data: json(body), configuration: .init(provider: .anthropic))) { XCTAssertEqual($0 as? AIError, .refused) }
    }

    func testMidstreamErrorIsSanitized() throws {
        var parser = AIStreamingResponseParser(configuration: .init(provider: .openRouter))
        XCTAssertThrowsError(try parser.consume(event(["error": ["message": "secret raw provider body"]]))) {
            XCTAssertEqual($0 as? AIError, .providerError)
            XCTAssertFalse($0.localizedDescription.contains("secret"))
        }
    }

    func testMistralMixedThinkingTextChunksExposeOnlyAnswer() throws {
        var parser = AIStreamingResponseParser(configuration: .init(provider: .mistral))
        let chunks: [[String: Any]] = [["type": "thinking", "thinking": [["type": "text", "text": "hidden reasoning"]]], ["type": "text", "text": "Answer"]]
        XCTAssertEqual(try parser.consume(event(["choices": [["delta": ["content": chunks], "finish_reason": "stop"]]])), ["Answer"])
        _ = try parser.consume(.init(name: "message", data: "[DONE]"))
        XCTAssertEqual(try parser.finish(), "Answer")
        let value: [String: Any] = ["choices": [["message": ["role": "assistant", "content": chunks], "finish_reason": "stop"]]]
        XCTAssertEqual(try AIRequestBuilder.parse(data: json(value), configuration: .init(provider: .mistral)), "Answer")
    }
}
