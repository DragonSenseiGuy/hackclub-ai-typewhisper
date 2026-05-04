import Foundation

public struct HackClubChatMessage: Codable, Sendable {
    public let role: String
    public let content: String
    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct HackClubChatOptions: Sendable {
    public var temperature: Double?
    public var topP: Double?
    public var maxTokens: Int?
    public var stop: [String]?
    public init(temperature: Double? = nil, topP: Double? = nil, maxTokens: Int? = nil, stop: [String]? = nil) {
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.stop = stop
    }
}

public enum HackClubChatError: Error, LocalizedError {
    case invalidURL
    case http(Int, String)
    case decoding(String)
    case empty

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Hack Club AI URL"
        case .http(let code, let body): return "Hack Club AI HTTP \(code): \(body)"
        case .decoding(let msg): return "Decode error: \(msg)"
        case .empty: return "Hack Club AI returned no content"
        }
    }
}

public struct HackClubChatClient: Sendable {
    public static let baseURL = URL(string: "https://ai.hackclub.com")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func currentModel() async throws -> String {
        let url = Self.baseURL.appendingPathComponent("model")
        let (data, response) = try await session.data(from: url)
        try Self.checkStatus(response, data: data)
        guard let model = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !model.isEmpty else {
            throw HackClubChatError.empty
        }
        return model
    }

    public func complete(messages: [HackClubChatMessage], options: HackClubChatOptions = .init()) async throws -> String {
        let request = try buildRequest(messages: messages, options: options, stream: false)
        let (data, response) = try await sendWithRetry(request)
        try Self.checkStatus(response, data: data)
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
            throw HackClubChatError.empty
        }
        return text
    }

    public func stream(messages: [HackClubChatMessage], options: HackClubChatOptions = .init()) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildRequest(messages: messages, options: options, stream: true)
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw HackClubChatError.http(http.statusCode, "stream error")
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let payloadData = payload.data(using: .utf8) else { continue }
                        if let chunk = try? JSONDecoder().decode(ChatStreamChunk.self, from: payloadData),
                           let delta = chunk.choices.first?.delta.content, !delta.isEmpty {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func buildRequest(messages: [HackClubChatMessage], options: HackClubChatOptions, stream: Bool) throws -> URLRequest {
        let url = Self.baseURL.appendingPathComponent("chat").appendingPathComponent("completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": stream
        ]
        if let t = options.temperature { body["temperature"] = t }
        if let p = options.topP { body["top_p"] = p }
        if let m = options.maxTokens { body["max_tokens"] = m }
        if let s = options.stop { body["stop"] = s }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func sendWithRetry(_ request: URLRequest, attempts: Int = 3) async throws -> (Data, URLResponse) {
        var delay: UInt64 = 500_000_000
        var lastError: Error = HackClubChatError.empty
        for attempt in 0..<attempts {
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode >= 500, attempt < attempts - 1 {
                    try await Task.sleep(nanoseconds: delay)
                    delay *= 2
                    continue
                }
                return (data, response)
            } catch {
                lastError = error
                if attempt == attempts - 1 { throw error }
                try await Task.sleep(nanoseconds: delay)
                delay *= 2
            }
        }
        throw lastError
    }

    private static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw HackClubChatError.http(http.statusCode, body)
        }
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable { let message: HackClubChatMessage }
        let choices: [Choice]
    }

    private struct ChatStreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta
        }
        let choices: [Choice]
    }
}
