import AppKit
import LpxCore
import SwiftUI

struct ProjectDetailView: View {
    @Environment(AuRegistry.self) private var registry
    @Environment(LibraryModel.self) private var model
    @State private var variantSummary: ProjectSummary?
    @State private var variantError: String?
    /// The project as cached by the scan (lowest-numbered alternative).
    let base: ProjectSummary

    /// What's on screen: the chosen alternative if one was loaded, else the scanned summary.
    private var summary: ProjectSummary { variantSummary ?? base }
    private var selectedVariant: Int { summary.variant }

    private var url: URL { URL(fileURLWithPath: summary.path) }

    private struct PluginGroup: Identifiable {
        let title: String
        let items: [(name: String, count: Int)]
        var id: String { title }
    }

    private var groups: [PluginGroup] {
        func group(_ title: String, _ types: Set<String>) -> PluginGroup? {
            var counts: [String: Int] = [:]
            for au in summary.fingerprints where types.contains(au.typeCode) { counts[registry.name(for: au), default: 0] += 1 }
            guard !counts.isEmpty else { return nil }
            return PluginGroup(title: title, items: counts.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }.map { ($0.key, $0.value) })
        }
        return [group("Instruments", ["aumu"]), group("Audio effects", ["aufx", "aumf"]), group("MIDI effects", ["aumi"])].compactMap { $0 }
    }

    /// Every arrangement track, hidden ones included, in Logic's order (the channel-strip fallback has no numbers
    /// and keeps file order).
    private var orderedTracks: [Track] {
        summary.tracks.sorted { a, b in
            switch (a.position, b.position) {
            case let (x?, y?): return x != y ? x < y : a.offset < b.offset
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }
    }

    private func symbol(for kind: TrackKind) -> String {
        switch kind {
        case .audio: "waveform"
        case .instrument: "pianokeys"
        case .folder: "folder"
        case .summingStack: "square.stack.3d.up"
        case .bus: "arrow.triangle.merge"
        case .aux: "arrow.triangle.branch"
        default: "slider.horizontal.3"
        }
    }

    private func pluginLine(_ t: Track) -> String {
        ([t.instrument].compactMap { $0 } + t.midiFx + t.audioFx).map { registry.name(for: $0) }.joined(separator: " · ")
    }

    /// Channel identifier column: the channel strip's own name ("Audio 1", "Inst 3"). Folders have none.
    private func channelLabel(_ t: Track) -> String {
        if !t.name.isEmpty { return t.name }
        switch t.kind {
        case .folder: return "Folder"
        case .summingStack: return "Stack"
        default: return "—"
        }
    }

    @ViewBuilder private var tracksSection: some View {
        let tracks = orderedTracks
        let hiddenCount = tracks.filter(\.isHidden).count
        Section {
            if tracks.isEmpty {
                Text("No tracks found").foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Text("#").frame(width: 32, alignment: .trailing)
                    Color.clear.frame(width: 20)
                    Text("Channel").frame(width: 84, alignment: .leading)
                    Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(tracks, id: \.offset) { t in
                let name = t.displayName
                let focused = model.focusedTrack?.path == summary.path && model.focusedTrack?.offset == t.offset
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(t.position.map(String.init) ?? "—")
                        .font(.body.monospacedDigit()).foregroundStyle(t.position == nil ? .tertiary : .primary)
                        .frame(width: 32, alignment: .trailing)
                    Image(systemName: symbol(for: t.kind)).foregroundStyle(.secondary).frame(width: 20)
                    Text(channelLabel(t))
                        .font(.body.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1).frame(width: 84, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(name.isEmpty ? "—" : name).foregroundStyle(name.isEmpty ? .tertiary : .primary)
                            if t.isHidden {
                                Image(systemName: "eye.slash").font(.caption).foregroundStyle(.secondary).help("Hidden in Logic's arrangement")
                            }
                        }
                        // Several tracks can share one object; show it when the track is named differently.
                        if let object = t.objectName, object != name, t.kind != .folder {
                            Text("Object: \(object)").font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        let plugins = pluginLine(t)
                        if !plugins.isEmpty { Text(plugins).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 2)
                .background(focused ? Color.yellow.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 4))
                .id(t.offset)
            }
        } header: {
            Text("Tracks (\(tracks.count)" + (hiddenCount > 0 ? ", \(hiddenCount) hidden)" : ")"))
        }
    }

    @ViewBuilder private var alternativesSection: some View {
        let alts = base.alternatives
        if alts.count > 1 {
            Section("Alternatives (\(alts.count))") {
                Picker("Showing", selection: Binding(get: { selectedVariant }, set: { loadVariant($0) })) {
                    ForEach(alts, id: \.index) { a in
                        Text(a.isActive ? "\(a.displayName) — last opened in Logic" : a.displayName).tag(a.index)
                    }
                }
                if let variantError { Text(variantError).font(.caption).foregroundStyle(.orange) }
            }
        }
    }

    private func loadVariant(_ index: Int) {
        guard index != selectedVariant else { return }
        if index == base.variant { variantSummary = nil; variantError = nil; return }
        let bundle = url
        Task {
            do {
                variantSummary = try await Task.detached(priority: .userInitiated) { try ProjectParser.parse(bundle: bundle, variant: index) }.value
                variantError = nil
            } catch {
                variantError = "Couldn't read this alternative: \(error)"
            }
        }
    }

    private func scrollToFocusedTrack(_ proxy: ScrollViewProxy) {
        guard let f = model.focusedTrack, f.path == summary.path,
              let t = summary.tracks.first(where: { $0.offset == f.offset }) else { return }
        // The Form lays out lazily and row heights vary (plug-in lines), so the first jump can land short of
        // rows that aren't realised yet. Repeat it as the layout settles; each pass starts closer.
        Task {
            for delay in [120, 350, 800] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled, model.focusedTrack?.offset == f.offset else { return }
                withAnimation { proxy.scrollTo(t.offset, anchor: .center) }
            }
        }
    }

    var body: some View {
        let m = summary.metadata
        ScrollViewReader { proxy in
        Form {
            Section { CompatibilityBand(summary: summary) }
            if let image = summary.alternatives.first(where: { $0.index == selectedVariant })?.windowImagePath {
                Section {
                    WindowImage(path: image)
                    Text("Snapshot from last save · \(RelativeDateTimeFormatter().localizedString(for: Date(timeIntervalSince1970: TimeInterval(summary.projectDataMTime)), relativeTo: Date()))")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
                }
            }
            alternativesSection
            Section {
                LabeledContent("Tempo") {
                    if let axis = SimilarityAxis.bpm(of: m) {
                        Button(String(format: "%.1f BPM", m.bpm)) { model.applySimilarity(axis) }
                            .buttonStyle(.link).help("Find projects \(axis.label)")
                    } else { Text("—") }
                }
                LabeledContent("Time signature", value: "\(m.sigNumerator)/\(m.sigDenominator)")
                LabeledContent("Key") {
                    if let axis = SimilarityAxis.key(of: m) {
                        Button(axis.label) { model.applySimilarity(axis) }
                            .buttonStyle(.link).help("Find other projects in \(axis.label)")
                    } else { Text("—") }
                }
                if let both = SimilarityAxis.keyAndBPM(of: m) {
                    Button("Find similar — \(both.label)") { model.applySimilarity(both) }
                        .buttonStyle(.link)
                }
                LabeledContent("Tracks", value: "\(m.trackCount)")
                LabeledContent("Sample rate", value: MetadataFormat.sampleRate(hz: m.sampleRate))
                if let frameRate = MetadataFormat.frameRate(index: m.frameRateIndex) { LabeledContent("Frame rate", value: frameRate) }
                LabeledContent("Created", value: MetadataFormat.dateWithRelative(unix: summary.stats.createdAt))
                LabeledContent("Modified", value: MetadataFormat.dateWithRelative(unix: summary.stats.modifiedAt))
                LabeledContent("Last saved", value: Date(timeIntervalSince1970: TimeInterval(summary.projectDataMTime)).formatted(date: .abbreviated, time: .shortened))
                if let v = summary.lastSavedFrom { LabeledContent("Saved with", value: v) }
                LabeledContent("Bundle size", value: ByteCountFormatter.string(fromByteCount: Int64(summary.stats.sizeBytes), countStyle: .file))
                LabeledContent("Audio files", value: "\(m.audioFileCount)")
                if m.impulseResponseCount > 0 { LabeledContent("Impulse responses", value: "\(m.impulseResponseCount)") }
            }
            if !ProjectBundle.hasInformationPlist(url) {
                Section { Label("This project has no ProjectInformation.plist; Logic may refuse to open it.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            tracksSection
            if groups.isEmpty {
                Section("Plug-ins") { Text("No plug-ins found").foregroundStyle(.secondary) }
            }
            ForEach(groups) { g in
                Section(g.title) {
                    ForEach(g.items, id: \.name) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            if item.count > 1 { Text("×\(item.count)").foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            AudioSection(bundlePath: summary.path)
        }
        .formStyle(.grouped)
        .task(id: base.path) { variantSummary = nil; variantError = nil }
        .task(id: model.focusedTrack?.offset) { scrollToFocusedTrack(proxy) }
        .navigationTitle(LibraryModel.projectName(summary.path))
        .navigationSubtitle(url.deletingLastPathComponent().path)
        .toolbar {
            ToolbarItem {
                // Reveal only: this app never opens (or launches Logic with) a project.
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Label("Reveal in Finder", systemImage: "folder") }
                    .help("Reveal this project in Finder")
            }
        }
        }
    }
}

/// Logic's saved window screenshot, decoded off the main thread.
struct WindowImage: View {
    let path: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                    .help("Click to open the full-size image")
            } else {
                Rectangle().fill(.quaternary).frame(height: 120).overlay(ProgressView().controlSize(.small))
            }
        }
        .task(id: path) {
            let p = path
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: URL(fileURLWithPath: p)) }.value
            image = data.flatMap { NSImage(data: $0) }
        }
    }
}
