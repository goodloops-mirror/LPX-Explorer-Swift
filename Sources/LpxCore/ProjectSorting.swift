import Foundation

public enum ProjectSortField: String, CaseIterable, Sendable, Codable {
    case name = "Name"
    case dateModified = "Date Modified"
    case dateCreated = "Date Created"
    /// When Logic last saved the project (its ProjectData file), as opposed to the project's own Finder dates.
    case dateSaved = "Date Saved"
    case size = "Size"

    public var isDate: Bool { self == .dateModified || self == .dateCreated || self == .dateSaved }
}

public struct ProjectOrder: Equatable, Sendable {
    public var field: ProjectSortField
    /// Name: A→Z. Date: oldest first. (Newest first is `ascending == false`.)
    public var ascending: Bool
    public init(field: ProjectSortField = .name, ascending: Bool = true) { self.field = field; self.ascending = ascending }

    /// What a field starts as when it is chosen: names A→Z, dates newest first, sizes largest first.
    public static func initial(for field: ProjectSortField) -> ProjectOrder { ProjectOrder(field: field, ascending: field == .name) }
}

public enum ProjectSorting {
    /// Re-orders `paths`, which must already be in natural name order (ascending). Name order is that list or its reverse; date
    /// order sorts by `value` (a date, or a size in bytes) and keeps name order among equal values. Projects without a known
    /// value (nil or 0) always go last.
    public static func sorted(_ paths: [String], by order: ProjectOrder, value: (String) -> Int64?) -> [String] {
        switch order.field {
        case .name:
            return order.ascending ? paths : paths.reversed()
        default:
            // Decorate with the original position so equal dates keep their name order (and the result is deterministic).
            let keyed = paths.enumerated().map { (index: $0.offset, path: $0.element, date: value($0.element) ?? 0) }
            return keyed.sorted { a, b in
                if (a.date == 0) != (b.date == 0) { return b.date == 0 }                // unknown dates last, either direction
                if a.date != b.date { return order.ascending ? a.date < b.date : a.date > b.date }
                return a.index < b.index
            }.map(\.path)
        }
    }

    /// The same for any list whose items map to a project path.
    public static func sorted<T>(_ items: [T], by order: ProjectOrder, path: (T) -> String, value: (String) -> Int64?) -> [T] {
        var byPath: [String: T] = [:]
        for item in items where byPath[path(item)] == nil { byPath[path(item)] = item }
        var seen = Set<String>()
        return sorted(items.map(path).filter { seen.insert($0).inserted }, by: order, value: value).compactMap { byPath[$0] }
    }
}
