import Foundation

/// Per-project text a query is matched against.
public struct SearchDocument: Equatable, Sendable {
    public var projectName: String
    public var pluginNames: [String]
    public var trackNames: [String]
    public var alternativeNames: [String]
    public init(projectName: String, pluginNames: [String] = [], trackNames: [String] = [], alternativeNames: [String] = []) {
        self.projectName = projectName
        self.pluginNames = pluginNames
        self.trackNames = trackNames
        self.alternativeNames = alternativeNames
    }
}

public enum SearchMatcher {
    /// Every whitespace-separated term in `query` must appear (case- and
    /// diacritic-insensitive) in the project name, a plug-in name or a track name.
    public static func matches(_ doc: SearchDocument, query: String) -> Bool {
        let terms = terms(of: query)
        if terms.isEmpty { return true }
        return matches(haystack: haystack(for: doc), terms: terms)
    }

    /// Fold once per project (when its summary lands), not once per keystroke.
    public static func haystack(for doc: SearchDocument) -> String {
        ([doc.projectName] + doc.pluginNames + doc.trackNames + doc.alternativeNames).map(fold).joined(separator: "\n")
    }

    public static func terms(of query: String) -> [String] {
        fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Byte-level substring search over the folded UTF-8 (≈10× faster than Foundation's `contains`
    /// on multi-KB haystacks, which matters when filtering thousands of projects per keystroke).
    public static func matches(haystack: String, terms: [String]) -> Bool {
        if terms.isEmpty { return true }
        var hay = haystack
        return hay.withUTF8 { h in
            terms.allSatisfy { term in
                var needle = term
                return needle.withUTF8 { n in
                    if n.isEmpty { return true }
                    guard h.count >= n.count, let hb = h.baseAddress, let nb = n.baseAddress else { return false }
                    return memmem(hb, h.count, nb, n.count) != nil
                }
            }
        }
    }

    public static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
