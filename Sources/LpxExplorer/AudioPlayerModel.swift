import AVFoundation
import Foundation
import LpxCore
import Observation

/// The app's one audio player (read-only; AVAudioPlayer never writes). Whatever is playing shows in the bottom bar and
/// keeps playing while you browse; `projectPath` remembers which project it was started from.
@MainActor @Observable
final class AudioPlayerModel {
    private(set) var currentPath: String?
    private(set) var title = ""
    /// The project card the playback was started from ("Show project" jumps back to it).
    private(set) var projectPath: String?
    private(set) var isPlaying = false
    private(set) var time: Double = 0
    private(set) var duration: Double = 0
    /// Peak levels (0…1) for the waveform; nil while they are still being computed.
    private(set) var peaks: [Float]?
    private(set) var errorMessage: String?

    var isActive: Bool { currentPath != nil }

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var peaksTask: Task<Void, Never>?
    private var peaksFlag: CancelFlag?
    nonisolated static let waveformBins = 1500

    func toggle(_ file: AudioFile, projectPath: String? = nil) {
        toggle(path: file.path, title: file.fileName, projectPath: projectPath)
    }

    /// Start playing `path`, or pause/resume if it is already the current file.
    func toggle(path: String, title: String, projectPath: String?) {
        if currentPath == path, let player {
            if player.isPlaying { player.pause(); isPlaying = false } else { player.play(); isPlaying = true }
            return
        }
        stop()
        do {
            let p = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            p.prepareToPlay()
            p.play()
            player = p
            currentPath = path
            self.title = title
            self.projectPath = projectPath
            duration = p.duration
            isPlaying = true
            errorMessage = nil
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            loadPeaks(path)
        } catch {
            errorMessage = "Can't play \(title): \(error.localizedDescription)"
        }
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.isPlaying { player.pause(); isPlaying = false } else { player.play(); isPlaying = true }
    }

    func seek(to seconds: Double) {
        player?.currentTime = max(0, min(seconds, duration))
        time = player?.currentTime ?? 0
    }

    /// Seek to a position in the waveform, 0…1.
    func seek(fraction: Double) { seek(to: max(0, min(1, fraction)) * duration) }

    func stop() {
        timer?.invalidate(); timer = nil
        peaksTask?.cancel(); peaksTask = nil; peaksFlag?.set()
        player?.stop(); player = nil
        currentPath = nil; projectPath = nil; title = ""; isPlaying = false; time = 0; duration = 0; peaks = nil
    }

    private func loadPeaks(_ path: String) {
        peaks = nil
        peaksTask?.cancel(); peaksFlag?.set()
        let flag = CancelFlag()
        peaksFlag = flag
        peaksTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                WaveformPeaks.compute(url: URL(fileURLWithPath: path), bins: Self.waveformBins, isCancelled: { flag.isSet })
            }.value
            guard !Task.isCancelled, let self, self.currentPath == path else { return }
            self.peaks = result?.peaks ?? []
        }
    }

    private func tick() {
        guard let player else { return }
        time = player.currentTime
        if !player.isPlaying && isPlaying { isPlaying = false; time = 0; player.currentTime = 0 } // finished
    }
}
