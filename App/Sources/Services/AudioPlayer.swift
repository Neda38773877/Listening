import Foundation
import AVFoundation
import MediaPlayer
import MeetingCore

/// Plays the original meeting recording: whole file, a sentence, or a single word.
/// Speed changes keep the pitch natural (spectral time-stretching).
@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published var rate: Double = 1.0 {
        didSet { if isPlaying { player?.rate = Float(rate) } }
    }
    /// The clip being played, if playback is limited to a clip.
    @Published private(set) var activeClip: Clip?

    /// Called when a clip finishes (used by shadowing and repeat).
    var onClipFinished: (() -> Void)?
    /// Seconds of audio actually heard since the last `takeListenedSeconds()`.
    private var listened: Double = 0
    private var lastTick: Double?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var boundaryObserver: Any?
    private var endObserver: NSObjectProtocol?
    private(set) var url: URL?

    func load(_ url: URL, duration knownDuration: Double) {
        guard url != self.url else { return }
        unload()
        self.url = url
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .spectral
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = false
        player = p
        duration = knownDuration
        if knownDuration <= 0 {
            Task { [weak self] in
                let d = await ImportService.audioDuration(url)
                self?.duration = d
            }
        }
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(CMTimeGetSeconds(t)) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishClip() }
        }
        configureSession(recording: false)
        setupRemoteCommands()
    }

    func unload() {
        pause()
        if let o = timeObserver { player?.removeTimeObserver(o) }
        if let o = boundaryObserver { player?.removeTimeObserver(o) }
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        timeObserver = nil; boundaryObserver = nil; endObserver = nil
        player = nil
        url = nil
    }

    private func tick(_ t: Double) {
        guard t.isFinite else { return }
        if isPlaying, let last = lastTick, t > last, t - last < 1 { listened += t - last }
        lastTick = t
        currentTime = t
    }

    func takeListenedSeconds() -> Double {
        defer { listened = 0 }
        return listened
    }

    // MARK: Playback

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        guard let p = player else { return }
        activeClip = nil
        clearBoundary()
        p.playImmediately(atRate: Float(rate))
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
        lastTick = nil
    }

    func seek(to t: Double, thenPlay: Bool = false) {
        guard let p = player else { return }
        let target = CMTime(seconds: max(0, min(t, duration > 0 ? duration : t)), preferredTimescale: 600)
        p.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.currentTime = CMTimeGetSeconds(target)
                if thenPlay { self?.play() }
            }
        }
    }

    func skip(_ seconds: Double) { seek(to: currentTime + seconds, thenPlay: isPlaying) }

    /// Plays exactly the clip, then pauses (and calls `onClipFinished`).
    func play(_ clip: Clip, rate customRate: Double? = nil) {
        guard let p = player, clip.duration > 0 else { return }
        p.pause()
        clearBoundary()
        activeClip = clip
        let r = Float(customRate ?? rate)
        let end = CMTime(seconds: clip.end, preferredTimescale: 600)
        boundaryObserver = p.addBoundaryTimeObserver(forTimes: [NSValue(time: end)], queue: .main) { [weak self] in
            MainActor.assumeIsolated { self?.finishClip() }
        }
        p.seek(to: CMTime(seconds: clip.start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] done in
            guard done else { return }
            Task { @MainActor in
                guard let self, self.activeClip == clip else { return }
                p.playImmediately(atRate: r)
                self.isPlaying = true
            }
        }
    }

    private func finishClip() {
        guard activeClip != nil || isPlaying else { return }
        let wasClip = activeClip != nil
        pause()
        clearBoundary()
        activeClip = nil
        if wasClip { onClipFinished?() }
    }

    private func clearBoundary() {
        if let o = boundaryObserver { player?.removeTimeObserver(o) }
        boundaryObserver = nil
    }

    // MARK: Session / lock screen

    func configureSession(recording: Bool) {
        let s = AVAudioSession.sharedInstance()
        if recording {
            try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        } else {
            try? s.setCategory(.playback, mode: .spokenAudio)
        }
        try? s.setActive(true)
    }

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.removeTarget(nil)
        c.pauseCommand.removeTarget(nil)
        c.skipBackwardCommand.removeTarget(nil)
        c.skipForwardCommand.removeTarget(nil)
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.play() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        c.skipBackwardCommand.preferredIntervals = [5]
        c.skipForwardCommand.preferredIntervals = [5]
        c.skipBackwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(-5) }; return .success }
        c.skipForwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(5) }; return .success }
    }

    func updateNowPlaying(title: String) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0,
        ]
    }
}

/// Records the learner's voice for shadowing / speaking practice.
@MainActor
final class VoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var isPlaying = false
    @Published private(set) var lastRecording: URL?
    @Published var permissionDenied = false

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    var onPlaybackFinished: (() -> Void)?

    func requestPermission() async -> Bool {
        let ok = await AVAudioApplication.requestRecordPermission()
        permissionDenied = !ok
        return ok
    }

    func start(into folder: URL) async {
        guard await requestPermission() else { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? s.setActive(true)
        let url = folder.appendingPathComponent("rec-\(Int(Date().timeIntervalSince1970 * 1000)).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let r = try? AVAudioRecorder(url: url, settings: settings) else { return }
        r.delegate = self
        r.record()
        recorder = r
        isRecording = true
    }

    func stop() {
        recorder?.stop()
        if let url = recorder?.url { lastRecording = url }
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }

    func playLast() {
        guard let url = lastRecording, let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.delegate = self
        p.play()
        player = p
        isPlaying = true
    }

    func stopPlayback() {
        player?.stop()
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.onPlaybackFinished?()
        }
    }
}
