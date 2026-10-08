import LpxCore
import SwiftUI

struct ContentView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(AuRegistry.self) private var registry

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
        } content: {
            if model.isPluginView { PluginRailView() } else { MiddlePane() }
        } detail: {
            if model.isPluginView {
                if let fp = model.selectedPlugin, let row = model.pluginRows.first(where: { $0.fingerprint == fp }) {
                    PluginDetailView(row: row).id(fp)
                } else {
                    ContentUnavailableView("Select a plug-in", systemImage: "puzzlepiece.extension")
                }
            } else if let path = model.selectedProject, model.entries[path] != nil {
                ProjectDetailLoader(path: path).id(path)
            } else if let path = model.selectedProject, let message = model.errors[path] {
                ContentUnavailableView("Can't read this project", systemImage: "exclamationmark.triangle", description: Text(message))
            } else {
                ContentUnavailableView("Select a project", systemImage: "music.note.list")
            }
        }
        .id(model.layoutResets)
        .searchable(
            text: Binding(get: { model.isPluginView ? model.pluginQuery : model.query },
                          set: { if model.isPluginView { model.pluginQuery = $0 } else { model.query = $0 } }),
            placement: .toolbar,
            prompt: model.isPluginView ? "Search plug-ins" : "Search projects, tracks and plug-ins")
        .safeAreaInset(edge: .bottom) { ScanBanner() }
        .dropDestination(for: URL.self) { urls, _ in
            let dirs = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && $0.pathExtension.lowercased() != "logicx" }
            dirs.forEach { model.addFolder($0.path) }
            return !dirs.isEmpty
        }
    }
}

struct SidebarView: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedFolder) {
            Section("Explore") {
                Label {
                    VStack(alignment: .leading) {
                        Text("Plug-ins")
                        Text("\(model.pluginRows.count) used across the library").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "puzzlepiece.extension") }
                .tag(LibraryModel.pluginsID)
            }
            Section("Library") {
                ForEach(model.folders, id: \.self) { folder in
                    Label {
                        VStack(alignment: .leading) {
                            Text(URL(fileURLWithPath: folder).lastPathComponent)
                            Text("\(model.folderProjects[folder]?.count ?? 0) projects")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "folder") }
                    .tag(folder)
                    .contextMenu {
                        Button("Rescan") { model.scan(folder) }
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)]) }
                        Button("Remove from Library", role: .destructive) { model.removeFolder(folder) }
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 225)
        .toolbar {
            ToolbarItem { Button { model.chooseFolder() } label: { Label("Add Folder", systemImage: "folder.badge.plus") } }
        }
        .overlay {
            if model.folders.isEmpty {
                ContentUnavailableView {
                    Label("No folders yet", systemImage: "folder.badge.plus")
                } description: {
                    Text("Add a folder that contains Logic projects, or drop one here.")
                } actions: {
                    Button("Add Folder…") { model.chooseFolder() }
                }
            }
        }
    }
}

struct ProjectListView: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let paths = model.selectedFolder.map { model.visibleProjects(in: $0) } ?? []
        List(paths, id: \.self, selection: $model.selectedProject) { path in
            ProjectRow(path: path)
        }
        .safeAreaInset(edge: .top, spacing: 0) { FilterChips(count: paths.count) }
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $model.onlyMissingPlugins) {
                    Label("Missing plug-ins only", systemImage: "exclamationmark.triangle")
                }
                .help("Show only projects that need plug-ins this Mac doesn't have")
            }
        }
        .navigationTitle(model.selectedFolder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Projects")
        .navigationSplitViewColumnWidth(min: 260, ideal: 750)
        .overlay {
            if model.selectedFolder != nil, paths.isEmpty, !model.isScanning {
                if model.query.isEmpty && (model.similarityFilter != nil || model.onlyMissingPlugins) {
                    ContentUnavailableView("No projects match these filters", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text(model.isScanning ? "The library is still being read; more may appear." : "Clear a filter to see more."))
                } else if model.query.isEmpty {
                    ContentUnavailableView("No projects found", systemImage: "music.note")
                } else {
                    ContentUnavailableView.search(text: model.query)
                }
            }
        }
    }
}

/// Active filters above the project list, each dismissible.
struct FilterChips: View {
    @Environment(LibraryModel.self) private var model
    let count: Int

    var body: some View {
        if model.similarityFilter != nil || model.onlyMissingPlugins {
            HStack(spacing: 8) {
                if let axis = model.similarityFilter {
                    chip("Similar: \(axis.label)") { model.similarityFilter = nil }
                }
                if model.onlyMissingPlugins {
                    chip("Missing plug-ins") { model.onlyMissingPlugins = false }
                }
                Text("\(count) project\(count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.bar)
        }
    }

    private func chip(_ text: String, clear: @escaping () -> Void) -> some View {
        Button(action: clear) {
            HStack(spacing: 4) {
                Text(text)
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Clear this filter")
    }
}

struct ProjectRow: View {
    @Environment(LibraryModel.self) private var model
    let path: String

    var body: some View {
        let entry = model.entries[path]
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(LibraryModel.projectName(path)).lineLimit(1)
                if let v = model.verdict(for: path), !v.missing.isEmpty {
                    Image(systemName: v.status == .willNotOpen ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(v.status == .willNotOpen ? .red : .orange)
                        .help(v.headline)
                }
                if let n = entry?.alternativeCount, n > 1 {
                    Text("\(n) alts").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule()).help("\(n) alternatives")
                }
            }
            if let e = entry {
                Text("\(Int(e.metadata.bpm.rounded())) BPM · \(e.visibleTrackCount) tracks · \(e.plugins.count) plug-ins")
                    .font(.caption).foregroundStyle(.secondary)
                Text(URL(fileURLWithPath: path).deletingLastPathComponent().path)
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
            } else if model.errors[path] != nil {
                Label("Can't read", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            } else {
                Text("Reading…").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .tag(path)
        .contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
        }
    }
}

/// Loads the full parse result (tracks, alternatives, …) for the selected project.
struct ProjectDetailLoader: View {
    @Environment(LibraryModel.self) private var model
    let path: String
    @State private var summary: ProjectSummary?
    @State private var failed = false

    var body: some View {
        Group {
            if let summary {
                ProjectDetailView(base: summary)
            } else if failed {
                ContentUnavailableView("Can't load this project", systemImage: "exclamationmark.triangle",
                                       description: Text("It will be read again on the next scan."))
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: path) {
            summary = nil; failed = false
            summary = await model.fullSummary(for: path)
            failed = summary == nil
        }
    }
}

struct ScanBanner: View {
    @Environment(LibraryModel.self) private var model
    @Environment(AuRegistry.self) private var registry

    var body: some View {
        if model.cacheUnavailable {
            Label("Couldn't open the library database in ~/Library/Application Support/LpxExplorer — projects are re-read at every launch until that is fixed.", systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.orange).padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).background(.bar)
        } else if model.isScanning || registry.isScanning || registry.lastError != nil {
            HStack(spacing: 12) {
                if model.isScanning {
                    if let message = model.scanMessage {
                        Text(message)
                    } else {
                        Text("Updating \(model.scanTotal) new or changed project\(model.scanTotal == 1 ? "" : "s") · \(model.scanDone) done")
                        ProgressView(value: Double(model.scanDone), total: Double(max(1, model.scanTotal))).frame(maxWidth: 240)
                    }
                    Button("Stop") { model.stopScan() }
                }
                if registry.isScanning { Text("Reading installed plug-ins…").foregroundStyle(.secondary) }
                if let error = registry.lastError {
                    Text("Plug-in names unavailable: \(error)").foregroundStyle(.orange)
                    Button("Retry") { registry.refresh() }
                }
                Spacer()
            }
            .font(.callout)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.bar)
        }
    }
}

/// Middle column: the three filter fields stay mounted on top; below them is the folder's project list, or — as soon as
/// anything is typed (here or in the toolbar's search box) — the library-wide results.
struct MiddlePane: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        Group {
            if model.isSearching { SearchResultsView() } else { ProjectListView() }
        }
        .safeAreaInset(edge: .top, spacing: 0) { SearchFilterBar() }
    }
}

/// Library-wide results: every row group is a project that matches, followed by the tracks/objects inside it that matched.
/// The toolbar's search box matches everything (project, track, object and channel names, plug-ins); the filter fields
/// above match only their own field; everything typed must match.
struct SearchResultsView: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let terms = SearchMatcher.terms(of: model.query) + SearchMatcher.terms(of: model.filters.name)
        List(selection: $model.selectedProject) {
            ForEach(model.results, id: \.path) { result in
                ProjectRow(path: result.path).tag(result.path)
                ForEach(result.tracks, id: \.offset) { h in
                    TrackHitRow(hit: h, terms: terms, pluginTerms: SearchMatcher.terms(of: model.query) + SearchMatcher.terms(of: model.filters.plugin))
                        .padding(.leading, 18)
                        .frame(maxWidth: .infinity, alignment: .leading) // the whole row is the click target, not just its text
                        .contentShape(Rectangle())
                        .onTapGesture { model.showTrack(path: h.path, offset: h.offset) }
                }
            }
            if let indexed = model.trackIndexedProjects, indexed < model.entries.count {
                Text("Per-track results cover \(indexed) of \(model.entries.count) projects; the others can only match as a whole.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.totalMatchingTracks > model.listedTracks {
                Text("Showing \(model.listedTracks) of \(model.totalMatchingTracks) matching tracks — refine the search to see the rest.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Search")
        .navigationSubtitle("\(model.results.count) project\(model.results.count == 1 ? "" : "s") · \(model.totalMatchingTracks) track\(model.totalMatchingTracks == 1 ? "" : "s")")
        .navigationSplitViewColumnWidth(min: 300, ideal: 750)
        .overlay {
            if model.results.isEmpty && !model.isScanning {
                ContentUnavailableView.search(text: model.query)
            }
        }
    }
}

struct TrackHitRow: View {
    @Environment(AuRegistry.self) private var registry
    let hit: TrackHit
    let terms: [String]
    /// Terms that may match plug-in names: those plug-ins of the track are listed under it.
    var pluginTerms: [String] = []

    private func highlighted(_ s: String, _ terms: [String]) -> AttributedString {
        var out = AttributedString(s)
        let folded = SearchMatcher.fold(s)
        // Folding preserves character count for ordinary text; skip highlighting if it doesn't.
        guard folded.count == s.count else { return out }
        for term in terms {
            var from = folded.startIndex
            while let r = folded.range(of: term, range: from..<folded.endIndex) {
                let lo: Int = folded.distance(from: folded.startIndex, to: r.lowerBound)
                let len: Int = folded.distance(from: r.lowerBound, to: r.upperBound)
                let a = out.index(out.startIndex, offsetByCharacters: lo)
                let b = out.index(a, offsetByCharacters: len)
                out[a..<b].backgroundColor = Color.yellow.opacity(0.35)
                from = r.upperBound
            }
        }
        return out
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(hit.position.map(String.init) ?? "—").font(.body.monospacedDigit()).foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(highlighted(hit.name.isEmpty ? "—" : hit.name, terms)).lineLimit(1)
                    if hit.isHidden { Image(systemName: "eye.slash").font(.caption).foregroundStyle(.secondary).help("Hidden in Logic's arrangement") }
                }
                if !hit.objectName.isEmpty, hit.objectName != hit.name {
                    Text(highlighted("Object: \(hit.objectName)", terms)).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
                let matchedPlugins = hit.pluginFingerprints.map { registry.entries[$0]?.name ?? $0 }.filter { name in
                    let folded = SearchMatcher.fold(name)
                    return pluginTerms.contains { folded.contains($0) }
                }
                if !matchedPlugins.isEmpty {
                    Text(highlighted(matchedPlugins.joined(separator: " · "), pluginTerms)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if !hit.channel.isEmpty, hit.channel != hit.name {
                    Text(highlighted(hit.channel, terms)).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
        }
    }
}

/// Field filters for drilling down: every field narrows the same result list.
struct SearchFilterBar: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("Project name", text: $model.filters.project)
                TextField("Track / object name", text: $model.filters.name)
                TextField("Plug-in", text: $model.filters.plugin)
            }
            .textFieldStyle(.roundedBorder)
            HStack(spacing: 6) {
                ForEach(LibraryModel.SearchFilters.KindGroup.allCases) { g in
                    let on = model.filters.kinds.contains(g)
                    Toggle(g.rawValue, isOn: Binding(get: { on }, set: { if $0 { model.filters.kinds.insert(g) } else { model.filters.kinds.remove(g) } }))
                        .toggleStyle(.button).controlSize(.small)
                }
                Picker("Hidden", selection: $model.filters.hidden) {
                    Text("Hidden tracks: show").tag(TrackSearchQuery.Visibility.include)
                    Text("Hidden tracks: skip").tag(TrackSearchQuery.Visibility.exclude)
                    Text("Hidden tracks: only").tag(TrackSearchQuery.Visibility.only)
                }
                .labelsHidden().controlSize(.small).fixedSize()
                Spacer()
                if model.filters.isActive { Button("Clear") { model.clearFilters() }.controlSize(.small) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.bar)
    }
}
