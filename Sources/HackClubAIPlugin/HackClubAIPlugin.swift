import Foundation
import SwiftUI
import TypeWhisperPluginSDK

public final class HackClubAIPlugin: NSObject, TypeWhisperPlugin, LLMProviderPlugin, TranscriptionEnginePlugin, @unchecked Sendable {
    public static let pluginId = "com.hackclub.typewhisper.hackclubai"
    public static let pluginName = "Hack Club AI"

    private let stateLock = NSLock()
    private var host: HostServices?
    private var cachedModelID: String = "hackclub-default"
    private var selectedTranscriptionModelID: String? = "openai/whisper"

    public override init() { super.init() }

    public func activate(host: HostServices) {
        stateLock.lock()
        self.host = host
        stateLock.unlock()
        Task { [weak self] in
            await self?.refreshChatModel()
        }
    }

    public func deactivate() {
        stateLock.lock()
        self.host = nil
        stateLock.unlock()
    }

    private func currentHost() -> HostServices? {
        stateLock.lock(); defer { stateLock.unlock() }
        return host
    }

    // MARK: - LLMProviderPlugin

    public var providerName: String { Self.pluginName }
    public var isAvailable: Bool { true }

    public var supportedModels: [PluginModelInfo] {
        stateLock.lock(); let id = cachedModelID; stateLock.unlock()
        return [PluginModelInfo(id: id, displayName: id, sizeDescription: "Hosted by Hack Club", languageCount: 0)]
    }

    public func process(systemPrompt: String, userText: String, model: String?) async throws -> String {
        let messages = [
            HackClubChatMessage(role: "system", content: systemPrompt),
            HackClubChatMessage(role: "user", content: userText)
        ]
        let client = HackClubChatClient()
        return try await client.complete(messages: messages, options: HackClubChatOptions(temperature: 0.3))
    }

    private func refreshChatModel() async {
        let client = HackClubChatClient()
        if let model = try? await client.currentModel() {
            stateLock.lock()
            cachedModelID = model
            stateLock.unlock()
            currentHost()?.notifyCapabilitiesChanged()
        }
    }

    // MARK: - TranscriptionEnginePlugin

    public var providerId: String { Self.pluginId + ".transcription" }
    public var providerDisplayName: String { Self.pluginName + " (Whisper via Replicate)" }

    public var isConfigured: Bool {
        guard let host = currentHost() else { return false }
        return (host.loadSecret(key: Self.replicateTokenKey)?.isEmpty == false)
    }

    public var transcriptionModels: [PluginModelInfo] {
        [PluginModelInfo(id: "openai/whisper", displayName: "openai/whisper (Replicate)", sizeDescription: "Cloud", languageCount: 99)]
    }

    public var selectedModelId: String? {
        stateLock.lock(); defer { stateLock.unlock() }
        return selectedTranscriptionModelID
    }

    public func selectModel(_ modelId: String) {
        stateLock.lock()
        selectedTranscriptionModelID = modelId
        stateLock.unlock()
    }

    public var supportsTranslation: Bool { true }

    public var supportedLanguages: [String] {
        ["en", "es", "fr", "de", "it", "pt", "nl", "ru", "zh", "ja", "ko", "ar", "hi", "tr", "pl", "sv", "no", "da", "fi", "cs", "el", "he", "id", "ms", "th", "uk", "vi"]
    }

    public func transcribe(audio: AudioData, language: String?, translate: Bool, prompt: String?) async throws -> PluginTranscriptionResult {
        guard let host = currentHost(), let token = host.loadSecret(key: Self.replicateTokenKey), !token.isEmpty else {
            throw PluginTranscriptionError.notConfigured
        }
        let client = HackClubReplicateClient(token: token)
        let options = HackClubReplicateOptions(language: language, translate: translate, initialPrompt: prompt)
        let text = try await client.transcribe(wavData: audio.wavData, options: options)
        return PluginTranscriptionResult(text: text, detectedLanguage: language)
    }

    // MARK: - Settings UI

    public var settingsView: AnyView? { AnyView(HackClubAISettingsView(plugin: self)) }

    static let replicateTokenKey = "replicateToken"

    func saveReplicateToken(_ token: String) {
        guard let host = currentHost() else { return }
        if token.isEmpty {
            try? host.storeSecret(key: Self.replicateTokenKey, value: "")
        } else {
            try? host.storeSecret(key: Self.replicateTokenKey, value: token)
        }
        host.notifyCapabilitiesChanged()
    }

    func hasReplicateToken() -> Bool { isConfigured }

    func testConnection() async -> String {
        var lines: [String] = []
        do {
            let model = try await HackClubChatClient().currentModel()
            lines.append("Chat: connected (\(model))")
        } catch {
            lines.append("Chat: failed — \(error.localizedDescription)")
        }
        lines.append(isConfigured ? "Transcription: Replicate token set" : "Transcription: no Replicate token")
        return lines.joined(separator: "\n")
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
                    plugin.saveReplicateToken(replicateToken)
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
