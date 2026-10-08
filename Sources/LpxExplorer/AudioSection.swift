import AppKit
import LpxCore
import SwiftUI

/// Audio inventory for one project: hero player on top, then every bounce / recording / freeze file.
struct AudioSection: View {
    let bundlePath: String
    @State private var files: [AudioFile]?
    @Environment(AudioPlayerModel.self) private var player

    private var hero: AudioFile? { files.flatMap(AudioInventory.pickHero) }

    var body: some View {
        Section {
            if let files {
                if files.isEmpty {
                    Text("No audio files inside this project").foregroundStyle(.secondary)
                } else {
                    if let hero { heroPlayer(hero) }
                    ForEach(files, id: \.path) { f in row(f) }
                }
            } else {
                HStack { ProgressView().controlSize(.small); Text("Reading audio files…").foregroundStyle(.secondary) }
            }
            if let message = player.errorMessage { Text(message).font(.caption).foregroundStyle(.orange) }
        } header: {
            Text(files.map { "Audio files (\($0.count))" } ?? "Audio files")
        }
        .task(id: bundlePath) {
            files = nil
            let path = bundlePath
            files = await Task.detached(priority: .userInitiated) { AudioInventory.collect(bundle: URL(fileURLWithPath: path)) }.value
        }
    }

    private func heroPlayer(_ hero: AudioFile) -> some View {
        let isCurrent = player.currentPath == hero.path
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { player.toggle(hero, projectPath: bundlePath) } label: {
                    Image(systemName: isCurrent && player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.title)
                }.buttonStyle(.plain)
                VStack(alignment: .leading) {
                    Text(hero.fileName).fixedSize(horizontal: false, vertical: true)
                    Text("\(label(hero.category)) · best match for “what does this sound like?”").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(timeText(isCurrent ? player.time : 0, of: isCurrent ? player.duration : hero.durationSeconds))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if isCurrent {
                Slider(value: Binding(get: { player.time }, set: { player.seek(to: $0) }), in: 0...max(player.duration, 0.1))
            }
        }
    }

    private func row(_ f: AudioFile) -> some View {
        let isCurrent = player.currentPath == f.path
        return HStack {
            Button { player.toggle(f, projectPath: bundlePath) } label: {
                Image(systemName: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
            }.buttonStyle(.borderless)
            Image(systemName: symbol(f.category)).foregroundStyle(.secondary).frame(width: 18)
            Text(f.fileName).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text(f.durationSeconds.map { timeText(nil, of: $0) } ?? "—").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text(ByteCountFormatter.string(fromByteCount: Int64(f.sizeBytes), countStyle: .file))
                .font(.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
        }
        .contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f.path)]) }
        }
    }

    private func label(_ c: AudioCategory) -> String {
        switch c { case .bounce: "Bounce"; case .audioRegion: "Recording"; case .freezeFile: "Freeze file" }
    }

    private func symbol(_ c: AudioCategory) -> String {
        switch c { case .bounce: "music.note"; case .audioRegion: "waveform"; case .freezeFile: "snowflake" }
    }

    private func timeText(_ now: Double?, of total: Double?) -> String {
        func f(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
        switch (now, total) {
        case let (n?, t?): return "\(f(n)) / \(f(t))"
        case let (nil, t?): return f(t)
        case let (n?, nil): return f(n)
        default: return "—"
        }
    }
}
