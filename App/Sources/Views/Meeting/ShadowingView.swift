import SwiftUI
import MeetingCore

struct ShadowingView: View {
    @ObservedObject var session: MeetingSession
    let startSentence: Int

    @State private var index: Int
    @State private var rate: Double
    @State private var machine: ShadowingMachine
    @State private var showTranslation = false
    @State private var pauseEnd: Date = Date()
    @State private var pauseTask: Task<Void, Never>?
    @State private var rounds = 0

    @ObservedObject private var player: AudioPlayer
    @ObservedObject private var recorder: VoiceRecorder

    @Environment(\.dismiss) var dismiss

    init(session: MeetingSession, startSentence: Int) {
        self.session = session
        self.startSentence = startSentence

        let count = session.doc.sentences.count
        let idx = min(max(0, startSentence), max(0, count - 1))
        let dur = session.clip(forSentence: idx)?.duration ?? 3
        let r = AppSettings.shared.playbackRate

        _index = State(initialValue: idx)
        _rate = State(initialValue: r)
        _machine = State(initialValue: ShadowingMachine(
            settings: AppSettings.shared.shadowing,
            sentenceDuration: dur,
            rate: r
        ))
        _player = ObservedObject(wrappedValue: session.player)
        _recorder = ObservedObject(wrappedValue: session.recorder)
    }

    var sentenceCount: Int { session.doc.sentences.count }
    var currentSentence: Sentence? {
        guard session.doc.sentences.indices.contains(index) else { return nil }
        return session.doc.sentences[index]
    }

    var body: some View {
        NavigationStack {
            if sentenceCount == 0 {
                VStack(spacing: 16) {
                    ContentUnavailableView("No sentences", systemImage: "text.alignleft")
                    Button("Done") { dismiss() }
                }
            } else if let currentSentence = currentSentence {
                VStack(spacing: 16) {
                    HStack {
                        Text("Sentence \(index + 1) of \(sentenceCount)")
                            .font(.headline)
                        Spacer()
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // German text
                            Text(session.doc.text(of: currentSentence))
                                .font(.system(size: 20, weight: .semibold, design: .serif))

                            // Translation toggle and display
                            if currentSentence.english != nil || currentSentence.persian != nil {
                                Toggle("Show translation", isOn: $showTranslation)

                                if showTranslation {
                                    VStack(alignment: .leading, spacing: 8) {
                                        if let e = currentSentence.english {
                                            Text(e.text)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let p = currentSentence.persian {
                                            Text(p.text)
                                                .environment(\.layoutDirection, .rightToLeft)
                                                .multilineTextAlignment(.trailing)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }

                            // Phase display
                            phasePanel
                        }
                        .padding()
                    }

                    // Control buttons
                    controlsBar
                }
                .navigationTitle("Shadowing")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .onAppear {
            session.loopSentence = nil
            react()
        }
        .onDisappear { cleanup() }
        .onChange(of: player.isPlaying) { old, new in
            if old && !new, case .listening = machine.phase {
                machine.playbackEnded()
                react()
            }
        }
    }

    private var phasePanel: some View {
        VStack(alignment: .center, spacing: 12) {
            switch machine.phase {
            case .idle:
                Text("Ready")
                    .font(.title3)
                    .foregroundStyle(.secondary)

            case .listening(let pass):
                VStack(spacing: 8) {
                    Text("Listen… (Pass \(pass))")
                        .font(.title3)
                    ProgressView()
                }

            case .repeating(let secs):
                VStack(spacing: 8) {
                    Text("Your turn — repeat aloud")
                        .font(.title3)
                    let now = Date()
                    ProgressView(timerInterval: now...max(now, pauseEnd), countsDown: true)
                }

            case .recording:
                VStack(spacing: 8) {
                    Text("Record yourself")
                        .font(.title3)
                    Button(role: .destructive, action: stopRecording) {
                        Label("Stop recording", systemImage: "stop.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

            case .comparing:
                VStack(spacing: 12) {
                    Text("Compare")
                        .font(.title3)
                    HStack(spacing: 12) {
                        Button(action: { session.playSentence(index, rate: rate) }) {
                            Label("Play original", systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)

                        Button(action: { recorder.playLast() }) {
                            Label("Play mine", systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)

                        Button(action: { machine.comparisonDone(); react() }) {
                            Label("Done", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

            case .finished:
                VStack(spacing: 12) {
                    Text("Round complete")
                        .font(.title3)
                    HStack(spacing: 12) {
                        Button("Repeat") {
                            resetMachine()
                        }
                        .buttonStyle(.bordered)

                        Button("Next") {
                            if index < sentenceCount - 1 {
                                index += 1
                                resetMachine()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(index >= sentenceCount - 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private var controlsBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Button(action: previousSentence) {
                    Label("Previous", systemImage: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(index == 0)

                Button(action: resetMachine) {
                    Label("Start/Restart", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button(action: replaySentence) {
                    Label("Replay", systemImage: "repeat")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button(action: nextSentence) {
                    Label("Next", systemImage: "chevron.right")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(index >= sentenceCount - 1)
            }

            HStack(spacing: 8) {
                if recorder.isRecording {
                    Button(action: stopRecordingManual) {
                        Label("Stop", systemImage: "stop.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: startRecordingManual) {
                        Label("Record", systemImage: "mic.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }

                if recorder.lastRecording != nil {
                    Button(action: { recorder.playLast() }) {
                        Label("Play my recording", systemImage: "play.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Text("Speed:")
                    .font(.caption)
                Picker("Speed", selection: $rate) {
                    ForEach(PlaybackPlanner.speeds, id: \.self) { speed in
                        Text(String(format: "%g×", speed)).tag(speed)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: rate) { _, newRate in
                    updateMachineRate(newRate)
                }
                Spacer()
            }

            DisclosureGroup("Settings") {
                VStack(spacing: 12) {
                    Stepper("Listen passes: \(AppSettings.shared.shadowing.listenPasses)", value: Binding(
                        get: { AppSettings.shared.shadowing.listenPasses },
                        set: { v in AppSettings.shared.shadowing.listenPasses = v; updateSettings() }
                    ), in: 1...3)

                    Toggle("Replay after pause", isOn: Binding(
                        get: { AppSettings.shared.shadowing.replayAfterPause },
                        set: { v in AppSettings.shared.shadowing.replayAfterPause = v; updateSettings() }
                    ))

                    Toggle("Record after", isOn: Binding(
                        get: { AppSettings.shared.shadowing.recordAfter },
                        set: { v in AppSettings.shared.shadowing.recordAfter = v; updateSettings() }
                    ))

                    Toggle("Auto-advance", isOn: Binding(
                        get: { AppSettings.shared.shadowing.autoAdvance },
                        set: { v in AppSettings.shared.shadowing.autoAdvance = v; updateSettings() }
                    ))
                }
                .font(.caption)
            }

            Text("Rounds this session: \(rounds)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func react() {
        switch machine.phase {
        case .idle:
            break

        case .listening:
            session.playSentence(index, rate: rate)

        case .repeating(let secs):
            pauseEnd = Date().addingTimeInterval(secs)
            pauseTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(secs * 1e9))
                if !Task.isCancelled {
                    machine.pauseEnded()
                    react()
                }
            }

        case .recording:
            Task { await recorder.start(into: session.store.recordingsFolder(session.doc.id)) }

        case .finished:
            rounds += 1
            session.log(.shadowing)
            if AppSettings.shared.shadowing.autoAdvance && index < sentenceCount - 1 {
                index += 1
                resetMachine()
            }

        case .comparing:
            break
        }
    }

    private func resetMachine() {
        pauseTask?.cancel()
        pauseTask = nil

        let dur = session.clip(forSentence: index)?.duration ?? 3
        machine = ShadowingMachine(
            settings: AppSettings.shared.shadowing,
            sentenceDuration: dur,
            rate: rate
        )
        machine.start()
        react()
    }

    private func updateMachineRate(_ newRate: Double) {
        var newMachine = machine
        newMachine.rate = newRate
        machine = newMachine
    }

    private func updateSettings() {
        var newMachine = machine
        newMachine.settings = AppSettings.shared.shadowing
        machine = newMachine
    }

    private func previousSentence() {
        if index > 0 {
            pauseTask?.cancel()
            pauseTask = nil
            player.pause()
            if recorder.isRecording { recorder.stop() }
            index -= 1
            resetMachine()
        }
    }

    private func nextSentence() {
        if index < sentenceCount - 1 {
            pauseTask?.cancel()
            pauseTask = nil
            player.pause()
            if recorder.isRecording { recorder.stop() }
            index += 1
            resetMachine()
        }
    }

    private func replaySentence() {
        session.playSentence(index, rate: rate)
    }

    private func startRecordingManual() {
        Task { await recorder.start(into: session.store.recordingsFolder(session.doc.id)) }
    }

    private func stopRecordingManual() {
        recorder.stop()
        session.log(.recording)
    }

    private func stopRecording() {
        recorder.stop()
        session.log(.recording)
        machine.recordingEnded()
        react()
    }

    private func cleanup() {
        pauseTask?.cancel()
        pauseTask = nil
        player.pause()
        if recorder.isRecording { recorder.stop() }
    }
}
