// Adapted from ChordCore/AIModelListRequest.swift; adds Anthropic pagination.
import Foundation

public struct AIListedModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String?
    public init(id: String, displayName: String? = nil) { self.id = id; self.displayName = displayName }
}

public struct AIModelPage: Equatable, Sendable {
    public let models: [AIListedModel]
    public let nextCursor: String?
    public init(models: [AIListedModel], nextCursor: String? = nil) { self.models = models; self.nextCursor = nextCursor }
}

enum AIModelListRequest {
    static let timeout: TimeInterval = 20
    static let maximumResponseBytes = 2 * 1024 * 1024
    static let maximumModels = 2000

    static func build(configuration: AIConfiguration, apiKey: String, afterID: String? = nil) throws -> URLRequest {
        let original = try configuration.validatedEndpoint()
        try AIRequestBuilder.validateKey(apiKey)
        // Model Studio's catalog is not an OpenAI list: it returns
        // output.models[].model with page_no/page_size. This kit supports its
        // generation endpoint; Qwen model selection is manual for this release.
        guard configuration.provider != .qwenChina, configuration.provider != .qwenInternational else { throw AIError.unsupportedEndpoint }
        guard var parts = URLComponents(url: original, resolvingAgainstBaseURL: false) else { throw AIError.unsupportedEndpoint }
        if let explicit = configuration.modelListEndpoint {
            var check = configuration
            check.endpoint = explicit
            let listURL = try check.validatedEndpoint()
            guard listURL.host?.lowercased() == original.host?.lowercased(), (listURL.port ?? 443) == (original.port ?? 443),
                  let listParts = URLComponents(url: listURL, resolvingAgainstBaseURL: false) else { throw AIError.unsupportedEndpoint }
            parts = listParts
        } else {
            // Qwen's documented model-list route is /api/v1/models, not the
            // compatible-mode generation prefix. Host must provide its regional
            // workspace route explicitly; manual model entry always remains valid.
            guard configuration.provider != .qwenChina, configuration.provider != .qwenInternational else { throw AIError.unsupportedEndpoint }
            let suffix: String
            switch configuration.apiProtocol {
            case .responses: suffix = "/responses"
            case .chatCompletions: suffix = "/chat/completions"
            case .anthropicMessages: suffix = "/messages"
            }
            var path = parts.percentEncodedPath
            if path.hasSuffix("/") { path.removeLast() }
            guard path.hasSuffix(suffix) else { throw AIError.unsupportedEndpoint }
            parts.percentEncodedPath = String(path.dropLast(suffix.count)) + "/models"
        }
        if let afterID {
            guard configuration.apiProtocol == .anthropicMessages, validID(afterID) else { throw AIError.unsupportedEndpoint }
            parts.queryItems = [URLQueryItem(name: "after_id", value: afterID)]
        }
        guard let url = parts.url, url.scheme == original.scheme, url.host == original.host, url.port == original.port else { throw AIError.unsupportedEndpoint }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        try AIRequestBuilder.authenticate(&request, configuration: configuration, apiKey: apiKey)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpShouldHandleCookies = false
        return request
    }

    static func parse(data: Data, configuration: AIConfiguration) throws -> AIModelPage {
        guard data.count <= maximumResponseBytes else { throw AIError.responseTooLarge }
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              body["error"] == nil || body["error"] is NSNull,
              let rows = body["data"] as? [[String: Any]] else { throw AIError.invalidResponse }
        guard rows.count <= maximumModels else { throw AIError.responseTooLarge }
        var seen = Set<String>()
        let models: [AIListedModel] = rows.compactMap { row in
            guard let id = row["id"] as? String, validID(id), seen.insert(id).inserted else { return nil }
            let name = (row["display_name"] as? String).flatMap { $0.utf8.count <= 256 && $0.rangeOfCharacter(from: .controlCharacters) == nil ? $0 : nil }
            return .init(id: id, displayName: name)
        }
        guard rows.isEmpty || !models.isEmpty else { throw AIError.invalidResponse }
        var nextCursor: String?
        if configuration.apiProtocol == .anthropicMessages, body["has_more"] as? Bool == true {
            guard let last = body["last_id"] as? String, validID(last) else { throw AIError.invalidResponse }
            nextCursor = last
        }
        return .init(models: models, nextCursor: nextCursor)
    }

    private static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && value.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil
    }
}
