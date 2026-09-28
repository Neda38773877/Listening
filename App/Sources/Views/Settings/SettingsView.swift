import SwiftUI
import SwiftData
import MeetingCore

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: AppSettings
    @State private var apiKey = ""
    @State private var showKeySaved = false
    @State private var keyVersion = 0
    @State private var showDeleteVocabConfirm = false
    @State private var showDeleteHistoryConfirm = false
    @State private var showDeleteMeetingsConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Playback") {
                    Picker("Default speed", selection: $settings.playbackRate) {
                        ForEach(PlaybackPlanner.speeds, id: \.self) { speed in
                            Text(String(format: "%g×", speed)).tag(speed)
                        }
                    }
                    Toggle("Show English", isOn: $settings.showEnglish)
                    Toggle("Show Persian", isOn: $settings.showPersian)
                }

                Section("Review") {
                    Stepper("New words per day: \(settings.newWordsPerDay)", value: $settings.newWordsPerDay, in: 0...50, step: 5)
                }

                Section("Shadowing defaults") {
                    Stepper("Listen passes: \(settings.shadowing.listenPasses)", value: $settings.shadowing.listenPasses, in: 1...3)
                    Toggle("Replay after pause", isOn: $settings.shadowing.replayAfterPause)
                    Toggle("Record after", isOn: $settings.shadowing.recordAfter)
                    Toggle("Auto-advance", isOn: $settings.shadowing.autoAdvance)

                    VStack(alignment: .leading) {
                        Text("Pause length ×\(String(format: "%.1f", settings.shadowing.pauseFactor))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.shadowing.pauseFactor, in: 1.0...2.5)
                    }
                }

                Section("Dictionary") {
                    NavigationLink("Custom dictionary", destination: CustomDictionaryView())
                }

                Section("Privacy & external AI") {
                    Text("Speech recognition, alignment, segmentation, Redemittel and vocabulary analysis run on this device. Nothing is uploaded unless you enable an external service below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Allow external AI (Claude)", isOn: $settings.externalAIEnabled)

                    if settings.externalAIEnabled {
                        VStack(spacing: 8) {
                            SecureField("Anthropic API key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                            HStack(spacing: 8) {
                                Button("Save") {
                                    Keychain.save(apiKey, for: "anthropicAPIKey")
                                    apiKey = ""
                                    showKeySaved = true
                                    keyVersion += 1
                                }
                                .disabled(apiKey.isEmpty)
                                if settings.hasAPIKey {
                                    Button("Remove key", role: .destructive) {
                                        Keychain.delete("anthropicAPIKey")
                                        keyVersion += 1
                                    }
                                }
                            }
                        }
                        .id(keyVersion)
                        if showKeySaved {
                            Text("Key saved")
                                .font(.caption)
                                .foregroundStyle(.green)
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        showKeySaved = false
                                    }
                                }
                        }
                        if settings.hasAPIKey {
                            Text("API key is saved in Keychain")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text("When used, only transcript text (never audio) is sent to Anthropic, and the app asks for permission per meeting. Results are labelled \"Claude (external)\".")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Forget per-meeting permissions") {
                            settings.revokeAllConsent()
                        }
                        .buttonStyle(.bordered)
                    }

                    Toggle("Allow Apple server speech recognition", isOn: $settings.allowServerRecognition)
                    Text("Only needed if on-device German recognition is unavailable. Audio is then sent to Apple for recognition.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Data") {
                    Button("Delete all vocabulary", role: .destructive) {
                        showDeleteVocabConfirm = true
                    }
                    Button("Delete learning history", role: .destructive) {
                        showDeleteHistoryConfirm = true
                    }
                    Button("Delete all meetings (audio, transcripts, analysis)", role: .destructive) {
                        showDeleteMeetingsConfirm = true
                    }
                    Text("Single meetings, their audio or transcript can be deleted from the meeting list (swipe).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                            Text(version)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Glossary seeded from your Hören-Trainer web glossary.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all vocabulary", isPresented: $showDeleteVocabConfirm) {
                Button("Delete", role: .destructive) {
                    let allItems = try? modelContext.fetch(FetchDescriptor<VocabItem>())
                    allItems?.forEach { modelContext.delete($0) }
                    try? modelContext.save()
                }
            } message: {
                Text("Are you sure you want to delete all vocabulary?")
            }
            .confirmationDialog("Delete learning history", isPresented: $showDeleteHistoryConfirm) {
                Button("Delete", role: .destructive) {
                    let allEvents = try? modelContext.fetch(FetchDescriptor<PracticeEvent>())
                    allEvents?.forEach { modelContext.delete($0) }
                    try? modelContext.save()
                }
            } message: {
                Text("Are you sure you want to delete all learning history?")
            }
            .confirmationDialog("Delete all meetings", isPresented: $showDeleteMeetingsConfirm) {
                Button("Delete", role: .destructive) {
                    MeetingStore.shared.deleteEverything()
                    let allRecords = try? modelContext.fetch(FetchDescriptor<MeetingRecord>())
                    allRecords?.forEach { modelContext.delete($0) }
                    try? modelContext.save()
                }
            } message: {
                Text("Are you sure you want to delete all meetings, including audio and transcripts? This cannot be undone.")
            }
        }
    }
}
