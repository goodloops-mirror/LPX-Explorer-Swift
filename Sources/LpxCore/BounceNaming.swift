import Foundation

public enum BounceKind: String, Equatable, Sendable, Codable {
    /// Any bounce of the project that is not a stem.
    case mix
    /// A stem ("… STM#01 …").
    case stem
}

public struct BounceMatch: Equatable, Sendable {
    public var kind: BounceKind
    /// The stem's number (`STM#nn`).
    public var stemNumber: Int?
    /// What follows the stem number in the file name ("PIANO").
    public var stemLabel: String?

    public init(kind: BounceKind, stemNumber: Int? = nil, stemLabel: String? = nil) {
        self.kind = kind; self.stemNumber = stemNumber; self.stemLabel = stemLabel
    }
}

/// Decides whether an audio file is a bounce of a project, by name — one rule:
///
///     the file name starts with the project's name (version number included); whatever follows is ignored.
///
/// Comparison ignores case and accents, and the project name must end where a word ends (so "Song v1" does not claim
/// "Song v10", nor "Song v10" claim "Song v10b"). The only thing read from the rest of the name is a stem marker
/// `STM#nn`, to tell stems from the mix.
public enum BounceNaming {
    public static let audioExtensions: Set<String> = ["wav", "aif", "aiff", "caf", "mp3", "m4a", "aac", "flac"]

    private static let stemMarker = try! Regex(#"(?i)stm ?#(\d+)"#)
    private static let separators = CharacterSet(charactersIn: " _-.")

    public static func match(fileName: String, projectName: String) -> BounceMatch? {
        var base = fileName
        if let dot = base.lastIndex(of: "."), audioExtensions.contains(base[base.index(after: dot)...].lowercased()) {
            base = String(base[..<dot])
        }
        let name = SearchMatcher.fold(base), project = SearchMatcher.fold(projectName)
        guard !project.isEmpty, name.hasPrefix(project) else { return nil }
        if let next = name.dropFirst(project.count).unicodeScalars.first, CharacterSet.alphanumerics.contains(next) { return nil }

        if let m = base.firstMatch(of: stemMarker), let number = Int(m.output[1].substring ?? "") {
            let label = String(base[m.range.upperBound...]).trimmingCharacters(in: separators)
            return BounceMatch(kind: .stem, stemNumber: number, stemLabel: label.isEmpty ? nil : label)
        }
        return BounceMatch(kind: .mix)
    }
}
