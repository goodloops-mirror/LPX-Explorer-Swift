import Foundation

/// Track scanner. Tracks are anchored on a 16-byte name field opening with 0x20
/// (NUL-padded ASCII) immediately followed by an 8-byte descriptor whose 4th byte has
/// the top two bits set. The pipeline mirrors the Rust parser:
/// `findTracks → assignAUs → assignUserNames → assignRegistryNames → synthesizeFolderTracks`.
public enum TrackFinder {
    private static let nameFieldLen = 16
    private static let descriptorLen = 8

    public static func findTracks(_ raw: [UInt8]) -> [Track] { raw.withUnsafeBufferPointer { findTracks(in: $0) } }

    public static func findTracks(in raw: UnsafeBufferPointer<UInt8>) -> [Track] {
        var tracks: [Track] = []
        let n = raw.count
        var i = 1 // a NUL must precede the 0x20 name marker
        while i + nameFieldLen + descriptorLen <= n, let hit = ByteSearch.indexOf(0x20, in: raw, from: i) {
            i = hit
            guard i + nameFieldLen + descriptorLen <= n, raw[i - 1] == 0x00 else { i += 1; continue }
            let d = i + nameFieldLen
            // Final type-code byte must have the high two bits set (filters stray 0x20 bytes).
            guard raw[d + 3] & 0xC0 == 0xC0, let name = decodeName(raw, at: i) else { i += 1; continue }
            let descriptor = (raw[d], raw[d + 1], raw[d + 2], raw[d + 4])
            tracks.append(Track(name: name, kind: classify(head: descriptor.0, b1: descriptor.1, b2: descriptor.2),
                                offset: i, isActive: descriptor.2 & 0x04 != 0 || descriptor.3 != 0))
            i += nameFieldLen // skip the whole record
        }
        return tracks
    }

    private static func decodeName(_ raw: UnsafeBufferPointer<UInt8>, at i: Int) -> String? {
        var end = 1
        while end < nameFieldLen {
            let b = raw[i + end]
            if b == 0 { break }
            if b < 0x20 || b > 0x7e { return nil }
            end += 1
        }
        for k in end..<nameFieldLen where raw[i + k] != 0 { return nil } // rest must be NUL padding
        let name = String(decoding: UnsafeBufferPointer(rebasing: raw[(i + 1) ..< (i + end)]), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func classify(head: UInt8, b1: UInt8, b2: UInt8) -> TrackKind {
        switch head {
        case 0x89: return .master
        case 0x49: return .output
        case 0xE9: return .bus
        case 0xAB: return b1 == 0xF5 ? .aux : .audio
        case 0x29: return (b2 == 0xF3 || b2 == 0xF7) ? .instrument : .input
        default: return .unknown
        }
    }

    // MARK: assignment

    /// Last index whose offset is <= `offset` in an offset-sorted track list.
    private static func owner(of offset: Int, in tracks: [Track]) -> Int? {
        var lo = 0, hi = tracks.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if tracks[mid].offset <= offset { lo = mid + 1 } else { hi = mid }
        }
        return lo == 0 ? nil : lo - 1
    }

    /// Route each AU to its nearest preceding track. Instruments (`aumu`) attach only
    /// to instrument tracks, first one wins; `aumf`/`aumi` go to midiFx, the rest to audioFx.
    public static func assignAUs(_ tracks: inout [Track], _ aus: [AURef]) {
        guard !tracks.isEmpty else { return }
        tracks.sort { $0.offset < $1.offset }
        for au in aus.sorted(by: { $0.offset < $1.offset }) {
            guard let idx = owner(of: au.offset, in: tracks) else { continue }
            switch au.typeCode {
            case "aumu":
                if tracks[idx].kind == .instrument && tracks[idx].instrument == nil { tracks[idx].instrument = au }
            case "aumf", "aumi": tracks[idx].midiFx.append(au)
            default: tracks[idx].audioFx.append(au)
            }
        }
    }

    /// Name each track from the nearest following region cluster. Auto-named clusters
    /// ("Audio 3") are skipped so a later rename wins; existing names are never overwritten.
    public static func assignUserNames(_ tracks: inout [Track], _ clusters: [RegionCluster]) {
        guard !tracks.isEmpty else { return }
        tracks.sort { $0.offset < $1.offset }
        for cluster in clusters.sorted(by: { $0.firstOffset < $1.firstOffset }) {
            if Regions.isAutoTrackName(cluster.baseName) { continue }
            guard let idx = owner(of: cluster.firstOffset, in: tracks) else { continue }
            if tracks[idx].userName == nil { tracks[idx].userName = cluster.baseName }
        }
    }

    /// Fill remaining names from the registry: audio by strip id ("Audio N" ↔ strip N),
    /// instruments by 1-based position in the offset-sorted track list.
    public static func assignRegistryNames(_ tracks: inout [Track], _ registry: [TrackRegistryEntry]) {
        guard !tracks.isEmpty, !registry.isEmpty else { return }
        pairAudio(&tracks, registry)
        pairInstruments(&tracks, registry)
    }

    static func parseAudioStripNumber(_ name: String) -> UInt16? {
        guard name.hasPrefix("Audio ") else { return nil }
        return UInt16(name.dropFirst("Audio ".count).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func pairAudio(_ tracks: inout [Track], _ registry: [TrackRegistryEntry]) {
        // Registry entries beyond the project's last audio strip are song titles / markers sharing the shape.
        let maxStrip = tracks.filter { $0.kind == .audio && $0.isActive }.compactMap { parseAudioStripNumber($0.name) }.max() ?? 0
        var byStripID: [UInt16: TrackRegistryEntry] = [:]
        for e in registry where e.kind == .audio && e.stripID > 0 && e.stripID <= maxStrip { byStripID[e.stripID] = e }
        guard !byStripID.isEmpty else { return }
        for i in tracks.indices where tracks[i].kind == .audio && tracks[i].isActive {
            guard let n = parseAudioStripNumber(tracks[i].name), let e = byStripID[n] else { continue }
            // The registry name only fills a gap and is skipped when it merely echoes the strip's default
            // name ("Audio 3" for strip 3).
            if tracks[i].userName == nil, e.name != tracks[i].name { tracks[i].userName = e.name }
        }
    }

    private static func pairInstruments(_ tracks: inout [Track], _ registry: [TrackRegistryEntry]) {
        let order = tracks.indices.sorted { tracks[$0].offset < tracks[$1].offset }
        for e in registry where e.kind == .instrument && e.stripID != 0 {
            let pos = Int(e.stripID) - 1
            guard pos < order.count else { continue }
            let idx = order[pos]
            guard tracks[idx].kind == .instrument && tracks[idx].isActive else { continue }
            if tracks[idx].userName == nil { tracks[idx].userName = e.name }
        }
    }

    /// Folders and summing stacks have no channel-strip record; add them from the registry.
    /// Idempotent: entries whose offset already exists are skipped.
    public static func synthesizeFolderTracks(_ tracks: inout [Track], _ registry: [TrackRegistryEntry]) {
        let existing = Set(tracks.map(\.offset))
        for e in registry where (e.kind == .folder || e.kind == .summingStack) && !existing.contains(e.offset) {
            tracks.append(Track(name: e.name, userName: e.name, kind: e.kind, offset: e.offset, isActive: true))
        }
        tracks.sort { $0.offset < $1.offset }
    }
}
