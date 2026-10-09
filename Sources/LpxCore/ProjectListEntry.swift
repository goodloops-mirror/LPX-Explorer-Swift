import Foundation

/// A plug-in used by a project, deduplicated by fingerprint.
public struct PluginUse: Codable, Equatable, Hashable, Sendable {
    /// First occurrence of this fingerprint (keeps the parser-recovered display name).
    public var ref: AURef
    public var instances: Int
    public var fingerprint: String { ref.fingerprint }
}

/// Everything the library list, search, filters, verdicts and the plug-in view need about a project,
/// in a few hundred bytes. The heavy parts of a `ProjectSummary` (tracks, alternatives with image
/// paths, …) are loaded on demand when a project is selected.
public struct ProjectListEntry: Codable, Equatable, Hashable, Sendable {
    public var path: String
    public var metadata: ProjectMetadata
    public var plugins: [PluginUse]
    public var visibleTrackCount: Int
    public var alternativeCount: Int
    /// mtime/size of the ProjectData that was parsed — the freshness stamp.
    public var projectDataMTime: Int64
    public var projectDataSize: UInt64
    /// Case/diacritic-folded text that search matches against: project name, custom and channel track
    /// names, and alternative names. (Plug-in names depend on the AU registry and are added at query time.)
    public var searchText: String
    /// "lso" for a single-file Logic 4–9 project: listed by name, contents not read. Optional so entries cached before this
    /// existed still decode.
    public var legacyFormat: String?
    public var isLegacy: Bool { legacyFormat != nil }
    /// Size of the project on disk and its Finder dates as found when it was parsed (the list refreshes the dates in the
    /// background, see `ProjectFileInfo`). Optional so entries cached before these existed still decode.
    public var sizeBytes: UInt64?
    public var createdAt: Int64?
    public var modifiedAt: Int64?

    public init(summary: ProjectSummary) {
        legacyFormat = summary.legacyFormat
        sizeBytes = summary.stats.sizeBytes
        createdAt = summary.stats.createdAt
        modifiedAt = summary.stats.modifiedAt
        path = summary.path
        metadata = summary.metadata
        projectDataMTime = summary.projectDataMTime
        projectDataSize = summary.projectDataSize
        alternativeCount = summary.alternatives.count
        // Arrangement tracks (they have a position) all count; the fallback channel-strip view only its visible kinds.
        visibleTrackCount = summary.tracks.filter { $0.position != nil || $0.isUserVisibleKind }.count

        var order: [String] = []
        var byFingerprint: [String: PluginUse] = [:]
        for ref in summary.fingerprints {
            if var use = byFingerprint[ref.fingerprint] {
                use.instances += 1
                if use.ref.displayName == nil, ref.displayName != nil { use.ref = ref }
                byFingerprint[ref.fingerprint] = use
            } else {
                order.append(ref.fingerprint)
                byFingerprint[ref.fingerprint] = PluginUse(ref: ref, instances: 1)
            }
        }
        plugins = order.compactMap { byFingerprint[$0] }

        var parts = [ProjectBundle.bundleName(URL(fileURLWithPath: summary.path))]
        for t in summary.tracks {
            if !t.name.isEmpty { parts.append(t.name) }
            if let u = t.userName { parts.append(u) }
            if let o = t.objectName { parts.append(o) }
        }
        // A lone alternative just repeats the project name.
        if summary.alternatives.count > 1 { parts += summary.alternatives.map(\.displayName) }
        searchText = SearchMatcher.fold(parts.joined(separator: "\n"))
    }

    public var name: String { ProjectBundle.bundleName(URL(fileURLWithPath: path)) }
}
