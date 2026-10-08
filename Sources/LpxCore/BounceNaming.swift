import Foundation

public enum BounceKind: String, Equatable, Sendable, Codable {
    /// The full mix of the project.
    case mix
    /// One stem ("… STM#01").
    case stem
}

public struct BounceMatch: Equatable, Sendable {
    public var kind: BounceKind
    /// 1-based stem number for stems.
    public var stemNumber: Int?
    /// The stem's own name as written in the file ("PIANO", "STRINGS 1").
    public var stemLabel: String?
    /// A mix variant such as "MIX ALL [30 SECS ALT 1]" — a mix, but not the main one.
    public var isAlternative: Bool

    public init(kind: BounceKind, stemNumber: Int? = nil, stemLabel: String? = nil, isAlternative: Bool = false) {
        self.kind = kind; self.stemNumber = stemNumber; self.stemLabel = stemLabel; self.isAlternative = isAlternative
    }
}

/// Decides whether an audio file is a bounce of a given project, by name.
///
/// Convention: a bounce is named like the project (including its version number); anything after that name is an
/// appendix we ignore — `MIX ALL`, an SMPTE timestamp (`01.02.03.04`), or `STM#nn` for the nn-th stem.
/// Matching is case- and accent-insensitive and the project name must end at a word boundary, so "Song v1" does not
/// claim "Song v10 MIX ALL".
public enum BounceNaming {
    public static let audioExtensions: Set<String> = ["wav", "aif", "aiff", "caf", "mp3", "m4a", "aac", "flac"]
    /// Formats with lossy compression: preferred less than a lossless file of the same mix.
    public static let lossyExtensions: Set<String> = ["mp3", "m4a", "aac"]

    private static let separators = CharacterSet(charactersIn: " _-.")
    private static let mixAll = try! Regex(#"mix[ _\-]?all"#)
    private static let stem = try! Regex(#"stm ?#(\d+)"#)
    /// `@09595923` (Logic's bounce start as HHMMSSFF) or a dotted / dashed SMPTE time.
    private static let atStamp = try! Regex(#"@\d{4,9}"#)
    private static let smpte = try! Regex(#"\d{1,2}[._:;\-]\d{2}[._:;\-]\d{2}[._:;\-]\d{2,3}"#)
    private static let bracket = try! Regex(#"\[[^\]]*\]"#)

    public static func match(fileName: String, projectName: String) -> BounceMatch? {
        var base = fileName
        if let dot = base.lastIndex(of: "."), audioExtensions.contains(base[base.index(after: dot)...].lowercased()) {
            base = String(base[..<dot])
        }
        let name = SearchMatcher.fold(base), project = SearchMatcher.fold(projectName)
        guard !project.isEmpty, name.hasPrefix(project) else { return nil }
        let rest = String(name.dropFirst(project.count))
        if rest.isEmpty { return BounceMatch(kind: .mix) }
        guard let first = rest.unicodeScalars.first, separators.contains(first) else { return nil }   // word boundary

        var r = rest.trimmingCharacters(in: separators)

        // Stem: "STM#01 PIANO" — everything after the number is the stem's own name (minus a trailing timestamp).
        if let m = r.prefixMatch(of: stem), let number = Int(m.output[1].substring ?? "") {
            let label = stemLabel(in: base)
            return BounceMatch(kind: .stem, stemNumber: number, stemLabel: label)
        }

        // Mix: optional "MIX ALL", then any of @timestamp / SMPTE / [tag].
        if let m = r.prefixMatch(of: mixAll) { r = String(r[m.range.upperBound...]).trimmingCharacters(in: separators) }
        var alternative = false
        while !r.isEmpty {
            if let m = r.prefixMatch(of: atStamp) ?? r.prefixMatch(of: smpte) {
                r = String(r[m.range.upperBound...]).trimmingCharacters(in: separators)
            } else if let m = r.prefixMatch(of: bracket) {
                alternative = true
                r = String(r[m.range.upperBound...]).trimmingCharacters(in: separators)
            } else {
                return nil
            }
        }
        return BounceMatch(kind: .mix, isAlternative: alternative)
    }

    /// The text after "STM#nn" in the original file name, without a trailing timestamp.
    private static func stemLabel(in base: String) -> String? {
        guard let m = base.firstMatch(of: try! Regex(#"(?i)stm ?#\d+"#)) else { return nil }
        var label = String(base[m.range.upperBound...]).trimmingCharacters(in: separators)
        if let t = label.firstMatch(of: atStamp) { label = String(label[..<t.range.lowerBound]).trimmingCharacters(in: separators) }
        return label.isEmpty ? nil : label
    }
}
