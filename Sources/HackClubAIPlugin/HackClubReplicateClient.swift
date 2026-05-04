import Foundation

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
    case http(Int, String)
    case predictionFailed(String)
    case timeout
    case decoding(String)

    public var errorDescription: String? {
        switch self {
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
    public static let timeoutSeconds: TimeInterval = 180

    let token: String
    private let session: URLSession

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    public func transcribe(wavData: Data, options: HackClubReplicateOptions = .init()) async throws -> String {
        let dataURL = "data:audio/wav;base64,\(wavData.base64EncodedString())"
        var input: [String: Any] = ["audio": dataURL]
        if let lang = options.language, !lang.isEmpty { input["language"] = lang }
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

        return try await poll(predictionID: prediction.id)
    }

    public func cancel(predictionID: String) async {
        let url = Self.baseURL
            .appendingPathComponent("replicate")
            .appendingPathComponent("predictions")
            .appendingPathComponent(predictionID)
            .appendingPathComponent("cancel")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: request)
    }

    private func poll(predictionID: String) async throws -> String {
        let url = Self.baseURL
            .appendingPathComponent("replicate")
            .appendingPathComponent("predictions")
            .appendingPathComponent(predictionID)
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
                if let text = prediction.output?.transcription, !text.isEmpty {
                    return text
                }
                if let plain = prediction.outputString, !plain.isEmpty {
                    return plain
                }
                throw HackClubReplicateError.predictionFailed("empty output")
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
        let outputString: String?

        enum CodingKeys: String, CodingKey { case id, status, error, output }

        struct Output: Decodable { let transcription: String? }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            status = try container.decode(String.self, forKey: .status)
            error = try? container.decodeIfPresent(String.self, forKey: .error)
            if let obj = try? container.decodeIfPresent(Output.self, forKey: .output) {
                output = obj
                outputString = nil
            } else if let str = try? container.decodeIfPresent(String.self, forKey: .output) {
                output = nil
                outputString = str
            } else {
                output = nil
                outputString = nil
            }
        }
    }
}
