import Foundation
import TypeWhisperPluginSDK

public struct HackClubReplicateOptions: Sendable {
    public var language: String?
    public var translate: Bool
    public var initialPrompt: String?
    public var modelVersion: String

    public static let defaultWhisperVersion = "8099696689d249cf8b122d833c36ac3f75505c666a395ca40ef26f68e7d3d16e"

    public init(language: String? = nil, translate: Bool = false, initialPrompt: String? = nil, modelVersion: String = Self.defaultWhisperVersion) {
        self.language = language
        self.translate = translate
        self.initialPrompt = initialPrompt
        self.modelVersion = modelVersion
    }
}

public enum HackClubReplicateError: Error, LocalizedError {
    case missingToken
    case http(Int, String)
    case predictionFailed(String)
    case timeout
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken: return "A Replicate API token is required for transcription. Set it in the Hack Club AI plugin settings."
        case .http(let code, let body): return "Replicate proxy HTTP \(code): \(body)"
        case .predictionFailed(let msg): return "Replicate prediction failed: \(msg)"
        case .timeout: return "Replicate prediction timed out"
        case .decoding(let msg): return "Decode error: \(msg)"
        }
    }
}

public struct HackClubReplicateClient: Sendable {
    public static let baseURL = URL(string: "https://ai.hackclub.com")!
    public static let pollIntervalNs: UInt64 = 1_000_000_000
    public static let timeoutSeconds: TimeInterval = 120

    let keychain: KeychainServicing
    let tokenKey: String
    private let session: URLSession

    public init(keychain: KeychainServicing, tokenKey: String, session: URLSession = .shared) {
        self.keychain = keychain
        self.tokenKey = tokenKey
        self.session = session
    }

    public func setToken(_ token: String?) throws {
        if let token, !token.isEmpty {
            try keychain.set(token, forKey: tokenKey)
        } else {
            try keychain.remove(forKey: tokenKey)
        }
    }

    public func hasToken() -> Bool {
        (try? keychain.get(forKey: tokenKey))?.isEmpty == false
    }

    public func transcribe(audio: Data, mimeType: String = "audio/wav", options: HackClubReplicateOptions = .init()) async throws -> String {
        guard let token = try? keychain.get(forKey: tokenKey), !token.isEmpty else {
            throw HackClubReplicateError.missingToken
        }
        let dataURL = "data:\(mimeType);base64,\(audio.base64EncodedString())"
        var input: [String: Any] = ["audio": dataURL]
        if let lang = options.language { input["language"] = lang }
        if options.translate { input["translate"] = true }
        if let prompt = options.initialPrompt, !prompt.isEmpty { input["initial_prompt"] = prompt }

        let body: [String: Any] = [
            "version": options.modelVersion,
            "input": input
        ]

        let createURL = Self.baseURL.appendingPathComponent("replicate").appendingPathComponent("predictions")
        var request = URLRequest(url: createURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (createData, createResponse) = try await session.data(for: request)
        try Self.checkStatus(createResponse, data: createData)
        let prediction = try JSONDecoder().decode(Prediction.self, from: createData)

        return try await poll(predictionID: prediction.id, token: token)
    }

    public func cancel(predictionID: String) async {
        guard let token = try? keychain.get(forKey: tokenKey), !token.isEmpty else { return }
        let url = Self.baseURL.appendingPathComponent("replicate").appendingPathComponent("predictions").appendingPathComponent(predictionID).appendingPathComponent("cancel")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: request)
    }

    private func poll(predictionID: String, token: String) async throws -> String {
        let url = Self.baseURL.appendingPathComponent("replicate").appendingPathComponent("predictions").appendingPathComponent(predictionID)
        let deadline = Date().addingTimeInterval(Self.timeoutSeconds)

        while Date() < deadline {
            try Task.checkCancellation()
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            try Self.checkStatus(response, data: data)
            let prediction = try JSONDecoder().decode(Prediction.self, from: data)
            switch prediction.status {
            case "succeeded":
                guard let text = prediction.output?.transcription, !text.isEmpty else {
                    throw HackClubReplicateError.predictionFailed("empty output")
                }
                return text
            case "failed", "canceled":
                throw HackClubReplicateError.predictionFailed(prediction.error ?? prediction.status)
            default:
                try await Task.sleep(nanoseconds: Self.pollIntervalNs)
            }
        }
        throw HackClubReplicateError.timeout
    }

    private static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw HackClubReplicateError.http(http.statusCode, body)
        }
    }

    private struct Prediction: Decodable {
        let id: String
        let status: String
        let error: String?
        let output: Output?

        struct Output: Decodable {
            let transcription: String?
        }
    }
}
