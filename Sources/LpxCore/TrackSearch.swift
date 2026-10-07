import Foundation

/// One searchable track, derived from a project summary and stored in SQLite (`tracks` table).
public struct TrackSearchRow: Equatable, Sendable {
    public var path: String
    public var position: Int
    public var kind: TrackKind
    public var isHidden: Bool
    /// Display fields.
    public var name: String
    public var objectName: String
    public var channel: String
    /// Folded text a search term is looked up in: track name, object name, channel, names of plug-ins the file itself names (Apple stock).
    public var text: String
    /// `|fingerprint|fingerprint|` of the track's plug-ins (for names that need the AU registry).
    public var fingerprints: String
    /// Folded project name.
    public var projectText: String

    /// One row per arrangement track (those with a track number); the fallback channel-strip view isn't searchable per track.
    public static func rows(for summary: ProjectSummary) -> [TrackSearchRow] {
        let project = SearchMatcher.fold(ProjectBundle.bundleName(URL(fileURLWithPath: summary.path)))
        return summary.tracks.compactMap { t in
            guard let position = t.position else { return nil }
            let plugins = ([t.instrument].compactMap { $0 }) + t.midiFx + t.audioFx
            var seen = Set<String>()
            let unique = plugins.filter { seen.insert($0.fingerprint).inserted }
            let object = t.objectName ?? ""
            let parts = [t.displayName, object, t.name] + unique.compactMap(\.displayName)
            return TrackSearchRow(
                path: summary.path, position: position, kind: t.kind, isHidden: t.isHidden,
                name: t.displayName, objectName: object, channel: t.name,
                text: SearchMatcher.fold(parts.joined(separator: "\n")),
                fingerprints: unique.isEmpty ? "" : "|" + unique.map(\.fingerprint).joined(separator: "|") + "|",
                projectText: project)
        }
    }
}

/// What the user typed, prepared for the database: folded terms, and for each term the fingerprints of installed
/// plug-ins whose registry name contains it.
public struct TrackSearchQuery: Equatable, Sendable {
    public var terms: [String]
    public var pluginFingerprints: [[String]]

    public init(terms: [String], pluginFingerprints: [[String]] = []) {
        self.terms = terms
        self.pluginFingerprints = pluginFingerprints
    }

    /// Build from raw user text; `fingerprints(forTerm:)` resolves plug-in names through the registry.
    public init(text: String, fingerprints: (String) -> [String] = { _ in [] }) {
        let t = SearchMatcher.terms(of: text)
        self.init(terms: t, pluginFingerprints: t.map(fingerprints))
    }

    public var isEmpty: Bool { terms.isEmpty }
}

public struct TrackHit: Equatable, Sendable {
    public var path: String
    public var position: Int
    public var kind: TrackKind
    public var isHidden: Bool
    public var name: String
    public var objectName: String
    public var channel: String
    public var pluginFingerprints: [String]
    public init(path: String, position: Int, kind: TrackKind, isHidden: Bool, name: String, objectName: String, channel: String, pluginFingerprints: [String]) {
        self.path = path; self.position = position; self.kind = kind; self.isHidden = isHidden
        self.name = name; self.objectName = objectName; self.channel = channel; self.pluginFingerprints = pluginFingerprints
    }
}

public struct TrackSearchResult: Equatable, Sendable {
    public var hits: [TrackHit]
    /// Number of matching tracks in the whole library (may exceed `hits.count` when the limit cut the list).
    public var total: Int
    public init(hits: [TrackHit], total: Int) { self.hits = hits; self.total = total }
}
