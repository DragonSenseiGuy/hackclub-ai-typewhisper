import Foundation
import SwiftUI
import TypeWhisperPluginSDK

public final class HackClubAIPlugin: NSObject, @unchecked Sendable {
    public static let pluginID = "com.hackclub.typewhisper.hackclubai"

    private let host: HostServices
    private let chat: HackClubChatClient
    private let replicate: HackClubReplicateClient

    public required init(host: HostServices) {
        self.host = host
        self.chat = HackClubChatClient()
        self.replicate = HackClubReplicateClient(keychain: host.keychain, tokenKey: "replicateToken")
        super.init()
    }
}
