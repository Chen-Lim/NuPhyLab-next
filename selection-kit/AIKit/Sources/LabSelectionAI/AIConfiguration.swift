import Foundation

public enum AIProtocol: String, Codable, Sendable, CaseIterable {
    case responses, chatCompletions, anthropicMessages
}

/// These are endpoint presets, not statements about account access or model modalities.
/// There is deliberately no hard-coded default model.
public enum AIProvider: String, Codable, Sendable, CaseIterable {
    case openAI, anthropic, gemini, openRouter, groq, mistral, xAI, deepSeek
    case qwenChina, qwenInternational, custom

    public var endpoint: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1/responses"
        case .anthropic: return "https://api.anthropic.com/v1/messages"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .openRouter: return "https://openrouter.ai/api/v1/chat/completions"
        case .groq: return "https://api.groq.com/openai/v1/chat/completions"
        case .mistral: return "https://api.mistral.ai/v1/chat/completions"
        case .xAI: return "https://api.x.ai/v1/chat/completions"
        case .deepSeek: return "https://api.deepseek.com/chat/completions"
        case .qwenChina: return "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        case .qwenInternational: return "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions"
        case .custom: return ""
        }
    }

    public var apiProtocol: AIProtocol {
        switch self {
        case .openAI: return .responses
        case .anthropic: return .anthropicMessages
        default: return .chatCompletions
        }
    }
}

public struct AIConfiguration: Codable, Equatable, Sendable {
    public var provider: AIProvider
    /// A full request endpoint, not an SDK base URL. HTTPS only; no URL key/query/fragment.
    public var endpoint: String
    public var model: String
    public var apiProtocol: AIProtocol
    /// The host must establish that this exact selected model accepts images.
    /// A successful /models listing alone is not evidence of image capability.
    public var imageInputConfirmed: Bool
    public var maximumOutputTokens: Int
    /// Optional explicit same-origin model-list URL for an OpenAI-style or
    /// Anthropic-style catalog. Qwen's different catalog schema is not supported.
    public var modelListEndpoint: String?
    /// Anthropic non-workspace-scoped keys may require an explicit workspace.
    public var anthropicWorkspaceID: String?

    public init(provider: AIProvider = .openAI, endpoint: String? = nil, model: String = "",
                apiProtocol: AIProtocol? = nil, imageInputConfirmed: Bool = false,
                maximumOutputTokens: Int = 4096, modelListEndpoint: String? = nil,
                anthropicWorkspaceID: String? = nil) {
        self.provider = provider
        self.endpoint = endpoint ?? provider.endpoint
        self.model = model
        self.apiProtocol = apiProtocol ?? provider.apiProtocol
        self.imageInputConfirmed = imageInputConfirmed
        self.maximumOutputTokens = maximumOutputTokens
        self.modelListEndpoint = modelListEndpoint
        self.anthropicWorkspaceID = anthropicWorkspaceID
    }

    public func validatedEndpoint() throws -> URL {
        guard !endpoint.isEmpty, endpoint == endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
              endpoint.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              !endpoint.contains("\\"), !endpoint.contains("{"), !endpoint.contains("}"),
              let parts = URLComponents(string: endpoint), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true, let url = parts.url else {
            throw AIError.invalidEndpoint
        }
        return url
    }

    /// The host supplies its own Keychain service and uses this deterministic account.
    /// Changing provider, protocol, region, origin or path must select a different key.
    public func credentialAccount() throws -> String {
        let url = try validatedEndpoint()
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), let host = parts.host else {
            throw AIError.invalidEndpoint
        }
        return "\(provider.rawValue)|\(apiProtocol.rawValue)|https://\(host.lowercased()):\(parts.port ?? 443)\(parts.percentEncodedPath)|\(anthropicWorkspaceID ?? "")"
    }
}

/// Sanitized errors contain neither response bodies nor credentials.
public enum AIError: Error, LocalizedError, Equatable, Sendable {
    case invalidEndpoint, missingModel, missingKey, invalidKey, emptyInput, invalidOutputFormat
    case textTooLarge, imageTooLarge, invalidImage, imagesDisabled, tooManyImages, payloadTooLarge
    case invalidResponse, emptyResponse, responseTooLarge, incompleteResponse, refused
    case authentication, rateLimited, rejected(Int), serviceUnavailable, redirected
    case timedOut, cancelled, network, providerError, unsupportedEndpoint

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "Enter the full HTTPS API endpoint without URL credentials, query or fragment."
        case .missingModel: return "Select or enter a valid model ID supplied by your provider."
        case .missingKey: return "Provide the API key for this exact service and endpoint."
        case .invalidKey: return "The API key contains invalid characters or is too long."
        case .emptyInput: return "Provide a selection or a user instruction."
        case .invalidOutputFormat: return "The request options are invalid."
        case .textTooLarge: return "The text exceeds the local 128 KiB limit."
        case .imageTooLarge: return "An image exceeds the local 8 MiB limit."
        case .invalidImage: return "An image does not have the expected PNG header."
        case .imagesDisabled: return "Confirm image support for the exact model or remove the image."
        case .tooManyImages: return "Only one selected image is supported per request."
        case .payloadTooLarge: return "The request exceeds the local size limit."
        case .invalidResponse: return "The provider returned an unrecognized response."
        case .emptyResponse: return "The provider returned no answer text."
        case .responseTooLarge: return "The provider response exceeded the local size limit."
        case .incompleteResponse: return "The answer is incomplete or requires an unsupported tool operation."
        case .refused: return "The provider declined to return this result."
        case .authentication: return "The API key is invalid or lacks access to this endpoint or model."
        case .rateLimited: return "The provider reported a rate or quota limit. Retry manually when appropriate."
        case .rejected(let status): return "The provider rejected the request (HTTP \(status))."
        case .serviceUnavailable: return "The provider is temporarily unavailable."
        case .redirected: return "The API redirect was blocked to protect the API key."
        case .timedOut: return "The request timed out. The provider may already have processed or billed it."
        case .cancelled: return "The request was cancelled. The provider may already have processed or billed it."
        case .network: return "The provider could not be reached. There is no automatic retry."
        case .providerError: return "The provider reported a failed request. The raw body is not exposed."
        case .unsupportedEndpoint: return "A model-list endpoint cannot be derived safely. Enter a model ID manually."
        }
    }
}
