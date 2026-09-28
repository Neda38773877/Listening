import SwiftUI
import MeetingCore

/// Manages audio playback of word clips from meetings.
@MainActor final class ClipPlayer: ObservableObject {
    let player = AudioPlayer()
    private var loadedMeeting: UUID?

    /// Loads a meeting's audio if needed and plays the specified clip.
    @discardableResult
    func play(meetingID: UUID, clip: Clip, rate: Double = 1) -> Bool {
        if loadedMeeting != meetingID {
            guard let doc = MeetingStore.shared.load(meetingID),
                  let url = MeetingStore.shared.audioURL(for: doc) else {
                return false
            }
            player.load(url, duration: doc.duration)
            loadedMeeting = meetingID
        }
        player.play(clip, rate: rate)
        return true
    }

    /// Plays a vocabulary item's audio clip if available.
    @discardableResult
    func play(item: VocabItem, rate: Double = 1) -> Bool {
        guard let meetingID = item.meetingID,
              let clipStart = item.clipStart,
              let clipEnd = item.clipEnd else {
            return false
        }
        let clip = Clip(start: clipStart, end: clipEnd)
        return play(meetingID: meetingID, clip: clip, rate: rate)
    }

    /// Stops audio playback.
    func stop() {
        player.pause()
    }
}
