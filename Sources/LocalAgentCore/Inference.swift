import Foundation
import MCP

public struct ToolCall: Codable, Sendable {
    public struct Function: Codable, Sendable {
        public let name: String
        public let arguments: String
    }
    public let id: String
    public let type: String
    public let function: Function
}
public struct ChatMessage: Codable, Sendable {
    public let role: String
    public let content: String?
    public let tool_calls: [ToolCall]?
    public let tool_call_id: String?
    public init(role: String, content: String?, toolCalls: [ToolCall]? = nil, toolCallID: String? = nil) {
        self.role = role; self.content = content; self.tool_calls = toolCalls; self.tool_call_id = toolCallID
    }
}
public struct FunctionTool: Encodable, Sendable {
    public struct Function: Encodable, Sendable {
        public let name: String
        public let description: String
        public let parameters: Value
    }
    public let type = "function"
    public let function: Function
}
public protocol InferenceClient: Sendable {
    func complete(messages: [ChatMessage], tools: [FunctionTool], model: ModelSpec, limits: RunLimits) async throws -> ChatMessage
}
final class RejectRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
public struct CompatibleInferenceClient: InferenceClient {
    private enum Target: Sendable { case configured(ProviderSpec), runtime(URL, key: String) }
    private let target: Target
    /// Configured `local`, `litellm` or `lan` provider. A `managed` provider must use `init(endpoint:)`.
    public init(provider: ProviderSpec) {
        target = .configured(provider)
    }
    /// App-owned runtime endpoint. The per-launch key is used only as a bearer header, never stored or logged.
    public init(endpoint: RuntimeEndpoint) {
        target = .runtime(endpoint.baseURL, key: endpoint.apiKey)
    }
    public func complete(messages: [ChatMessage], tools: [FunctionTool], model: ModelSpec, limits: RunLimits) async throws -> ChatMessage {
        try await completeMeasured(messages: messages, tools: tools, model: model, limits: limits).message
    }
    /// `complete` plus content-free usage/timing numbers when the server reports them (llama-server does).
    public func completeMeasured(messages: [ChatMessage], tools: [FunctionTool], model: ModelSpec,
                                 limits: RunLimits) async throws -> (message: ChatMessage, metrics: CompletionMetrics?) {
        struct Request: Encodable {
            let model: String
            let messages: [ChatMessage]
            let tools: [FunctionTool]?
            let max_tokens: Int
            let stream = false
            let parallel_tool_calls = false
        }
        struct Response: Decodable {
            struct Choice: Decodable { let message: ChatMessage; let finish_reason: String? }
            let choices: [Choice]
            let usage: CompletionMetrics.Usage?
            let timings: CompletionMetrics.Timings?
        }
        // Endpoint rules are re-checked before every request; a `lan` .local name is re-resolved here (ADR 0011).
        let baseURL: URL
        let bearer: String?
        switch target {
        case .configured(let provider):
            baseURL = try await provider.verifiedBaseURL()
            bearer = try ProviderCredential.bearer(account: provider.credentialAccount)
        case .runtime(let url, let key):
            try AgentConfiguration.validateEndpoint(url, local: true)
            baseURL = url; bearer = key
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(Request(model: model.model, messages: messages,
            tools: tools.isEmpty ? nil : tools, max_tokens: limits.outputTokens))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Double(limits.timeoutSeconds)
        configuration.timeoutIntervalForResource = Double(limits.timeoutSeconds)
        let session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AgentError.rejected("Inference request failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 262144 else { throw AgentError.rejected("Inference response exceeded the size limit.") }
            data.append(byte)
        }
        let result = try JSONDecoder().decode(Response.self, from: data)
        guard let choice = result.choices.first, choice.message.role == "assistant" else {
            throw AgentError.rejected("Provider returned an invalid assistant response.")
        }
        guard choice.finish_reason != "length" else {
            throw AgentError.rejected("The model reached the output limit. Try a smaller task.")
        }
        let metrics = result.usage == nil && result.timings == nil ? nil : CompletionMetrics(usage: result.usage, timings: result.timings)
        return (choice.message, metrics)
    }
}

/// Token counts and server-side timings. Numbers only; never content.
public struct CompletionMetrics: Codable, Sendable {
    public struct Usage: Codable, Sendable {
        public let prompt_tokens: Int?
        public let completion_tokens: Int?
    }
    /// llama-server extension to the OpenAI response.
    public struct Timings: Codable, Sendable {
        public let prompt_n: Int?
        public let prompt_ms: Double?
        public let prompt_per_second: Double?
        public let predicted_n: Int?
        public let predicted_ms: Double?
        public let predicted_per_second: Double?
    }
    public let usage: Usage?
    public let timings: Timings?
}

public enum ContextBudget {
    // UTF-8 byte count is deliberately conservative for supported byte-level tokenizers.
    // Includes framing allowance. Exact model/template token counting is a release gate.
    public static func validate(messages: [ChatMessage], tools: [FunctionTool], model: ModelSpec, limits: RunLimits) throws {
        let bytes = try JSONEncoder().encode(messages).count + JSONEncoder().encode(tools).count
        guard bytes + limits.outputTokens + 512 <= model.contextTokens else {
            throw AgentError.rejected("This task exceeds the context budget. Narrow the request or use fewer tools.")
        }
    }
}
