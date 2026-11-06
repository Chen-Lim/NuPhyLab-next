import XCTest
@testable import LabSelectionAI

private final class FixtureProtocol: URLProtocol {
    struct Stub {
        var status = 200
        var mime = "text/event-stream"
        var chunks: [Data] = []
        var finish = true
    }
    private static let lock = NSLock()
    private static var value = Stub()
    private static var starts = 0
    private static var stops = 0
    static func configure(_ stub: Stub) {
        lock.lock();defer { lock.unlock() }
        value = stub;starts = 0;stops = 0
    }
    static var counts: (starts: Int, stops: Int) {
        lock.lock();defer { lock.unlock() }; return (starts, stops)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock();Self.starts += 1;let stub = Self.value;Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": stub.mime])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in stub.chunks { client?.urlProtocol(self, didLoad: chunk) }
        if stub.finish { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() { Self.lock.lock();Self.stops += 1;Self.lock.unlock() }
}

private actor Events {
    var texts: [String] = []
    func add(_ event: AIStreamingEvent) {
        if case .delta(let text, _) = event { texts.append(text) }
    }
}

final class TransportTests: XCTestCase {
    private let configuration = AIConfiguration(provider: .custom, endpoint: "https://fixture.invalid/v1/chat/completions", model: "fixture")
    private let stream = "data: {\"choices\":[{\"delta\":{\"content\":\"你好\"},\"finish_reason\":null}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"

    override func tearDown() { FixtureProtocol.configure(.init());super.tearDown() }

    func testStreamingThroughProductionTransportWithSingleByteChunks() async throws {
        FixtureProtocol.configure(.init(chunks: Data(stream.utf8).map { Data([$0]) }))
        let events = Events()
        let result = try await AIClient(protocolClasses: [FixtureProtocol.self]).sendStreaming(configuration: configuration, text: "Translate", apiKey: "fixture", onEvent: { await events.add($0) })
        XCTAssertEqual(result, "你好")
        let received = await events.texts
        XCTAssertEqual(received.joined(), "你好")
        XCTAssertEqual(FixtureProtocol.counts.starts, 1)
    }

    func testCompatibleJSONResponseDoesNotRetry() async throws {
        let json = #"{"choices":[{"message":{"role":"assistant","content":"Same response"},"finish_reason":"stop"}]}"#
        FixtureProtocol.configure(.init(mime: "application/json", chunks: [Data(json.utf8)]))
        let result = try await AIClient(protocolClasses: [FixtureProtocol.self]).sendStreaming(configuration: configuration, text: "Ask", apiKey: "fixture", onEvent: { _ in })
        XCTAssertEqual(result, "Same response")
        XCTAssertEqual(FixtureProtocol.counts.starts, 1)
    }

    func testNoRetryForRateLimitAndNoRawErrorBody() async {
        FixtureProtocol.configure(.init(status: 429, mime: "application/json", chunks: [Data("secret response body".utf8)]))
        do {
            _ = try await AIClient(protocolClasses: [FixtureProtocol.self]).sendStreaming(configuration: configuration, text: "Ask", apiKey: "fixture", onEvent: { _ in })
            XCTFail("Expected failure")
        } catch { XCTAssertEqual(error as? AIError, .rateLimited) }
        XCTAssertEqual(FixtureProtocol.counts.starts, 1)
    }

    func testCancellationStopsOutstandingRequest() async throws {
        FixtureProtocol.configure(.init(finish: false))
        let config = configuration
        let task = Task {
            try await AIClient(protocolClasses: [FixtureProtocol.self]).sendStreaming(configuration: config, text: "Ask", apiKey: "fixture", onEvent: { _ in })
        }
        for _ in 0..<100 where FixtureProtocol.counts.starts == 0 { try await Task.sleep(nanoseconds: 2_000_000) }
        task.cancel()
        do { _ = try await task.value;XCTFail("Expected cancellation") }
        catch { XCTAssertEqual(error as? AIError, .cancelled) }
        for _ in 0..<100 where FixtureProtocol.counts.stops == 0 { try await Task.sleep(nanoseconds: 2_000_000) }
        XCTAssertGreaterThan(FixtureProtocol.counts.stops, 0)
    }

    func testTimeoutIsBoundedAndDoesNotRetry() async {
        FixtureProtocol.configure(.init(finish: false))
        var limits = AIStreamingLimits();limits.deadline = 0.05;limits.idleTimeout = 0.05
        do {
            _ = try await AIClient(protocolClasses: [FixtureProtocol.self], streamingLimits: limits).sendStreaming(configuration: configuration, text: "Ask", apiKey: "fixture", onEvent: { _ in })
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual(error as? AIError, .timedOut) }
        XCTAssertEqual(FixtureProtocol.counts.starts, 1)
    }

    func testResponseBoundStopsExcessBytes() async {
        FixtureProtocol.configure(.init(chunks: [Data(repeating: 65, count: 101)]))
        var limits = AIStreamingLimits();limits.maximumBytes = 100
        do {
            _ = try await AIClient(protocolClasses: [FixtureProtocol.self], streamingLimits: limits).sendStreaming(configuration: configuration, text: "Ask", apiKey: "fixture", onEvent: { _ in })
            XCTFail("Expected size error")
        } catch { XCTAssertEqual(error as? AIError, .responseTooLarge) }
    }

    func testRedirectDelegateNeverForwardsCredentialRequest() async throws {
        let request = try AIRequestBuilder.build(configuration: configuration, prompt: .init(user: "Ask"), apiKey: "fixture")
        let transport = AIStreamingTransport(request: request, protocolClasses: [FixtureProtocol.self], limits: .init())
        defer { transport.stop() }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: request) // Not resumed; no real network.
        let redirect = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": "https://foreign.invalid/"])!
        transport.urlSession(session, task: task, willPerformHTTPRedirection: redirect, newRequest: URLRequest(url: URL(string: "https://foreign.invalid/")!)) { redirected in
            XCTAssertNil(redirected)
        }
        do { _ = try await transport.next();XCTFail("Expected redirect rejection") }
        catch { XCTAssertEqual(error as? AIError, .redirected) }
    }
}
