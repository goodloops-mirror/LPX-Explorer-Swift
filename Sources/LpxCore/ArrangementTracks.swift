import Foundation

public enum ArrangementTracks {
    /// Key shared by every folder track (they live on one built-in "(Folder)" object).
    static let folderKey: UInt32 = 0x10

    /// Turn the arrangement records into tracks (position order), resolving names, objects and channel strips.
    ///
    /// - Parameters:
    ///   - texts: `qSxT` name texts by id. A non-zero `nameTextID` is the track's own name; 0 ⇒ the object's name.
    ///   - objects: registry-shaped records of any class, looked up by key.
    ///   - strips: channel strips (from `TrackFinder`) with their plug-ins already assigned.
    public static func build(records: [ArrangementRecord], texts: [UInt32: String], objects: [ObjectRecord], strips: [Track]) -> [Track] {
        var objectByKey: [UInt32: ObjectRecord] = [:]
        for o in objects where objectByKey[o.key] == nil { objectByKey[o.key] = o }
        let ordered = strips.sorted { $0.offset < $1.offset }

        return records.map { r in
            let object = objectByKey[r.objectKey]
            let strip = object.flatMap { link($0, ordered) }
            let own = r.nameTextID != 0 ? texts[r.nameTextID] : nil
            let name = own ?? object?.name
            let kind: TrackKind = strip?.kind ?? (r.objectKey == folderKey ? .folder : .unknown)
            return Track(
                name: strip?.name ?? "", userName: (name?.isEmpty ?? true) ? nil : name, kind: kind,
                offset: r.offset, isActive: true,
                instrument: strip?.instrument, midiFx: strip?.midiFx ?? [], audioFx: strip?.audioFx ?? [],
                position: r.position, objectName: object?.name, isHidden: r.isHidden)
        }
    }

    /// The channel strip of an object. Its registry trailer stores a strip id: for audio objects that is the number
    /// in "Audio N"; for instruments it is the 1-based position of the strip in storage order. Recognised classes
    /// use their own rule; for the others try the instrument ordinal first, then the audio name.
    private static func link(_ object: ObjectRecord, _ strips: [Track]) -> Track? {
        let kind = TrackRegistry.kind(forClass: object.classNumber)
        for id in [object.stripID, object.altStripID] where id > 0 {
            let s = Int(id)
            let audio = strips.first { $0.kind == .audio && $0.name == "Audio \(s)" }
            let instrument = s <= strips.count && strips[s - 1].kind == .instrument ? strips[s - 1] : nil
            let hit: Track?
            switch kind {
            case .audio?: hit = audio
            case .instrument?: hit = instrument
            default: hit = instrument ?? audio
            }
            if let hit { return hit }
        }
        return nil
    }
}
