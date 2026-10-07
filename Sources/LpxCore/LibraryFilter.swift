import Foundation

/// Filters applied to a folder's project list (besides the text query).
public struct LibraryFilter: Equatable, Sendable {
    public var similarity: SimilarityAxis?
    public var onlyMissingPlugins: Bool

    public init(similarity: SimilarityAxis? = nil, onlyMissingPlugins: Bool = false) {
        self.similarity = similarity
        self.onlyMissingPlugins = onlyMissingPlugins
    }

    public var isActive: Bool { similarity != nil || onlyMissingPlugins }

    /// Keeps the paths that pass every active filter. Projects that haven't been read yet
    /// (no entry) can't be judged, so they're excluded while a filter is active.
    public func apply(to paths: [String], entries: [String: ProjectListEntry], installed: Set<String>?) -> [String] {
        guard isActive else { return paths }
        return paths.filter { path in
            guard let entry = entries[path] else { return false }
            if let similarity, !similarity.matches(entry.metadata) { return false }
            if onlyMissingPlugins {
                // Unknown registry ⇒ can't call anything missing.
                guard installed != nil,
                      !CompatibilityVerdict.evaluate(plugins: entry.plugins.map(\.ref), installed: installed).missing.isEmpty else { return false }
            }
            return true
        }
    }
}
