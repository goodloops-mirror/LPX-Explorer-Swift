import AppKit
import Foundation
import LpxCore
import Observation

/// Thread-safe mailbox: scan workers push outcomes, the main actor drains them
/// in batches so a 3000-project scan causes ~dozens of UI updates, not 3000.
final class OutcomeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [ScanOutcome] = []
    func add(_ o: ScanOutcome) { lock.lock(); pending.append(o); lock.unlock() }
    func drain() -> [ScanOutcome] {
        lock.lock(); defer { lock.unlock() }
        let out = pending; pending = []; return out
    }
}

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

@MainActor @Observable
final class LibraryModel {
    private(set) var folders: [String]
    private(set) var folderProjects: [String: [String]] = [:]
    /// Light per-project data for the list, search, filters and plug-in view (full summaries load on demand).
    private(set) var entries: [String: ProjectListEntry] = [:]
    private(set) var errors: [String: String] = [:]
    /// True while the cached library is being read from disk at launch.
    private(set) var isLoadingCache = false
    private(set) var isScanning = false { didSet { if oldValue && !isScanning { scheduleSearch() } } }
    private(set) var scanTotal = 0
    private(set) var scanDone = 0
    private(set) var scanMessage: String?

    var selectedFolder: String? { didSet { if oldValue != selectedFolder { similarityFilter = nil } } }
    var selectedProject: String?
    /// Bumped by "Reset Column Widths": rebuilds the split view so the default proportions (15 / 50 / 35 %) apply again.
    private(set) var layoutResets = 0

    func resetColumnWidths() {
        // AppKit keeps divider positions of autosaved split views in our own UserDefaults; forget them.
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains("SplitView") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        layoutResets += 1
    }
    var query = "" { didSet { if oldValue != query { if query.isEmpty { focusedTrack = nil }; scheduleSearch() } } }
    /// Library-wide track search (while `query` is non-empty): matching tracks, and projects matched by name alone.
    private(set) var trackResults = TrackSearchResult(hits: [], total: 0)
    private(set) var projectNameMatches: [String] = []
    /// Track to scroll to / highlight in the inspector after a result was clicked.
    var focusedTrack: (path: String, position: Int)?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    static let searchLimit = 500
    /// "Find similar" pivot (key / tempo); applies to the selected folder.
    var similarityFilter: SimilarityAxis?
    var onlyMissingPlugins = false

    // MARK: plug-in rail (library-wide usage view)

    /// Sidebar selection value for the "Plug-ins" entry (not a real folder path).
    static let pluginsID = "lpx://plugins"
    var pluginQuery = ""
    var pluginStatus: PluginStatusFilter = .all
    var pluginCategory: AuFineCategory?
    var selectedPlugin: String?
    @ObservationIgnored private var rowsCache: (projects: Int, registry: Int, rows: [PluginRow])?

    let registry: AuRegistry
    private let db: SummaryDatabase?
    /// Parsed in this session but possibly not yet written to SQLite: lets the inspector open a project
    /// the instant it is parsed, whatever order the background writes land in.
    private var unsavedSummaries: [String: ProjectSummary] = [:]
    @ObservationIgnored private var sortedByFolder: [String: [String]] = [:]
    @ObservationIgnored private var haystacks: [String: String] = [:]
    @ObservationIgnored private var foldedPluginNames: [String: String] = [:]
    @ObservationIgnored private var haystackRegistryVersion = -1
    private var started = false
    private var scanTask: Task<Void, Never>?
    private var cancelFlag: CancelFlag?

    private static let foldersKey = "libraryFolders"

    init(registry: AuRegistry) {
        self.registry = registry
        self.folders = UserDefaults.standard.stringArray(forKey: Self.foldersKey) ?? []
        SummaryDatabase.removeLegacyJSONCache(in: SummaryDatabase.defaultURL.deletingLastPathComponent())
        // The cache is disposable; if the real location can't be opened fall back to a throw-away file.
        self.db = (try? SummaryDatabase(url: SummaryDatabase.defaultURL))
            ?? (try? SummaryDatabase(url: FileManager.default.temporaryDirectory.appendingPathComponent("lpx-\(UUID().uuidString).sqlite")))
        self.selectedFolder = folders.first
    }

    /// Launch sequence (idempotent): read the cached library in the background so the list appears
    /// at once, then re-scan folders; only projects whose ProjectData changed are parsed again.
    func start() {
        guard !started else { return }
        started = true
        guard let db else { return rescanAllIfAny() }
        isLoadingCache = true
        Task {
            let cached = (try? await db.entries()) ?? []
            for e in cached where entries[e.path] == nil { entries[e.path] = e }
            for folder in folders where folderProjects[folder] == nil {
                // Provisional list straight from the cache; discovery below confirms it.
                let prefix = folder.hasSuffix("/") ? folder : folder + "/"
                setProjects(folder, entries.keys.filter { $0.hasPrefix(prefix) })
            }
            isLoadingCache = false
            rescanAllIfAny()
        }
    }

    private func rescanAllIfAny() { if !folders.isEmpty { rescanAll() } }

    /// Full parse result for the inspector: freshly parsed (not yet saved) summaries first, then SQLite.
    func fullSummary(for path: String) async -> ProjectSummary? {
        if let s = unsavedSummaries[path] { return s }
        return (try? await db?.summary(forPath: path)) ?? nil
    }

    /// Replace a folder's project list and refresh its cached name-sorted order (natural sort,
    /// computed once per change — not on every UI refresh).
    private func setProjects(_ folder: String, _ paths: [String]) {
        folderProjects[folder] = paths
        let named = paths.map { (Self.projectName($0), $0) }
        sortedByFolder[folder] = named.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }.map(\.1)
    }

    // MARK: folders

    func addFolder(_ path: String) {
        if !folders.contains(path) {
            folders.append(path)
            UserDefaults.standard.set(folders, forKey: Self.foldersKey)
        }
        selectedFolder = path
        scan(path)
    }

    func removeFolder(_ path: String) {
        folders.removeAll { $0 == path }
        let gone = folderProjects[path] ?? []
        folderProjects[path] = nil
        sortedByFolder[path] = nil
        for p in gone where !folders.contains(where: { (folderProjects[$0] ?? []).contains(p) }) { entries[p] = nil; errors[p] = nil }
        if let db { Task { try? await db.remove(paths: gone) } }
        UserDefaults.standard.set(folders, forKey: Self.foldersKey)
        if selectedFolder == path { selectedFolder = folders.first }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"
        if panel.runModal() == .OK, let url = panel.url { addFolder(url.path) }
    }

    // MARK: scanning

    func rescanAll() {
        scanTask?.cancel()
        let all = folders
        runScan(folders: all)
    }

    func scan(_ folder: String) { runScan(folders: [folder]) }

    func stopScan() {
        cancelFlag?.set()
        scanTask?.cancel()
    }

    private func runScan(folders targets: [String]) {
        scanTask?.cancel()
        cancelFlag?.set()
        let flag = CancelFlag()
        cancelFlag = flag
        isScanning = true
        scanDone = 0
        scanTotal = 0
        scanMessage = "Looking for projects…"
        let workers = LibraryScanner.defaultWorkerCount()

        scanTask = Task { [weak self] in
            var all: [(folder: String, urls: [URL])] = []
            for folder in targets {
                // nil = the folder couldn't be read (e.g. a disconnected volume): keep what we have cached.
                let found: [URL]? = await Task.detached(priority: .userInitiated) {
                    try? LogicxDiscovery.discover(in: URL(fileURLWithPath: folder), isCancelled: { flag.isSet })
                }.value
                guard let self else { return }
                guard let found, !flag.isSet else { continue }
                self.setProjects(folder, found.map(\.path))
                self.pruneVanishedProjects(in: folder, keeping: Set(found.map(\.path)))
                all.append((folder, found))
            }
            guard let self else { return }
            let known = (try? await self.db?.stamps()) ?? [:]
            let bundles = all.flatMap(\.urls)
            self.scanTotal = bundles.count
            self.scanMessage = nil

            let collector = OutcomeCollector()
            let flusher = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(150))
                    self?.apply(collector.drain())
                }
            }
            await LibraryScanner.scan(bundles: bundles, workers: workers, known: known, onOutcome: collector.add)
            flusher.cancel()
            self.apply(collector.drain())
            self.isScanning = false
        }
    }

    /// Projects deleted or moved away since the last scan disappear from the list and the cache.
    private func pruneVanishedProjects(in folder: String, keeping found: Set<String>) {
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        let gone = entries.keys.filter { $0.hasPrefix(prefix) && !found.contains($0) }
        guard !gone.isEmpty else { return }
        for p in gone { entries[p] = nil; errors[p] = nil; haystacks[p] = nil }
        if let db { Task { try? await db.remove(paths: gone) } }
    }

    private func apply(_ outcomes: [ScanOutcome]) {
        guard !outcomes.isEmpty else { return }
        var fresh: [ProjectSummary] = []
        for o in outcomes {
            switch o {
            case .unchanged: break
            case .parsed(let s):
                entries[s.path] = ProjectListEntry(summary: s)
                errors[s.path] = nil
                haystacks[s.path] = nil
                unsavedSummaries[s.path] = s
                fresh.append(s)
            case .failed(let path, let message):
                errors[path] = message
            }
        }
        scanDone = min(scanTotal, scanDone + outcomes.count)
        persist(fresh)
    }

    /// Incremental write: only projects that were actually (re)parsed in this batch.
    private func persist(_ batch: [ProjectSummary]) {
        guard !batch.isEmpty, let db else { return }
        Task {
            try? await db.upsert(batch)
            for s in batch where unsavedSummaries[s.path] == s { unsavedSummaries[s.path] = nil }
        }
    }

    /// True once `auval -l` has been read, so install status is meaningful.
    var pluginRowsKnowInstallStatus: Bool { !registry.entries.isEmpty }

    var isPluginView: Bool { selectedFolder == Self.pluginsID }

    /// Every plug-in used across the whole library (all folders), most-used first.
    /// Cached until the set of parsed projects or the AU registry changes.
    var pluginRows: [PluginRow] {
        let projects = entries.count // reading this also registers the observation dependency
        let regVersion = registry.version &+ registry.entries.count
        if let c = rowsCache, c.projects == projects, c.registry == regVersion { return c.rows }
        let rows = PluginRail.sortedByUsage(PluginRail.rows(PluginRollup.aggregate(entries),
                                                           registry: registry.entries.isEmpty ? nil : registry.entries))
        rowsCache = (projects, regVersion, rows)
        return rows
    }

    /// Jump from the plug-in view to a project in the folder that contains it.
    func showProject(_ path: String) {
        if let folder = folders.first(where: { (folderProjects[$0] ?? []).contains(path) }) { selectedFolder = folder }
        selectedProject = path
    }

    // MARK: search

    var isSearching: Bool { !SearchMatcher.terms(of: query).isEmpty && !isPluginView }

    /// Re-run the library-wide search shortly after the last keystroke (and after a scan finished).
    func scheduleSearch() {
        searchTask?.cancel()
        let text = query
        guard !SearchMatcher.terms(of: text).isEmpty else { trackResults = TrackSearchResult(hits: [], total: 0); projectNameMatches = []; return }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            let q = TrackSearchQuery(text: text) { self.pluginFingerprints(matching: $0) }
            let result = (try? await self.db?.searchTracks(q, limit: Self.searchLimit)) ?? TrackSearchResult(hits: [], total: 0)
            guard !Task.isCancelled else { return }
            let nameMatches = self.entries.keys.filter { SearchMatcher.matches(haystack: SearchMatcher.fold(Self.projectName($0)), terms: q.terms) }
                .sorted { Self.projectName($0).localizedStandardCompare(Self.projectName($1)) == .orderedAscending }
            self.trackResults = result
            self.projectNameMatches = nameMatches
        }
    }

    /// Fingerprints of installed plug-ins whose registry name contains `term` (already folded).
    private func pluginFingerprints(matching term: String) -> [String] {
        registry.entries.values.filter { SearchMatcher.fold($0.name).contains(term) }.map(\.fingerprint)
    }

    /// Open a search result: select its project and ask the inspector to show the track.
    func showTrack(path: String, position: Int) {
        showProject(path)
        focusedTrack = (path, position)
    }

    static func projectName(_ path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    func verdict(for path: String) -> CompatibilityVerdict? {
        entries[path].map { CompatibilityVerdict.evaluate(plugins: $0.plugins.map(\.ref), installed: registry.installed) }
    }

    func applySimilarity(_ axis: SimilarityAxis) {
        similarityFilter = axis
        selectedProject = nil
    }

    /// The folder's projects in natural name order, narrowed by the active filters and search text.
    func visibleProjects(in folder: String) -> [String] {
        var paths = sortedByFolder[folder] ?? []
        let filter = LibraryFilter(similarity: similarityFilter, onlyMissingPlugins: onlyMissingPlugins)
        if filter.isActive { paths = filter.apply(to: paths, entries: entries, installed: registry.installed) }
        let terms = SearchMatcher.terms(of: query)
        guard !terms.isEmpty else { return paths }
        if haystackRegistryVersion != registry.version {
            haystacks.removeAll(keepingCapacity: true)
            foldedPluginNames.removeAll(keepingCapacity: true)
            haystackRegistryVersion = registry.version
        }
        return paths.filter { path in
            guard let entry = entries[path] else { return SearchMatcher.matches(haystack: SearchMatcher.fold(Self.projectName(path)), terms: terms) }
            return SearchMatcher.matches(haystack: haystack(for: path, entry), terms: terms)
        }
    }

    /// Folded static text (name, tracks, alternatives) plus the folded names of the plug-ins used.
    private func haystack(for path: String, _ entry: ProjectListEntry) -> String {
        if let h = haystacks[path] { return h }
        let plugins = entry.plugins.map { use -> String in
            if let cached = foldedPluginNames[use.fingerprint] { return cached }
            let folded = SearchMatcher.fold(registry.name(for: use.ref))
            foldedPluginNames[use.fingerprint] = folded
            return folded
        }
        let h = entry.searchText + "\n" + plugins.joined(separator: "\n")
        haystacks[path] = h
        return h
    }

    var unindexedCount: Int {
        guard let folder = selectedFolder else { return 0 }
        return (folderProjects[folder] ?? []).filter { entries[$0] == nil && errors[$0] == nil }.count
    }
}
