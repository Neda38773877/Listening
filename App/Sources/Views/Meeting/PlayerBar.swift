import SwiftUI
import MeetingCore

struct PlayerBar: View {
    @ObservedObject var session: MeetingSession
    @ObservedObject var player: AudioPlayer
    let compact: Bool
    var onShadowing: () -> Void

    @State private var scrubbing: Double?

    var body: some View {
        VStack(spacing: compact ? 4 : 8) {
            if !session.hasAudio {
                Label("No audio for this meeting", systemImage: "speaker.slash").font(.footnote).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Text(TimeFormat.short(scrubbing ?? player.currentTime)).font(.caption.monospacedDigit())
                    Slider(value: Binding(get: { scrubbing ?? player.currentTime }, set: { scrubbing = $0 }),
                           in: 0...max(player.duration, 1)) { editing in
                        if !editing, let t = scrubbing { player.seek(to: t, thenPlay: player.isPlaying); scrubbing = nil }
                    }
                    Text(TimeFormat.short(player.duration)).font(.caption.monospacedDigit())
                }
                HStack(spacing: compact ? 14 : 22) {
                    Button { session.step(-1) } label: { Image(systemName: "backward.end.fill") }
                        .accessibilityLabel("Previous sentence")
                    Button { player.skip(-5) } label: { Image(systemName: "gobackward.5") }
                    Button { session.togglePlay() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: compact ? 36 : 44))
                    }
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    Button { player.skip(5) } label: { Image(systemName: "goforward.5") }
                    Button { session.step(1) } label: { Image(systemName: "forward.end.fill") }
                        .accessibilityLabel("Next sentence")
                    Button {
                        if let i = session.currentSentenceIndex { session.playSentence(i) }
                    } label: { Image(systemName: "arrow.counterclockwise") }
                        .accessibilityLabel("Replay sentence")
                    Button {
                        if let i = session.currentSentenceIndex {
                            session.loopSentence = session.loopSentence == nil ? i : nil
                            if session.loopSentence != nil { session.playSentence(i) }
                        }
                    } label: { Image(systemName: session.loopSentence == nil ? "repeat" : "repeat.1") }
                        .accessibilityLabel("Repeat sentence")
                    speedMenu
                    if !compact {
                        Button(action: onShadowing) { Label("Shadowing", systemImage: "person.wave.2") }
                    }
                }
                .font(.title3)
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, compact ? 6 : 10)
        .background(.bar)
    }

    private var speedMenu: some View {
        Menu {
            ForEach(PlaybackPlanner.speeds, id: \.self) { r in
                Button { session.setRate(r) } label: {
                    if r == player.rate { Label(rateText(r), systemImage: "checkmark") } else { Text(rateText(r)) }
                }
            }
        } label: {
            Text(rateText(player.rate)).font(.callout.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().stroke(Color.secondary.opacity(0.5)))
        }
        .accessibilityLabel("Playback speed")
    }

    private func rateText(_ r: Double) -> String {
        r == r.rounded() ? "\(Int(r))×" : String(format: "%g×", r)
    }
}

/// Topic list; tapping a topic jumps the audio there.
struct MeetingTimelineView: View {
    @ObservedObject var session: MeetingSession
    var onSelect: (() -> Void)? = nil

    var body: some View {
        List {
            Section {
                ForEach(session.doc.topics) { t in
                    Button {
                        session.select(.sentence(t.firstSentence))
                        session.jump(toSentence: t.firstSentence)
                        onSelect?()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(range(t)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text(t.title).font(.subheadline).foregroundStyle(.primary)
                        }
                    }
                    .listRowBackground(isCurrent(t) ? Color.accentColor.opacity(0.1) : nil)
                }
            } header: {
                Text("Topics")
            } footer: {
                if session.doc.topics.contains(where: { $0.provenance == .automatic }) {
                    Text("Automatic sections: split at pauses and labelled with the most frequent words. For real topic titles use Meeting summary (external AI, optional).")
                } else if session.doc.topics.contains(where: { $0.provenance == .ai }) {
                    Text("Topics by Claude (external), checked against sentence numbers.")
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func isCurrent(_ t: Topic) -> Bool {
        guard let s = session.playingSentence else { return false }
        return s >= t.firstSentence && s <= t.lastSentence
    }

    private func range(_ t: Topic) -> String {
        let d = session.doc
        let a = d.sentences.indices.contains(t.firstSentence) ? d.timeRange(of: d.sentences[t.firstSentence])?.lowerBound : nil
        let b = d.sentences.indices.contains(t.lastSentence) ? d.timeRange(of: d.sentences[t.lastSentence])?.upperBound : nil
        return "\(a.map(TimeFormat.short) ?? "--")–\(b.map(TimeFormat.short) ?? "--")"
    }
}
