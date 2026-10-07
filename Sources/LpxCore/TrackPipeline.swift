import Foundation

/// The full ProjectData → tracks pipeline, in the order the Rust parser runs it.
public enum TrackPipeline {
    /// The legacy channel-strip view (the Rust parser's output): every channel strip with plug-ins and a best-effort
    /// name. Logic creates hundreds of unused default strips, so this is NOT the arrangement.
    public static func channelStrips(in raw: UnsafeBufferPointer<UInt8>, aus: [AURef]) -> [Track] {
        var tracks = TrackFinder.findTracks(in: raw)
        TrackFinder.assignAUs(&tracks, aus)
        TrackFinder.assignUserNames(&tracks, Regions.cluster(Regions.findRecords(in: raw)))
        let registry = TrackRegistry.findRecords(in: raw)
        TrackFinder.assignRegistryNames(&tracks, registry)
        TrackFinder.synthesizeFolderTracks(&tracks, registry)
        return tracks
    }

    public static func channelStrips(_ raw: [UInt8], aus: [AURef]) -> [Track] {
        raw.withUnsafeBufferPointer { channelStrips(in: $0, aus: aus) }
    }

    /// The project's tracks as Logic lists them: one per arrangement-list record, in track order, hidden tracks and
    /// folders included, each with its own name, its object, channel strip and plug-ins. Projects without a
    /// recognisable list fall back to the filtered channel strips.
    public static func tracks(in raw: UnsafeBufferPointer<UInt8>, aus: [AURef]) -> [Track] {
        let strips = channelStrips(in: raw, aus: aus)
        let records = ArrangementList.records(in: raw)
        guard !records.isEmpty else { return relevant(strips) }
        return ArrangementTracks.build(records: records, texts: NameTexts.find(in: raw), objects: TrackObjects.find(in: raw), strips: strips)
    }

    public static func tracks(_ raw: [UInt8], aus: [AURef]) -> [Track] {
        raw.withUnsafeBufferPointer { tracks(in: $0, aus: aus) }
    }

    /// What's worth keeping per project: active user-visible tracks, plus active routing
    /// strips that carry plug-ins. Logic creates hundreds of default channel strips and
    /// ~256 buses per project that are not tracks; storing them would balloon the cache.
    public static func relevant(_ tracks: [Track]) -> [Track] {
        tracks.filter { $0.isActive && ($0.isUserVisibleKind || $0.hasInserts) }
    }
}
