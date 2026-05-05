import Foundation
import SwiftUI
import TypeWhisperPluginSDK

@objc(HackClubAIPlugin)
final class HackClubAIPlugin: NSObject, LLMProviderPlugin {
    static let pluginId = "com.hackclub.typewhisper.hackclubai"
    static let pluginName = "Hack Club AI"

    private nonisolated(unsafe) var host: HostServices?
    private nonisolated(unsafe) var cachedModelID: String = "hackclub-default"

    let providerName = "Hack Club AI"
    var isAvailable: Bool { true }

    var supportedModels: [PluginModelInfo] {
        [PluginModelInfo(
            id: cachedModelID,
            displayName: cachedModelID,
            sizeDescription: "Hosted by Hack Club",
            languageCount: 0
        )]
    }

    override init() { super.init() }

    func activate(host: HostServices) {
        self.host = host
        Task { [weak self] in
            await self?.refreshChatModel()
        }
    }

    func deactivate() {
        host = nil
    }

    func process(systemPrompt: String, userText: String, model: String?) async throws -> String {
        let messages = [
            HackClubChatMessage(role: "system", content: systemPrompt),
            HackClubChatMessage(role: "user", content: userText)
        ]
        return try await HackClubChatClient().complete(
            messages: messages,
            options: HackClubChatOptions(temperature: 0.3)
        )
    }

    private func refreshChatModel() async {
        guard let model = try? await HackClubChatClient().currentModel() else { return }
        cachedModelID = model
        host?.notifyCapabilitiesChanged()
    }
}
