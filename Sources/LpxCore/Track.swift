import Foundation

public enum TrackKind: String, Codable, Sendable, Equatable {
    case audio, instrument, folder
    case summingStack = "summing-stack"
    case master, output, bus, aux, input, unknown
}

public struct Track: Equatable, Sendable, Codable {
    /// Channel-strip default name, e.g. "Inst 1" / "Audio 3".
    public var name: String
    /// User-given name recovered from region clusters or the registry.
    public var userName: String?
    public var kind: TrackKind
    public var offset: Int
    public var isActive: Bool
    public var instrument: AURef?
    /// Plug-ins the parser filed under MIDI FX: `aumi` processors AND `aumf` music effects (mirrors the
    /// legacy parser). `aumf` are really audio effects; presentation code should group by `typeCode`.
    public var midiFx: [AURef]
    public var audioFx: [AURef]
    public var subNumber: UInt32?
    public var parentOffset: Int?
    /// Logic's sequential track number (1 = top track; hidden tracks count). nil when the file doesn't
    /// give a reliable one (tracks without regions/events, or with conflicting entries).
    public var position: Int?
    /// Name of the object (channel strip) the track belongs to; several tracks can share one object and each has its own name.
    public var objectName: String? = nil
    /// Hidden in Logic's arrangement (hidden tracks still have a track number).
    public var isHidden: Bool = false

    public init(name: String, userName: String? = nil, kind: TrackKind, offset: Int, isActive: Bool,
                instrument: AURef? = nil, midiFx: [AURef] = [], audioFx: [AURef] = [],
                subNumber: UInt32? = nil, parentOffset: Int? = nil, position: Int? = nil,
                objectName: String? = nil, isHidden: Bool = false) {
        self.name = name; self.userName = userName; self.kind = kind; self.offset = offset
        self.isActive = isActive; self.instrument = instrument; self.midiFx = midiFx
        self.audioFx = audioFx; self.subNumber = subNumber; self.parentOffset = parentOffset
        self.position = position
        self.objectName = objectName; self.isHidden = isHidden
    }

    /// What the user sees in Logic's Tracks area.
    public var displayName: String { userName ?? name }

    /// Audio, instrument, folder and summing-stack tracks appear in Logic's Tracks area;
    /// master/output/bus/aux/input are routing strips.
    public var isUserVisibleKind: Bool {
        kind == .audio || kind == .instrument || kind == .folder || kind == .summingStack
    }

    public var hasInserts: Bool { instrument != nil || !midiFx.isEmpty || !audioFx.isEmpty }
}

public struct RegionRecord: Equatable, Sendable { public var offset: Int; public var name: String }

public struct RegionCluster: Equatable, Sendable {
    public var baseName: String
    public var firstOffset: Int
    public var lastOffset: Int
    public var count: Int
}

public struct TrackRegistryEntry: Equatable, Sendable {
    public var offset: Int
    public var name: String
    public var kind: TrackKind
    public var trackID: UInt16
    public var stripID: UInt16
}
