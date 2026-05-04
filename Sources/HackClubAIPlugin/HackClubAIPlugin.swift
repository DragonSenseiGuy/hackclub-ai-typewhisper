import Foundation
import SwiftUI
import TypeWhisperPluginSDK

@MainActor
public final class HackClubAIPlugin: NSObject, TypeWhisperPlugin, LLMProviderPlugin, TranscriptionEnginePlugin, DictionaryTermsCapabilityProviding, @unchecked Sendable {
    public static let pluginID = "com.hackclub.typewhisper.hackclubai"
    public static let displayName = "Hack Club AI"

    private let host: HostServices
    private let chat: HackClubChatClient
    private let replicate: HackClubReplicateClient
    private var cachedModel: String?

    public required init(host: HostServices) {
        self.host = host
        self.chat = HackClubChatClient()
        self.replicate = HackClubReplicateClient(keychain: host.keychain, tokenKey: "replicateToken")
        super.init()
    }

    // MARK: LLMProviderPlugin

    public func listModels() async throws -> [LLMModelDescriptor] {
        let model = try await chat.currentModel()
        cachedModel = model
        return [LLMModelDescriptor(id: model, displayName: model, supportsStreaming: true)]
    }

    public func complete(request: LLMCompletionRequest) async throws -> LLMCompletionResponse {
        let messages = mapMessages(request)
        let options = HackClubChatOptions(
            temperature: request.temperature,
            topP: request.topP,
            maxTokens: request.maxTokens,
            stop: request.stopSequences
        )
        let text = try await chat.complete(messages: messages, options: options)
        return LLMCompletionResponse(text: text, finishReason: .stop)
    }

    public func stream(request: LLMCompletionRequest) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        let messages = mapMessages(request)
        let options = HackClubChatOptions(
            temperature: request.temperature,
            topP: request.topP,
            maxTokens: request.maxTokens,
            stop: request.stopSequences
        )
        let upstream = chat.stream(messages: messages, options: options)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await delta in upstream {
                        continuation.yield(LLMStreamChunk(text: delta))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func mapMessages(_ request: LLMCompletionRequest) -> [HackClubChatMessage] {
        var messages: [HackClubChatMessage] = []
        if let dictionary = dictionarySystemPrompt() {
            messages.append(HackClubChatMessage(role: "system", content: dictionary))
        }
        for message in request.messages {
            let role: String
            switch message.role {
            case .system: role = "system"
            case .user: role = "user"
            case .assistant: role = "assistant"
            }
            messages.append(HackClubChatMessage(role: role, content: message.content))
        }
        return messages
    }

    private func dictionarySystemPrompt() -> String? {
        let terms = host.dictionaryTerms
        guard !terms.isEmpty else { return nil }
        return "Honor the user's preferred spellings for these terms: " + terms.joined(separator: ", ")
    }

    // MARK: TranscriptionEnginePlugin

    public func transcribe(request: TranscriptionRequest) async throws -> TranscriptionResult {
        let prompt = host.dictionaryTerms.isEmpty ? nil : host.dictionaryTerms.joined(separator: ", ")
        let options = HackClubReplicateOptions(
            language: request.languageCode,
            translate: false,
            initialPrompt: prompt
        )
        let text = try await replicate.transcribe(audio: request.audio, mimeType: request.mimeType ?? "audio/wav", options: options)
        return TranscriptionResult(text: text, language: request.languageCode)
    }

    // MARK: DictionaryTermsCapabilityProviding

    public var dictionaryTermsBudget: Int { 600 }

    // MARK: Settings UI

    public func makeSettingsView() -> AnyView {
        AnyView(HackClubAISettingsView(plugin: self))
    }

    func saveReplicateToken(_ token: String) throws {
        try replicate.setToken(token.isEmpty ? nil : token)
    }

    func hasReplicateToken() -> Bool {
        replicate.hasToken()
    }

    func testConnection() async -> String {
        do {
            let model = try await chat.currentModel()
            let chatStatus = "Chat: connected (\(model))"
            let replicateStatus = replicate.hasToken() ? "Transcription: token set" : "Transcription: no Replicate token"
            return "\(chatStatus)\n\(replicateStatus)"
        } catch {
            return "Chat: failed — \(error.localizedDescription)"
        }
    }
}

private struct HackClubAISettingsView: View {
    let plugin: HackClubAIPlugin
    @State private var replicateToken: String = ""
    @State private var statusMessage: String = ""
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("Chat (Hack Club AI)") {
                Text("No API key required. Chat completions go to https://ai.hackclub.com/chat/completions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Transcription (Replicate proxy)") {
                SecureField("Replicate API token", text: $replicateToken)
                Button("Save token") {
                    try? plugin.saveReplicateToken(replicateToken)
                    replicateToken = ""
                    statusMessage = plugin.hasReplicateToken() ? "Token saved." : "Token cleared."
                }
                Text("Tokens are stored in the macOS Keychain. The plugin posts predictions to https://ai.hackclub.com/replicate/predictions running openai/whisper.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button(isTesting ? "Testing…" : "Test connection") {
                    isTesting = true
                    Task {
                        let result = await plugin.testConnection()
                        await MainActor.run {
                            statusMessage = result
                            isTesting = false
                        }
                    }
                }
                .disabled(isTesting)
                if !statusMessage.isEmpty {
                    Text(statusMessage).font(.callout)
                }
            }
        }
        .padding()
    }
}
