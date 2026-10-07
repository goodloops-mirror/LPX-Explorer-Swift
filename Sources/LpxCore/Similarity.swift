import Foundation

/// Pivots for "find similar projects" (key, tempo, or both).
public enum SimilarityAxis: Equatable, Sendable {
    case key(songKey: String, songGender: String)
    case bpm(Double)
    case keyAndBPM(songKey: String, songGender: String, bpm: Double)

    /// The tempo window is the nearest multiple of 5 to the target, ±2 (a 5-wide band):
    /// exact matching was too narrow on real libraries, and fixed buckets split neighbours.
    private static let bucket = 5.0
    private static let tolerance = 2.0

    public func matches(_ metadata: ProjectMetadata) -> Bool {
        switch self {
        case let .key(k, g): return Self.keyMatches(metadata, k, g)
        case let .bpm(target): return Self.bpmInBand(metadata.bpm, target)
        case let .keyAndBPM(k, g, target): return Self.keyMatches(metadata, k, g) && Self.bpmInBand(metadata.bpm, target)
        }
    }

    /// "C major", "around 92 BPM (88–92)", or both.
    public var label: String {
        switch self {
        case let .key(k, g): return Self.keyLabel(k, g)
        case let .bpm(b): return Self.bpmLabel(b)
        case let .keyAndBPM(k, g, b): return "\(Self.keyLabel(k, g)) \(Self.bpmLabel(b))"
        }
    }

    // MARK: axes for a given project (nil when the value is unknown)

    public static func key(of m: ProjectMetadata) -> SimilarityAxis? {
        isKeyKnown(m) ? .key(songKey: m.songKey, songGender: m.songGender) : nil
    }

    public static func bpm(of m: ProjectMetadata) -> SimilarityAxis? { m.bpm > 0 ? .bpm(m.bpm) : nil }

    public static func keyAndBPM(of m: ProjectMetadata) -> SimilarityAxis? {
        isKeyKnown(m) && m.bpm > 0 ? .keyAndBPM(songKey: m.songKey, songGender: m.songGender, bpm: m.bpm) : nil
    }

    // MARK: internals

    private static func isKeyKnown(_ m: ProjectMetadata) -> Bool { m.songKey != "?" && m.songGender != "?" }

    private static func keyMatches(_ m: ProjectMetadata, _ key: String, _ gender: String) -> Bool {
        guard key != "?", gender != "?", isKeyKnown(m) else { return false }
        return m.songKey == key && m.songGender == gender
    }

    private static func center(_ bpm: Double) -> Double { (bpm / bucket).rounded() * bucket }

    private static func bpmInBand(_ candidate: Double, _ target: Double) -> Bool {
        guard candidate > 0, target > 0 else { return false }
        let c = center(target)
        return candidate >= c - tolerance && candidate <= c + tolerance
    }

    private static func keyLabel(_ key: String, _ gender: String) -> String { "\(key) \(gender.lowercased())" }

    private static func bpmLabel(_ bpm: Double) -> String {
        let c = Int(center(bpm))
        return "around \(Int(bpm.rounded())) BPM (\(c - Int(tolerance))–\(c + Int(tolerance)))"
    }
}
