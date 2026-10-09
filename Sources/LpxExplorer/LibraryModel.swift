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
    /// The on-disk library couldn't be opened: this session starts from scratch and nothing is remembered.
    private(set) var cacheUnavailable = false
    private(set) var isScanning = false { didSet { if oldValue && !isScanning { scheduleSearch(); syncBounces() } } }
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
    /// Projects that match, each with the tracks/objects inside it that matched.
    private(set) var results: [ProjectResult] = []
    /// The results in natural name order, before `sortOrder` is applied.
    @ObservationIgnored private var nameSortedResults: [ProjectResult] = []
    /// How the project list and the search results are ordered (remembered between launches).
    var sortOrder: ProjectOrder = LibraryModel.savedSortOrder() {
        didSet {
            guard oldValue != sortOrder else { return }
            UserDefaults.standard.set(sortOrder.field.rawValue, forKey: Self.sortFieldKey)
            UserDefaults.standard.set(sortOrder.ascending, forKey: Self.sortAscendingKey)
            applyResultOrder()
        }
    }
    private static let sortFieldKey = "projectSortField", sortAscendingKey = "projectSortAscending"

    private static func savedSortOrder() -> ProjectOrder {
        let d = UserDefaults.standard
        guard let raw = d.string(forKey: sortFieldKey), let field = ProjectSortField(rawValue: raw) else { return ProjectOrder() }
        return ProjectOrder(field: field, ascending: d.object(forKey: sortAscendingKey) as? Bool ?? ProjectOrder.initial(for: field).ascending)
    }

    private func applyResultOrder() {
        results = ProjectSorting.sorted(nameSortedResults, by: sortOrder, path: \.path, date: { self.entries[$0]?.projectDataMTime })
    }
    /// Bounces found next to / inside each project (cached in SQLite; refreshed in the background).
    private(set) var bounces: [String: [BounceFile]] = [:]
    var bounceFilter: BounceFilter = .any { didSet { if oldValue != bounceFilter { scheduleSearch() } } }
    @ObservationIgnored private var bounceTask: Task<Void, Never>?
    /// Matching tracks in the whole library (may exceed what is listed: the list is capped).
    private(set) var totalMatchingTracks = 0
    private(set) var listedTracks = 0
    /// How many projects have per-track search rows (the rest only match as a whole).
    private(set) var trackIndexedProjects: Int?
    /// Track to scroll to / highlight in the inspector after a result was clicked.
    var focusedTrack: (path: String, offset: Int)?
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
    @ObservationIgnored private var pluginTexts: [String: String] = [:]
    @ObservationIgnored private var foldedNames: [String: String] = [:]
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
        // The cache is disposable; if the real location can't be opened fall back to a throw-away file (and say so).
        if let real = try? SummaryDatabase(url: SummaryDatabase.defaultURL) {
            self.db = real
        } else {
            self.db = try? SummaryDatabase(url: FileManager.default.temporaryDirectory.appendingPathComponent("lpx-\(UUID().uuidString).sqlite"))
            self.cacheUnavailable = true
        }
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
            // Projects that failed to parse stay failed until their file changes (no retry at every launch).
            for (path, message) in (try? await db.failures()) ?? [:] where entries[path] == nil { errors[path] = message }
            bounces = (try? await db.bounces()) ?? [:]
            Task { _ = try? await db.rebuildTracksIfNeeded() } // derived search rows; cheap and never a re-parse
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
        for p in gone where !folders.contains(where: { (folderProjects[$0] ?? []).contains(p) }) { entries[p] = nil; errors[p] = nil; bounces[p] = nil }
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
            self.scanMessage = "Checking for changes…"
            // Only new or modified projects are parsed; with nothing changed this is a quick stat pass and no progress bar.
            let bundles = await LibraryScanner.changedBundles(all.flatMap(\.urls), known: known, workers: workers)
            guard !flag.isSet else { self.isScanning = false; return }
            self.scanTotal = bundles.count
            self.scanMessage = nil
            if bundles.isEmpty { self.isScanning = false; return }

            let collector = OutcomeCollector()
            let flusher = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(150))
                    self?.apply(collector.drain())
                }
            }
            await LibraryScanner.scan(bundles: bundles, workers: workers, onOutcome: collector.add)
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
        var failed: [ProjectFailure] = []
        for o in outcomes {
            switch o {
            case .unchanged: break
            case .parsed(let s):
                entries[s.path] = ProjectListEntry(summary: s)
                errors[s.path] = nil
                haystacks[s.path] = nil
                pluginTexts[s.path] = nil
                unsavedSummaries[s.path] = s
                fresh.append(s)
            case .failed(let path, let message):
                errors[path] = message
                if let st = ProjectParser.projectDataStat(bundle: URL(fileURLWithPath: path)) {
                    failed.append(ProjectFailure(path: path, stamp: DatabaseStamp(mtime: st.mtime, size: st.size), message: message))
                }
            }
        }
        scanDone = min(scanTotal, scanDone + outcomes.count)
        persist(fresh)
        if let db, !failed.isEmpty { Task { try? await db.recordFailures(failed) } }
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

    // MARK: bounces

    func hasBounce(_ path: String) -> Bool { !(bounces[path] ?? []).isEmpty }
    private var bouncePaths: Set<String> { Set(bounces.compactMap { $0.value.isEmpty ? nil : $0.key }) }

    /// Look for every project's bounces in the background (shared `Bounces` folders are listed once) and remember the
    /// result. A project whose bundle can't be seen right now (drive offline) keeps what was cached.
    func syncBounces() {
        bounceTask?.cancel()
        let projects = Array(entries.keys)
        let known = bounces
        let roots = folders.filter { $0 != Self.pluginsID }
        guard !projects.isEmpty else { return }
        bounceTask = Task { [weak self] in
            let found = await Task.detached(priority: .utility) { () -> [String: [BounceFile]] in
                let cache = BounceListingCache()
                let lock = NSLock()
                var out: [String: [BounceFile]] = [:]
                DispatchQueue.concurrentPerform(iterations: projects.count) { i in
                    let path = projects[i]
                    guard !Task.isCancelled, FileManager.default.fileExists(atPath: path) else { return }
                    // The library folder the project lives in bounds how far up its Bounces folders are looked for.
                    let root = roots.filter { path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }.max { $0.count < $1.count }
                    let files = BounceFinder.find(project: URL(fileURLWithPath: path), libraryRoot: root.map { URL(fileURLWithPath: $0) }, cache: cache)
                    lock.lock(); out[path] = files; lock.unlock()
                }
                return out
            }.value
            guard !Task.isCancelled, let self else { return }
            var changed: [String: [BounceFile]] = [:]
            for (path, files) in found where (known[path] ?? []) != files { changed[path] = files }
            guard !changed.isEmpty else { return }
            for (path, files) in changed { self.bounces[path] = files.isEmpty ? nil : files }
            try? await self.db?.saveBounces(changed)
        }
    }

    // MARK: search

    /// Field filters above the results (all optional, all combined with the search box).
    struct SearchFilters: Equatable {
        enum KindGroup: String, CaseIterable, Identifiable {
            case audio = "Audio", instrument = "Instrument", structure = "Folder / Stack"
            var id: String { rawValue }
            var kinds: Set<TrackKind> {
                switch self { case .audio: [.audio]; case .instrument: [.instrument]; case .structure: [.folder, .summingStack] }
            }
        }
        var project = ""
        var name = ""
        var plugin = ""
        var kinds: Set<KindGroup> = []
        var hidden: TrackSearchQuery.Visibility = .include
        var isActive: Bool { self != SearchFilters() }
        var hasText: Bool { !SearchMatcher.terms(of: project + " " + name + " " + plugin).isEmpty }
    }

    var filters = SearchFilters() { didSet { if oldValue != filters { scheduleSearch() } } }
    var isSearching: Bool {
        !isPluginView && (!SearchMatcher.terms(of: query).isEmpty || filters.isActive)
    }

    func clearFilters() { filters = SearchFilters() }

    /// Re-run the library-wide search shortly after the last keystroke (and after a scan finished).
    func scheduleSearch() {
        searchTask?.cancel()
        let text = query, f = filters
        let freeTerms = SearchMatcher.terms(of: text)
        guard !freeTerms.isEmpty || f.hasText || !f.kinds.isEmpty else {
            nameSortedResults = []; results = []; totalMatchingTracks = 0; listedTracks = 0; return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            var q = TrackSearchQuery(text: text) { self.pluginFingerprints(matching: $0) }
            q.projectTerms = SearchMatcher.terms(of: f.project)
            q.nameTerms = SearchMatcher.terms(of: f.name)
            q.pluginTerms = SearchMatcher.terms(of: f.plugin)
            q.pluginTermFingerprints = q.pluginTerms.map { self.pluginFingerprints(matching: $0) }
            q.kinds = f.kinds.reduce(into: Set<TrackKind>()) { $0.formUnion($1.kinds) }
            q.hidden = f.hidden
            let result = (try? await self.db?.searchTracks(q, limit: Self.searchLimit)) ?? TrackSearchResult(hits: [], total: 0)
            guard !Task.isCancelled else { return }
            // Projects that match as a whole (name, any track/object name, any plug-in) but have no track row listed below.
            let pq = ProjectSearch.Query(terms: q.terms, projectTerms: q.projectTerms, nameTerms: q.nameTerms, pluginTerms: q.pluginTerms,
                                         // Track-name, kind and hidden filters are about tracks: a project only counts through its matching tracks.
                                         restrictsTracks: !q.nameTerms.isEmpty || !q.kinds.isEmpty || q.hidden != .include)
            self.refreshProjectTexts()
            let wholeProjects = pq.restrictsTracks ? [] : self.entries.filter { path, entry in
                ProjectSearch.matches(pq, entry: entry, projectName: self.foldedProjectName(path), pluginText: self.pluginText(path, entry))
            }.map(\.key)
            self.nameSortedResults = SearchResults.combine(hits: result.hits, projects: wholeProjects, name: Self.projectName)
                .filter { self.bounceFilter.allows(hasBounce: self.hasBounce($0.path)) }
            self.applyResultOrder()
            self.totalMatchingTracks = result.total
            self.listedTracks = result.hits.count
            self.trackIndexedProjects = (try? await self.db?.trackIndexedProjectCount()) ?? nil
        }
    }

    /// Fingerprints of installed plug-ins whose registry name contains `term` (already folded).
    private func pluginFingerprints(matching term: String) -> [String] {
        registry.entries.values.filter { SearchMatcher.fold($0.name).contains(term) }.map(\.fingerprint)
    }

    /// Open a search result: select its project and ask the inspector to show the track.
    func showTrack(path: String, offset: Int) {
        showProject(path)
        focusedTrack = (path, offset)
    }

    static func projectName(_ path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    func verdict(for path: String) -> CompatibilityVerdict? {
        entries[path].flatMap { $0.isLegacy ? nil : $0 }.map { CompatibilityVerdict.evaluate(plugins: $0.plugins.map(\.ref), installed: registry.installed) }
    }

    func applySimilarity(_ axis: SimilarityAxis) {
        similarityFilter = axis
        selectedProject = nil
    }

    /// `paths` (in natural name order) in the chosen sort order.
    private func ordered(_ paths: [String]) -> [String] {
        ProjectSorting.sorted(paths, by: sortOrder, date: { entries[$0]?.projectDataMTime })
    }

    /// The folder's projects, narrowed by the active filters and search text, in the chosen sort order (natural name order by default).
    func visibleProjects(in folder: String) -> [String] {
        var paths = sortedByFolder[folder] ?? []
        let filter = LibraryFilter(similarity: similarityFilter, onlyMissingPlugins: onlyMissingPlugins, bounce: bounceFilter)
        if filter.isActive { paths = filter.apply(to: paths, entries: entries, installed: registry.installed, withBounce: bouncePaths) }
        let terms = SearchMatcher.terms(of: query)
        guard !terms.isEmpty else { return ordered(paths) }
        if haystackRegistryVersion != registry.version {
            haystacks.removeAll(keepingCapacity: true)
            foldedPluginNames.removeAll(keepingCapacity: true)
            haystackRegistryVersion = registry.version
        }
        return ordered(paths.filter { path in
            guard let entry = entries[path] else { return SearchMatcher.matches(haystack: SearchMatcher.fold(Self.projectName(path)), terms: terms) }
            return SearchMatcher.matches(haystack: haystack(for: path, entry), terms: terms)
        })
    }

    /// Folded plug-in names / project names for the project-level search, cached until the plug-in registry changes.
    private func refreshProjectTexts() {
        if haystackRegistryVersion != registry.version {
            haystacks.removeAll(keepingCapacity: true)
            foldedPluginNames.removeAll(keepingCapacity: true)
            pluginTexts.removeAll(keepingCapacity: true)
            haystackRegistryVersion = registry.version
        }
    }

    private func foldedProjectName(_ path: String) -> String {
        if let n = foldedNames[path] { return n }
        let n = SearchMatcher.fold(Self.projectName(path)); foldedNames[path] = n; return n
    }

    private func pluginText(_ path: String, _ entry: ProjectListEntry) -> String {
        if let t = pluginTexts[path] { return t }
        let names = entry.plugins.map { use -> String in
            if let cached = foldedPluginNames[use.fingerprint] { return cached }
            let folded = SearchMatcher.fold(registry.name(for: use.ref))
            foldedPluginNames[use.fingerprint] = folded
            return folded
        }
        let t = names.joined(separator: "\n")
        pluginTexts[path] = t
        return t
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
