import AVFoundation
import Foundation
import LpxCore
import Observation

/// Plays one audio file from a bundle at a time (read-only; AVAudioPlayer never writes).
@MainActor @Observable
final class AudioPlayerModel {
    private(set) var currentPath: String?
    private(set) var isPlaying = false
    private(set) var time: Double = 0
    private(set) var duration: Double = 0
    private(set) var errorMessage: String?

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(_ file: AudioFile) {
        if currentPath == file.path, let player {
            if player.isPlaying { player.pause(); isPlaying = false } else { player.play(); isPlaying = true }
            return
        }
        stop()
        do {
            let p = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: file.path))
            p.prepareToPlay()
            p.play()
            player = p
            currentPath = file.path
            duration = p.duration
            isPlaying = true
            errorMessage = nil
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        } catch {
            errorMessage = "Can't play \(file.fileName): \(error.localizedDescription)"
        }
    }

    func seek(to seconds: Double) {
        player?.currentTime = max(0, min(seconds, duration))
        time = player?.currentTime ?? 0
    }

    func stop() {
        timer?.invalidate(); timer = nil
        player?.stop(); player = nil
        currentPath = nil; isPlaying = false; time = 0; duration = 0
    }

    private func tick() {
        guard let player else { return }
        time = player.currentTime
        if !player.isPlaying && isPlaying { isPlaying = false; time = 0; player.currentTime = 0 } // finished
    }
}
