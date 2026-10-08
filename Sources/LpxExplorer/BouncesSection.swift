import AppKit
import LpxCore
import SwiftUI

/// The project's bounces: the mix is the prominent line, its stems follow. Clicking one starts it in the bottom player.
struct BouncesSection: View {
    @Environment(LibraryModel.self) private var model
    @Environment(AudioPlayerModel.self) private var player
    let projectPath: String
    /// Files that still exist (the cached list is confirmed against the disk when the section appears).
    @State private var existing: [BounceFile]?

    private var files: [BounceFile] { existing ?? model.bounces[projectPath] ?? [] }
    private var mixes: [BounceFile] { files.filter { $0.kind == .mix } }
    private var stems: [BounceFile] { files.filter { $0.kind == .stem } }

    var body: some View {
        Section {
            if files.isEmpty {
                Text("No bounce found for this project's name in a Bounces folder next to it or inside it.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(mixes.enumerated()), id: \.element.path) { index, file in
                mixRow(file, primary: index == 0)
            }
            if !stems.isEmpty {
                Text("Stems (\(stems.count))").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                ForEach(stems, id: \.path) { stemRow($0) }
            }
        } header: {
            Text("Bounces")
        }
        .task(id: projectPath) {
            existing = nil
            let cached = model.bounces[projectPath] ?? []
            existing = await Task.detached(priority: .userInitiated) { cached.filter { FileManager.default.fileExists(atPath: $0.path) } }.value
        }
    }

    private func isCurrent(_ f: BounceFile) -> Bool { player.currentPath == f.path }
    private func isPlaying(_ f: BounceFile) -> Bool { isCurrent(f) && player.isPlaying }

    private func play(_ f: BounceFile) { player.toggle(path: f.path, title: f.fileName, projectPath: projectPath) }

    private func mixRow(_ f: BounceFile, primary: Bool) -> some View {
        HStack(spacing: 12) {
            Button { play(f) } label: {
                Image(systemName: isPlaying(f) ? "pause.circle.fill" : "play.circle.fill").font(primary ? .system(size: 34) : .title2)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.fileName).font(primary ? .headline : .body).lineLimit(1).truncationMode(.middle)
                Text(detail(f)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, primary ? 4 : 0)
        .contentShape(Rectangle())
        .onTapGesture { play(f) }
        .contextMenu { revealMenu(f) }
    }

    private func stemRow(_ f: BounceFile) -> some View {
        HStack(spacing: 8) {
            Button { play(f) } label: { Image(systemName: isPlaying(f) ? "pause.fill" : "play.fill") }.buttonStyle(.borderless)
            Text(f.stemNumber.map { "STM#\(String(format: "%02d", $0))" } ?? "Stem")
                .font(.body.monospaced()).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            Text(f.fileName).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: Int64(f.sizeBytes), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { play(f) }
        .contextMenu { revealMenu(f) }
    }

    @ViewBuilder private func revealMenu(_ f: BounceFile) -> some View {
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f.path)]) }
    }

    private func detail(_ f: BounceFile) -> String {
        let age = RelativeDateTimeFormatter().localizedString(for: Date(timeIntervalSince1970: TimeInterval(f.mtimeUnix)), relativeTo: Date())
        return "\(ByteCountFormatter.string(fromByteCount: Int64(f.sizeBytes), countStyle: .file)) · bounced \(age)"
    }
}
