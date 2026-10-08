import LpxCore
import SwiftUI

/// The player at the bottom of the window: play / pause, the full file name, the waveform with a playhead (click or drag to
/// jump), times, and a way back to the project the playback was started from. It is its own strip of the window (it never
/// covers content) and appears only while something is loaded.
struct PlayerBar: View {
    @Environment(LibraryModel.self) private var model
    @Environment(AudioPlayerModel.self) private var player

    var body: some View {
        if player.isActive {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 30))
                    }
                    .buttonStyle(.plain)
                    .help(player.isPlaying ? "Pause" : "Play")

                    VStack(alignment: .leading, spacing: 2) {
                        // The whole file name, however long: it wraps instead of being cut off.
                        Text(player.title).font(.callout.weight(.medium)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if let project = player.projectPath {
                            Button { model.showProject(project) } label: {
                                Label(LibraryModel.projectName(project), systemImage: "arrow.uturn.backward").multilineTextAlignment(.leading)
                            }
                            .buttonStyle(.link).font(.caption).help("Show the project this was started from")
                        }
                    }
                    Spacer(minLength: 12)

                    Text("\(clock(player.time)) / \(clock(player.duration))").font(.callout.monospacedDigit()).foregroundStyle(.secondary)

                    Button { player.stop() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("Close the player")
                }

                WaveformView(peaks: player.peaks, progress: player.duration > 0 ? player.time / player.duration : 0) { player.seek(fraction: $0) }
                    .frame(height: 56)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private func clock(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}

/// Peaks drawn as bars, the played part in the accent colour, a playhead line; click or drag anywhere to jump there.
struct WaveformView: View {
    let peaks: [Float]?
    let progress: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let mid = size.height / 2
                if let peaks, !peaks.isEmpty {
                    let columns = max(1, Int(size.width / 3))           // 2 pt bars, 1 pt gap
                    for c in 0..<columns {
                        let lo = c * peaks.count / columns, hi = max(lo + 1, (c + 1) * peaks.count / columns)
                        let level = CGFloat(peaks[lo..<min(hi, peaks.count)].max() ?? 0)
                        let h = max(2, level * size.height)
                        let x = CGFloat(c) / CGFloat(columns) * size.width
                        let played = Double(c) / Double(columns) < progress
                        context.fill(Path(roundedRect: CGRect(x: x, y: mid - h / 2, width: 2, height: h), cornerRadius: 1),
                                     with: .color(played ? .accentColor : .secondary.opacity(0.55)))
                    }
                } else {
                    context.fill(Path(CGRect(x: 0, y: mid - 1, width: size.width, height: 2)), with: .color(.secondary.opacity(0.3)))
                }
                let x = size.width * CGFloat(min(max(progress, 0), 1))
                context.fill(Path(CGRect(x: x - 0.5, y: 0, width: 1.5, height: size.height)), with: .color(.primary))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                onSeek(Double(value.location.x / max(geo.size.width, 1)))
            })
            .overlay { if peaks == nil { ProgressView().controlSize(.small) } }
        }
    }
}
