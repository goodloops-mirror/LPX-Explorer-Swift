import Foundation

public enum BounceFilter: String, CaseIterable, Sendable {
    case any = "Any", has = "Has bounce", none = "No bounce"

    /// Whether a project passes, given whether it has a bounce.
    public func allows(hasBounce: Bool) -> Bool {
        switch self { case .any: true; case .has: hasBounce; case .none: !hasBounce }
    }
}

/// Filters applied to a folder's project list (besides the text query).
public struct LibraryFilter: Equatable, Sendable {
    public var similarity: SimilarityAxis?
    public var onlyMissingPlugins: Bool
    public var bounce: BounceFilter

    public init(similarity: SimilarityAxis? = nil, onlyMissingPlugins: Bool = false, bounce: BounceFilter = .any) {
        self.similarity = similarity
        self.onlyMissingPlugins = onlyMissingPlugins
        self.bounce = bounce
    }

    public var isActive: Bool { similarity != nil || onlyMissingPlugins || bounce != .any }

    /// Keeps the paths that pass every active filter. Projects that haven't been read yet
    /// (no entry) can't be judged, so they're excluded while a filter is active.
    public func apply(to paths: [String], entries: [String: ProjectListEntry], installed: Set<String>?, withBounce: Set<String> = []) -> [String] {
        guard isActive else { return paths }
        return paths.filter { path in
            guard let entry = entries[path] else { return false }
            if let similarity, !similarity.matches(entry.metadata) { return false }
            if !bounce.allows(hasBounce: withBounce.contains(path)) { return false }
            if onlyMissingPlugins {
                // Unknown registry ⇒ can't call anything missing.
                guard installed != nil,
                      !CompatibilityVerdict.evaluate(plugins: entry.plugins.map(\.ref), installed: installed).missing.isEmpty else { return false }
            }
            return true
        }
    }
}
