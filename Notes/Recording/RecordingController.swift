import AVFoundation
import Observation

/// Owns the microphone recording lifecycle with explicit states, so the UI
/// never claims to be recording when AVAudioRecorder isn't.
///
/// Recordings are written to Application Support/Drafts (not tmp) so an
/// unsent lecture survives a crash or the sheet being closed, and can be
/// recovered next time.
@MainActor
@Observable
final class RecordingController: NSObject, AVAudioRecorderDelegate {
    enum State: Equatable {
        case idle
        case recording
        case paused        // paused by the user
        case interrupted   // paused by the system (call, Siri, route loss)
        case finished(URL)
    }

    private(set) var state: State = .idle
    private(set) var duration: TimeInterval = 0
    var errorMessage: String?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// The draft file this controller created or restored; the only file it may delete.
    @ObservationIgnored private var ownedURL: URL?

    var isCapturing: Bool { state == .recording }

    var finishedURL: URL? {
        if case .finished(let url) = state { return url }
        return nil
    }

    /// True while there is recorded audio that hasn't been uploaded.
    var hasUnsavedAudio: Bool {
        switch state {
        case .idle: return false
        case .recording, .paused, .interrupted, .finished: return ownedURL != nil
        }
    }

    // MARK: - Drafts

    static var draftsDirectory: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Drafts", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        return dir
    }

    /// Most recent leftover draft large enough to contain real audio.
    static func recoverableDraft() -> URL? {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let files = (try? fm.contentsOfDirectory(at: draftsDirectory, includingPropertiesForKeys: keys)) ?? []
        return files
            .filter { $0.pathExtension == "m4a" }
            .filter { ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 4096 }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }
    }

    // MARK: - Control

    func start() {
        guard state == .idle else { return }
        errorMessage = nil
        AVAudioApplication.requestRecordPermission { allowed in
            Task { @MainActor in
                if allowed {
                    self.beginRecording()
                } else {
                    self.errorMessage = "Microphone access denied. Please enable it in Settings."
                }
            }
        }
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            errorMessage = "Audio session setup failed: \(error.localizedDescription)"
            return
        }

        let url = Self.draftsDirectory.appendingPathComponent("recording_\(Int(Date().timeIntervalSince1970)).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.delegate = self
            guard rec.record() else {
                errorMessage = "Couldn't start recording."
                try? FileManager.default.removeItem(at: url)
                return
            }
            recorder = rec
            ownedURL = url
            duration = 0
            state = .recording
            installObservers()
            startTimer()
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func pause() {
        guard state == .recording else { return }
        recorder?.pause()
        stopTimer()
        state = .paused
    }

    func resume() {
        guard state == .paused || state == .interrupted, let recorder else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            errorMessage = "Couldn't resume: \(error.localizedDescription)"
            return
        }
        // record() can fail (mic still held by a call); stay paused and say so.
        guard recorder.record() else {
            errorMessage = "Couldn't resume recording. Try again in a moment."
            return
        }
        errorMessage = nil
        state = .recording
        startTimer()
    }

    func stop() {
        guard let recorder, state == .recording || state == .paused || state == .interrupted else { return }
        duration = recorder.currentTime > 0 ? recorder.currentTime : duration
        recorder.stop() // delegate finalizes state
        finish()
    }

    private func finish() {
        stopTimer()
        removeObservers()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if let url = ownedURL, FileManager.default.fileExists(atPath: url.path) {
            state = .finished(url)
        } else {
            state = .idle
        }
    }

    /// Deletes the draft this controller owns and resets.
    func discard() {
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        stopTimer()
        removeObservers()
        if let url = ownedURL { try? FileManager.default.removeItem(at: url) }
        ownedURL = nil
        duration = 0
        errorMessage = nil
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Adopts a leftover draft from a previous session.
    func restore(draft url: URL) {
        guard state == .idle, url.deletingLastPathComponent().standardizedFileURL == Self.draftsDirectory.standardizedFileURL else { return }
        ownedURL = url
        duration = (try? AVAudioPlayer(contentsOf: url).duration) ?? 0
        state = .finished(url)
    }

    /// The upload has been staged in its own copy, so the draft can go.
    func uploadSucceeded() {
        if let url = ownedURL { try? FileManager.default.removeItem(at: url) }
        ownedURL = nil
        state = .idle
        duration = 0
    }

    /// Called when the view goes away. Stops (never deletes) an active
    /// recording so the audio stays available as a draft.
    func tearDown() {
        if state == .recording || state == .paused || state == .interrupted { stop() }
        removeObservers()
        stopTimer()
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let rec = self.recorder, self.state == .recording else { return }
                self.duration = rec.currentTime
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - System events

    private func installObservers() {
        removeObservers()
        let nc = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOpts = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated { self?.handleInterruption(rawType: rawType, rawOpts: rawOpts) }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            let rawReason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated { self?.handleRouteChange(rawReason: rawReason) }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.recorder != nil else { return }
                // The recorder is invalid after a reset; keep what was written.
                self.errorMessage = "Audio system was reset. Your recording so far was saved."
                self.recorder?.delegate = nil
                self.finish()
            }
        })
    }

    private func removeObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    private func handleInterruption(rawType: UInt?, rawOpts: UInt?) {
        guard let raw = rawType,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            guard state == .recording else { return }
            if let rec = recorder { duration = rec.currentTime }
            stopTimer()
            state = .interrupted
        case .ended:
            guard state == .interrupted else { return }
            let opts = AVAudioSession.InterruptionOptions(rawValue: rawOpts ?? 0)
            if opts.contains(.shouldResume) { resume() }
            // Otherwise stay interrupted; the user taps Resume.
        @unknown default:
            break
        }
    }

    private func handleRouteChange(rawReason: UInt?) {
        guard let raw = rawReason,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        // Headset/mic unplugged: pause rather than silently switching mics.
        if reason == .oldDeviceUnavailable, state == .recording {
            recorder?.pause()
            if let rec = recorder { duration = rec.currentTime }
            stopTimer()
            state = .interrupted
            errorMessage = "Microphone disconnected. Tap Resume to continue."
        }
    }

    // MARK: - AVAudioRecorderDelegate

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let message = error?.localizedDescription ?? "unknown error"
        Task { @MainActor in
            self.errorMessage = "Recording error: \(message). What was recorded so far was kept."
            self.finish()
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                self.errorMessage = "Recording ended unexpectedly. What was recorded so far was kept."
            }
            if self.recorder != nil { self.finish() }
        }
    }
}
