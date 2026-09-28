import SwiftUI

extension View {
    /// Presents a consent alert for sending meeting text to Claude (external AI).
    /// - Parameters:
    ///   - isPresented: Binding to show/hide the alert
    ///   - meetingID: UUID of the meeting (used for per-meeting consent)
    ///   - purpose: What the text will be used for (e.g., "explain this word")
    ///   - onAllow: Closure called if user allows and API call should proceed
    func externalAIConsent(isPresented: Binding<Bool>, meetingID: UUID, purpose: String, onAllow: @escaping () -> Void) -> some View {
        alert("Send text to Claude?", isPresented: isPresented) {
            Button("Allow") {
                AppSettings.shared.grantConsent(for: meetingID)
                onAllow()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only text from this meeting (never the audio) is sent to Anthropic's API to \(purpose). Results are labelled \"Claude (external)\". Allow for this meeting?")
        }
    }
}

/// Button that either calls an action directly (if consent already granted) or first shows consent alert.
struct ExternalAIButton: View {
    let title: String
    let meetingID: UUID
    let purpose: String
    let action: () -> Void

    @EnvironmentObject var settings: AppSettings
    @State private var showConsent = false

    var body: some View {
        if !settings.externalAIEnabled || !settings.hasAPIKey {
            VStack(alignment: .leading, spacing: 4) {
                Button(action: {}) {
                    Label(title + " (external)", systemImage: "cloud")
                        .foregroundStyle(.secondary)
                }
                .disabled(true)
                Text("Enable external AI and add an API key in Settings to use this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Button(action: tapButton) {
                Label(title + " (external)", systemImage: "cloud")
            }
            .externalAIConsent(isPresented: $showConsent, meetingID: meetingID, purpose: purpose, onAllow: action)
        }
    }

    private func tapButton() {
        if settings.hasConsent(for: meetingID) {
            action()
        } else {
            showConsent = true
        }
    }
}
