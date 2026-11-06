// Adapted from Chord ChordCore/AIClient.swift. See SOURCE-PROVENANCE.json.
import Foundation

/// A single explicit request with no history, application retries, cookies, or disk cache.
/// Cancelling the calling Task cancels the request; this cannot undo provider processing/billing.
public struct AIClient {
    private let protocolClasses: [AnyClass]?
    private let streamingLimits: AIStreamingLimits
    public init() { protocolClasses = nil; streamingLimits = AIStreamingLimits() }
    // Internal seam for deterministic tests; production callers cannot replace transport.
    init(protocolClasses: [AnyClass], streamingLimits: AIStreamingLimits = AIStreamingLimits()) {
        self.protocolClasses = protocolClasses; self.streamingLimits = streamingLimits
    }

    public func send(configuration: AIConfiguration, text: String, imagePNG: Data?, apiKey: String) async throws -> String {
        try await send(configuration: configuration, text: text, images: imagePNG.map { [AIImageAttachment(label: "", png: $0)] } ?? [], apiKey: apiKey)
    }

    public func send(configuration: AIConfiguration, text: String, images: [AIImageAttachment], apiKey: String) async throws -> String {
        try await send(configuration: configuration, prompt: .interaction(user: text), images: images, apiKey: apiKey)
    }

    public func send(configuration: AIConfiguration, prompt: AIRequestPrompt, images: [AIImageAttachment] = [], apiKey: String) async throws -> String {
        let request = try AIRequestBuilder.build(configuration: configuration, prompt: prompt, images: images, apiKey: apiKey)
        let data = try await receive(request, maximumBytes: AIRequestBuilder.maximumResponseBytes, timeout: AIRequestBuilder.timeout)
        return try AIRequestBuilder.parse(data: data, configuration: configuration)
    }

    public func sendStreaming(configuration: AIConfiguration, text: String, images: [AIImageAttachment] = [], apiKey: String, onEvent: @escaping @Sendable (AIStreamingEvent) async -> Void) async throws -> String {
        try await sendStreaming(configuration: configuration, prompt: .interaction(user: text), images: images, apiKey: apiKey, onEvent: onEvent)
    }

    /// Ordinary text interactions only. Events are serial, awaited and checked for
    /// cancellation on both sides of every callback. Callbacks should be brief and
    /// must check their captured session ID before changing UI after an actor hop.
    /// Only the returned string is complete; partial deltas may precede an error.
    public func sendStreaming(configuration: AIConfiguration, prompt: AIRequestPrompt, images: [AIImageAttachment] = [], apiKey: String, onEvent: @escaping @Sendable (AIStreamingEvent) async -> Void) async throws -> String {
        if Task.isCancelled { throw AIError.cancelled }
        let request = try AIRequestBuilder.build(configuration: configuration, prompt: prompt, images: images, apiKey: apiKey, stream: true)
        let transport = AIStreamingTransport(request: request, protocolClasses: protocolClasses, limits: streamingLimits)
        defer { transport.stop() }
        do {
            return try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: String.self) { group in
                    defer { group.cancelAll() }
                    group.addTask { try await transport.waitForTimeout() }
                    group.addTask {
                        try await withTaskCancellationHandler {
                            try Task.checkCancellation()
                            transport.start()
                            return try await Self.readStream(transport, configuration: configuration, limits: streamingLimits, onEvent: onEvent)
                        } onCancel: { transport.stop(.cancelled) }
                    }
                    guard let result = try await group.next() else { throw AIError.invalidResponse }
                    try Task.checkCancellation()
                    return result
                }
            } onCancel: { transport.stop(.cancelled) }
        } catch {
            if Task.isCancelled { throw AIError.cancelled }
            throw AIStreamingTransport.sanitized(error)
        }
    }

    private static func readStream(_ transport: AIStreamingTransport, configuration: AIConfiguration, limits: AIStreamingLimits, onEvent: @Sendable (AIStreamingEvent) async -> Void) async throws -> String {
        var format: AIStreamingFormat?
        var json = Data()
        var sse = AISSEParser(maximumEventBytes: limits.maximumEventBytes)
        var parser = AIStreamingResponseParser(configuration: configuration, maximumTextBytes: limits.maximumBytes)
        var sentFirstText = false
        func notify(_ event: AIStreamingEvent) async throws {
            try Task.checkCancellation()
            try transport.checkTime()
            await onEvent(event)
            try Task.checkCancellation()
            try transport.checkTime()
        }
        func emit(_ texts: [String]) async throws {
            for text in texts where !text.isEmpty {
                if !sentFirstText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sentFirstText = true
                    try await notify(.firstText(elapsed: transport.elapsed))
                }
                try await notify(.delta(text: text, elapsed: transport.elapsed))
            }
        }
        while let chunk = try await transport.next() {
            try Task.checkCancellation()
            try transport.checkTime()
            switch chunk {
            case .headers(let response):
                guard format == nil else { throw AIError.invalidResponse }
                let mime = response.mimeType?.lowercased() ?? ""
                if mime == "text/event-stream" { format = .serverSentEvents }
                else if mime == "application/json" || mime.hasSuffix("+json") || mime.isEmpty { format = .json }
                else { throw AIError.invalidResponse }
                try await notify(.headers(elapsed: transport.elapsed, format: format!))
            case .data(let data):
                guard let format else { throw AIError.invalidResponse }
                if format == .json { json.append(data); continue }
                for byte in data {
                    try Task.checkCancellation()
                    if let event = try sse.append(byte) {
                        try await emit(parser.consume(event))
                        if let result = parser.result { return result }
                    }
                }
            }
        }
        try Task.checkCancellation()
        try transport.checkTime()
        guard let format else { throw AIError.invalidResponse }
        if format == .serverSentEvents { return try parser.finish() }
        // A compatible server may return JSON to this same request. Never resend
        // with stream=false, including after unsupported-stream HTTP errors.
        let result = try AIRequestBuilder.parse(data: json, configuration: configuration)
        try await emit([result])
        return result
    }

    /// Lists one explicit page. The host can request nextCursor for Anthropic;
    /// model IDs do not establish modalities, entitlement, pricing or region access.
    public func listModels(configuration: AIConfiguration, apiKey: String, afterID: String? = nil) async throws -> AIModelPage {
        let request = try AIModelListRequest.build(configuration: configuration, apiKey: apiKey, afterID: afterID)
        let data = try await receive(request, maximumBytes: AIModelListRequest.maximumResponseBytes, timeout: AIModelListRequest.timeout)
        let result = try AIModelListRequest.parse(data: data, configuration: configuration)
        if Task.isCancelled { throw AIError.cancelled }
        return result
    }

    public func listModelCatalog(configuration: AIConfiguration, apiKey: String) async throws -> AIModelPage {
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        var catalog = AIModelCatalog()
        repeat {
            try Task.checkCancellation()
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw AIError.timedOut }
            var request = try AIModelListRequest.build(configuration:configuration,apiKey:apiKey,afterID:catalog.nextCursor)
            request.timeoutInterval = min(AIModelListRequest.timeout,remaining)
            let data = try await receive(request,maximumBytes:AIModelListRequest.maximumResponseBytes,timeout:request.timeoutInterval)
            try catalog.append(AIModelListRequest.parse(data:data,configuration:configuration))
        } while catalog.canContinue
        try Task.checkCancellation()
        return .init(models:catalog.models,nextCursor:catalog.nextCursor)
    }

    private func receive(_ request: URLRequest, maximumBytes: Int, timeout: TimeInterval) async throws -> Data {
        let transport = Self.sessionConfiguration()
        transport.timeoutIntervalForRequest = timeout
        transport.timeoutIntervalForResource = timeout
        if let protocolClasses { transport.protocolClasses = protocolClasses }
        let session = URLSession(configuration: transport, delegate: AIRedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
            // Inspect only status. Error bodies can contain user text or secrets and are never read.
            try AIRequestBuilder.validateStatus(http.statusCode)
            guard response.expectedContentLength <= maximumBytes else { throw AIError.responseTooLarge }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < maximumBytes else { throw AIError.responseTooLarge }
                data.append(byte)
            }
            try Task.checkCancellation()
            return data
        } catch is CancellationError {
            throw AIError.cancelled
        } catch let error as AIError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw AIError.cancelled
            case .timedOut: throw AIError.timedOut
            default: throw AIError.network
            }
        } catch {
            throw AIError.network
        }
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = AIRequestBuilder.timeout
        configuration.timeoutIntervalForResource = AIRequestBuilder.timeout
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return configuration
    }
}

final class AIRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Even a same-host redirect can change trust boundaries. Never forward credentials.
        completionHandler(nil)
    }
}
