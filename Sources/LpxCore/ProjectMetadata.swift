import Foundation

public struct ProjectMetadata: Equatable, Hashable, Sendable, Codable {
    public var songKey = "?"
    public var songGender = "?"
    public var bpm = 0.0
    public var sigNumerator = 4
    public var sigDenominator = 4
    public var trackCount = 0
    public var sampleRate = 0
    public var audioFileCount = 0
    public var impulseResponseCount = 0
    public var frameRateIndex = 0
    public init() {}
}

public enum MetadataError: Error, Equatable { case invalid(String) }

public enum MetadataParser {
    /// Parse a `MetaData.plist` payload (XML or binary). Missing or mistyped
    /// keys fall back to defaults; only an unreadable plist throws.
    public static func parse(_ data: Data) throws -> ProjectMetadata {
        let root: Any
        do {
            root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw MetadataError.invalid(error.localizedDescription)
        }
        guard let dict = root as? [String: Any] else {
            throw MetadataError.invalid("plist root is not a dictionary")
        }
        var m = ProjectMetadata()
        if let v = dict["SongKey"] as? String { m.songKey = v }
        if let v = dict["SongGenderKey"] as? String { m.songGender = v }
        if let v = (dict["BeatsPerMinute"] as? NSNumber)?.doubleValue { m.bpm = v }
        m.sigNumerator = uint(dict["SongSignatureNumerator"]) ?? 4
        m.sigDenominator = uint(dict["SongSignatureDenominator"]) ?? 4
        m.trackCount = uint(dict["NumberOfTracks"]) ?? 0
        m.sampleRate = uint(dict["SampleRate"]) ?? 0
        m.audioFileCount = (dict["AudioFiles"] as? [Any])?.count ?? 0
        m.impulseResponseCount = (dict["ImpulsResponsesFiles"] as? [Any])?.count ?? 0
        m.frameRateIndex = uint(dict["FrameRateIndex"]) ?? 0
        return m
    }

    private static func uint(_ v: Any?) -> Int? {
        guard let n = v as? NSNumber, n.intValue >= 0 else { return nil }
        return n.intValue
    }
}
