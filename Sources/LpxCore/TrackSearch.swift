import Foundation

/// One searchable track, derived from a project summary and stored in SQLite (`tracks` table).
public struct TrackSearchRow: Equatable, Sendable {
    public var path: String
    /// Logic's track number; nil for channel strips of projects whose arrangement list couldn't be read.
    public var position: Int?
    /// Byte offset of the track in ProjectData: identifies it within the project (the inspector scrolls to it).
    public var offset: Int
    public var kind: TrackKind
    public var isHidden: Bool
    /// Display fields.
    public var name: String
    public var objectName: String
    public var channel: String
    /// Folded track name, object name and channel.
    public var text: String
    /// Folded names of the plug-ins the file itself names (Apple stock); other plug-ins are found through `fingerprints`.
    public var pluginText: String
    /// `|fingerprint|fingerprint|` of the track's plug-ins (for names that need the AU registry).
    public var fingerprints: String
    /// Folded project name.
    public var projectText: String

    /// One row per track: every arrangement track, or — for projects whose arrangement list couldn't be read — each user-visible channel strip.
    public static func rows(for summary: ProjectSummary) -> [TrackSearchRow] {
        let project = SearchMatcher.fold(ProjectBundle.bundleName(URL(fileURLWithPath: summary.path)))
        return summary.tracks.compactMap { t in
            let position = t.position
            // Numbered arrangement tracks, plus (when the arrangement list wasn't found) the channel strips Logic shows as tracks.
            guard position != nil || t.isUserVisibleKind else { return nil }
            let plugins = ([t.instrument].compactMap { $0 }) + t.midiFx + t.audioFx
            var seen = Set<String>()
            let unique = plugins.filter { seen.insert($0.fingerprint).inserted }
            let object = t.objectName ?? ""
            let parts = [t.displayName, object, t.name]
            return TrackSearchRow(
                path: summary.path, position: position, offset: t.offset, kind: t.kind, isHidden: t.isHidden,
                name: t.displayName, objectName: object, channel: t.name,
                text: SearchMatcher.fold(parts.joined(separator: "\n")),
                pluginText: SearchMatcher.fold(unique.compactMap(\.displayName).joined(separator: "\n")),
                fingerprints: unique.isEmpty ? "" : "|" + unique.map(\.fingerprint).joined(separator: "|") + "|",
                projectText: project)
        }
    }
}

/// What the user typed, prepared for the database: folded terms, and for each term the fingerprints of installed
/// plug-ins whose registry name contains it.
public struct TrackSearchQuery: Equatable, Sendable {
    public enum Visibility: Sendable { case include, exclude, only }

    /// Free terms: each must be found in the track's name/object/channel/plug-ins, or in the project's name.
    public var terms: [String]
    public var pluginFingerprints: [[String]]
    /// Field-specific narrowing (all combined with AND): terms that must be in the project name / in the track's own
    /// names / among its plug-ins (with the registry fingerprints each plug-in term resolved to).
    public var projectTerms: [String] = []
    public var nameTerms: [String] = []
    public var pluginTerms: [String] = []
    public var pluginTermFingerprints: [[String]] = []
    /// Restrict to these kinds; empty = any.
    public var kinds: Set<TrackKind> = []
    public var hidden: Visibility = .include

    public init(terms: [String], pluginFingerprints: [[String]] = []) {
        self.terms = terms
        self.pluginFingerprints = pluginFingerprints
    }

    /// Build from raw user text; `fingerprints(forTerm:)` resolves plug-in names through the registry.
    public init(text: String, fingerprints: (String) -> [String] = { _ in [] }) {
        let t = SearchMatcher.terms(of: text)
        self.init(terms: t, pluginFingerprints: t.map(fingerprints))
    }

    public var isEmpty: Bool { terms.isEmpty && projectTerms.isEmpty && nameTerms.isEmpty && pluginTerms.isEmpty && kinds.isEmpty }
}

public struct TrackHit: Equatable, Sendable {
    public var path: String
    public var position: Int?
    public var offset: Int
    public var kind: TrackKind
    public var isHidden: Bool
    public var name: String
    public var objectName: String
    public var channel: String
    public var pluginFingerprints: [String]
    public init(path: String, position: Int?, offset: Int, kind: TrackKind, isHidden: Bool, name: String, objectName: String, channel: String, pluginFingerprints: [String]) {
        self.path = path; self.position = position; self.offset = offset; self.kind = kind; self.isHidden = isHidden
        self.name = name; self.objectName = objectName; self.channel = channel; self.pluginFingerprints = pluginFingerprints
    }
}

public struct TrackSearchResult: Equatable, Sendable {
    public var hits: [TrackHit]
    /// Number of matching tracks in the whole library (may exceed `hits.count` when the limit cut the list).
    public var total: Int
    public init(hits: [TrackHit], total: Int) { self.hits = hits; self.total = total }
}

/// Project-level matching for the search (everything the old list search covered): a project is a result when its
/// name, any of its track/object names, or any of its plug-ins match — even if no per-track row exists for it.
public enum ProjectSearch {
    public struct Query: Equatable, Sendable {
        public var terms: [String]
        public var projectTerms: [String]
        public var nameTerms: [String]
        public var pluginTerms: [String]
        /// Kind / hidden restrictions only make sense for individual tracks; projects don't match while one is set.
        public var restrictsTracks: Bool
        public init(terms: [String] = [], projectTerms: [String] = [], nameTerms: [String] = [], pluginTerms: [String] = [], restrictsTracks: Bool = false) {
            self.terms = terms; self.projectTerms = projectTerms; self.nameTerms = nameTerms; self.pluginTerms = pluginTerms
            self.restrictsTracks = restrictsTracks
        }
        public var isEmpty: Bool { terms.isEmpty && projectTerms.isEmpty && nameTerms.isEmpty && pluginTerms.isEmpty }
    }

    /// - Parameters: `projectName` and `pluginText` are folded; `entry.searchText` already is.
    public static func matches(_ q: Query, entry: ProjectListEntry, projectName: String, pluginText: String) -> Bool {
        guard !q.isEmpty, !q.restrictsTracks else { return false }
        func has(_ haystack: String, _ terms: [String]) -> Bool { SearchMatcher.matches(haystack: haystack, terms: terms) }
        // Free terms: each anywhere. (`searchText` = project name + track, channel and object names + alternatives.)
        for t in q.terms where !has(entry.searchText, [t]) && !has(pluginText, [t]) { return false }
        return has(projectName, q.projectTerms) && has(entry.searchText, q.nameTerms) && has(pluginText, q.pluginTerms)
    }
}
