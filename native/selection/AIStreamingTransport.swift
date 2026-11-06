// Adapted from Chord ChordCore/AIStreamingTransport.swift. See SOURCE-PROVENANCE.json.
import Foundation

struct AIStreamingLimits {
    var maximumBytes = AIRequestBuilder.maximumResponseBytes
    var maximumEventBytes = AIRequestBuilder.maximumResponseBytes
    var deadline: TimeInterval = AIRequestBuilder.timeout
    var idleTimeout: TimeInterval = AIRequestBuilder.timeout
}

enum AIStreamingChunk {
    case headers(HTTPURLResponse)
    case data(Data)
}

/// One explicitly started POST. A bounded, coalescing mailbox prevents a slow UI
/// callback from accumulating an unbounded queue of tiny network chunks. This
/// delegate never logs request/response content and never reconnects or retries.
final class AIStreamingTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private enum Delivery {
        case chunk(AIStreamingChunk?)
        case failure(AIError)
    }
    private let lock = NSLock()
    private let limits: AIStreamingLimits
    private let started: TimeInterval
    private var lastActivity: TimeInterval
    private var receivedBytes = 0
    private var headers: HTTPURLResponse?
    private var pendingData = Data()
    private var ended = false
    private var failure: AIError?
    private var waiter: CheckedContinuation<AIStreamingChunk?, Error>?
    private var session: URLSession!
    private var task: URLSessionDataTask!

    init(request: URLRequest, protocolClasses: [AnyClass]?, limits: AIStreamingLimits) {
        self.limits = limits
        started = ProcessInfo.processInfo.systemUptime
        lastActivity = started
        super.init()
        let configuration = AIClient.sessionConfiguration()
        configuration.timeoutIntervalForRequest = limits.idleTimeout
        configuration.timeoutIntervalForResource = limits.deadline
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        task = session.dataTask(with: request)
    }

    var elapsed: TimeInterval { max(0, ProcessInfo.processInfo.systemUptime - started) }

    func start() { task.resume() }

    func stop(_ error: AIError? = nil) {
        if let error { complete(error) }
        session.invalidateAndCancel()
    }

    func next() async throws -> AIStreamingChunk? {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            // Only the one stream-consumer task may read this mailbox.
            guard waiter == nil else {
                lock.unlock()
                continuation.resume(throwing: AIError.invalidResponse)
                return
            }
            waiter = continuation
            let ready = takeReadyLocked()
            lock.unlock()
            deliver(ready)
        }
    }

    func waitForTimeout() async throws -> String {
        while true {
            try Task.checkCancellation()
            let remaining = remainingTime()
            guard remaining > 0 else { throw AIError.timedOut }
            try await Task.sleep(nanoseconds: UInt64(min(remaining, 60) * 1_000_000_000))
        }
    }

    func checkTime() throws {
        guard remainingTime() > 0 else { throw AIError.timedOut }
    }

    private func remainingTime() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return min(started + limits.deadline, lastActivity + limits.idleTimeout) - ProcessInfo.processInfo.systemUptime
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        do {
            guard let response = response as? HTTPURLResponse else { throw AIError.invalidResponse }
            try AIRequestBuilder.validateStatus(response.statusCode)
            guard response.expectedContentLength <= limits.maximumBytes else { throw AIError.responseTooLarge }
            lock.lock()
            if ended { lock.unlock(); completionHandler(.cancel); return }
            headers = response
            lastActivity = ProcessInfo.processInfo.systemUptime
            let ready = takeReadyLocked()
            lock.unlock()
            deliver(ready)
            completionHandler(.allow)
        } catch {
            complete(error as? AIError ?? .invalidResponse)
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        if ended { lock.unlock(); return }
        guard data.count <= limits.maximumBytes - receivedBytes else {
            lock.unlock()
            complete(.responseTooLarge)
            dataTask.cancel()
            return
        }
        receivedBytes += data.count
        if !data.isEmpty { lastActivity = ProcessInfo.processInfo.systemUptime }
        pendingData.append(data)
        let ready = takeReadyLocked()
        lock.unlock()
        deliver(ready)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        complete(error.map(Self.sanitized))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Block even same-origin redirects; never forward Authorization to a new URL.
        complete(.redirected)
        completionHandler(nil)
    }

    private func complete(_ error: AIError?) {
        lock.lock()
        // The first transport failure wins, but cancellation may still invalidate
        // buffered bytes after the server has finished sending them.
        if failure == nil, let error { failure = error }
        ended = true
        if failure != nil { headers = nil; pendingData.removeAll() }
        let ready = takeReadyLocked()
        lock.unlock()
        deliver(ready)
    }

    private func takeReadyLocked() -> (CheckedContinuation<AIStreamingChunk?, Error>, Delivery)? {
        guard let continuation = waiter else { return nil }
        let value: Delivery
        if let failure { value = .failure(failure) }
        else if let headers { self.headers = nil; value = .chunk(.headers(headers)) }
        else if !pendingData.isEmpty {
            let data = pendingData
            pendingData = Data()
            value = .chunk(.data(data))
        } else if ended { value = .chunk(nil) }
        else { return nil }
        waiter = nil
        return (continuation, value)
    }

    private func deliver(_ ready: (CheckedContinuation<AIStreamingChunk?, Error>, Delivery)?) {
        guard let (continuation, delivery) = ready else { return }
        switch delivery {
        case .chunk(let chunk): continuation.resume(returning: chunk)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    static func sanitized(_ error: Error) -> AIError {
        if let error = error as? AIError { return error }
        if error is CancellationError { return .cancelled }
        if let error = error as? URLError {
            if error.code == .cancelled { return .cancelled }
            if error.code == .timedOut { return .timedOut }
        }
        return .network
    }
}
