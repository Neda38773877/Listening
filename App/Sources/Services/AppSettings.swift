import Foundation
import Security
import MeetingCore

/// User preferences (UserDefaults) — nothing sensitive here; the API key is in the Keychain.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    /// Master switch for any external AI processing. Off by default.
    @Published var externalAIEnabled: Bool { didSet { d.set(externalAIEnabled, forKey: "externalAIEnabled") } }
    /// Allow Apple's servers for speech recognition when on-device German is unavailable.
    @Published var allowServerRecognition: Bool { didSet { d.set(allowServerRecognition, forKey: "allowServerRecognition") } }
    @Published var playbackRate: Double { didSet { d.set(playbackRate, forKey: "playbackRate") } }
    @Published var newWordsPerDay: Int { didSet { d.set(newWordsPerDay, forKey: "newWordsPerDay") } }
    @Published var showPersian: Bool { didSet { d.set(showPersian, forKey: "showPersian") } }
    @Published var showEnglish: Bool { didSet { d.set(showEnglish, forKey: "showEnglish") } }
    @Published var shadowing: ShadowingSettings {
        didSet { d.set(try? JSONEncoder().encode(shadowing), forKey: "shadowing") }
    }
    /// Meetings for which the user confirmed sending transcript text to the external AI.
    @Published private(set) var consentedMeetings: Set<String> {
        didSet { d.set(Array(consentedMeetings), forKey: "consentedMeetings") }
    }

    private init() {
        externalAIEnabled = d.bool(forKey: "externalAIEnabled")
        allowServerRecognition = d.bool(forKey: "allowServerRecognition")
        playbackRate = d.object(forKey: "playbackRate") as? Double ?? 1.0
        newWordsPerDay = d.object(forKey: "newWordsPerDay") as? Int ?? 15
        showPersian = d.object(forKey: "showPersian") as? Bool ?? true
        showEnglish = d.object(forKey: "showEnglish") as? Bool ?? true
        if let data = d.data(forKey: "shadowing"), let s = try? JSONDecoder().decode(ShadowingSettings.self, from: data) {
            shadowing = s
        } else {
            shadowing = ShadowingSettings()
        }
        consentedMeetings = Set(d.stringArray(forKey: "consentedMeetings") ?? [])
    }

    var hasAPIKey: Bool { !(Keychain.read("anthropicAPIKey") ?? "").isEmpty }

    func hasConsent(for meeting: UUID) -> Bool { consentedMeetings.contains(meeting.uuidString) }
    func grantConsent(for meeting: UUID) { consentedMeetings.insert(meeting.uuidString) }
    func revokeAllConsent() { consentedMeetings.removeAll() }
}

/// Minimal Keychain wrapper for the user's Anthropic API key.
enum Keychain {
    private static let service = "com.hoerentrainer.app"

    static func save(_ value: String, for key: String) {
        delete(key)
        guard !value.isEmpty else { return }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(q as CFDictionary)
    }
}
