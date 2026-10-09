import Foundation

/// What Finder knows about a project and the project's own data doesn't say: its dates and its tags (all of them, colour
/// tags included, by name). Tags and dates can change without Logic touching the project, so they are read from the file
/// system again after every scan. Read-only.
public struct ProjectFileInfo: Equatable, Sendable, Codable {
    public var created: Int64
    public var modified: Int64
    public var tags: [String]
    public init(created: Int64, modified: Int64, tags: [String]) { self.created = created; self.modified = modified; self.tags = tags }

    /// nil when the project can't be seen (e.g. its drive is not mounted).
    public static func read(_ url: URL) -> ProjectFileInfo? {
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey, .tagNamesKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        func seconds(_ d: Date?) -> Int64 { d.map { Int64($0.timeIntervalSince1970) } ?? 0 }
        let modified = seconds(values.contentModificationDate)
        return ProjectFileInfo(created: values.creationDate.map { seconds($0) } ?? modified, modified: modified, tags: values.tagNames ?? [])
    }
}
