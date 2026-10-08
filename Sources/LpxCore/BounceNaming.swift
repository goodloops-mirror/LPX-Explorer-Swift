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
}

/// Decides whether an audio file is a bounce of a given project, by name.
///
/// Convention: a bounce is named like the project (including its version number); anything after that name is an
/// appendix we ignore — `MIX ALL`, an SMPTE timestamp (`01.02.03.04`), or `STM#nn` for the nn-th stem.
/// Matching is case- and accent-insensitive and the project name must end at a word boundary, so "Song v1" does not
/// claim "Song v10 MIX ALL".
public enum BounceNaming {
    public static let audioExtensions: Set<String> = ["wav", "aif", "aiff", "caf", "mp3", "m4a", "aac", "flac"]
    private static let separators = CharacterSet(charactersIn: " _-.")
    private static let timestamp = try! Regex(#"\d{1,2}[._:;\-]\d{2}[._:;\-]\d{2}[._:;\-]\d{2,3}"#)
    private static let mixAll = try! Regex(#"mix[ _\-]?all"#)

    public static func match(fileName: String, projectName: String) -> BounceMatch? {
        var base = fileName
        if let dot = base.lastIndex(of: "."), audioExtensions.contains(base[base.index(after: dot)...].lowercased()) {
            base = String(base[..<dot])
        }
        let name = SearchMatcher.fold(base), project = SearchMatcher.fold(projectName)
        guard !project.isEmpty, name.hasPrefix(project) else { return nil }
        let rest = String(name.dropFirst(project.count))
        if rest.isEmpty { return BounceMatch(kind: .mix, stemNumber: nil) }
        guard let first = rest.unicodeScalars.first, separators.contains(first) else { return nil }   // word boundary

        var r = rest.trimmingCharacters(in: separators)
        func isTimestampOrNothing(_ s: String) -> Bool {
            let t = s.trimmingCharacters(in: separators)
            return t.isEmpty || t.wholeMatch(of: timestamp) != nil
        }
        if r.hasPrefix("stm#") {
            let digits = r.dropFirst(4).prefix(while: \.isNumber)
            guard let n = Int(digits), isTimestampOrNothing(String(r.dropFirst(4 + digits.count))) else { return nil }
            return BounceMatch(kind: .stem, stemNumber: n)
        }
        if let m = r.prefixMatch(of: mixAll) { r = String(r[m.range.upperBound...]) }
        return isTimestampOrNothing(r) ? BounceMatch(kind: .mix, stemNumber: nil) : nil
    }
}
