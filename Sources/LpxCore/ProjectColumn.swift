import Foundation

/// The optional columns of the project list (the name is always there). Which ones are shown is the user's choice,
/// kept as a set of these names.
public enum ProjectColumn: String, CaseIterable, Sendable, Codable {
    case dateModified = "Date Modified"
    case dateCreated = "Date Created"
    /// When Logic last saved the project (as opposed to the project's own Finder dates).
    case dateSaved = "Date Saved"
    case size = "Size"
    case tags = "Tags"

    /// Shown until the user chooses otherwise: the two Finder dates. The rest is one click away in the header's menu.
    public static let defaultVisible: Set<ProjectColumn> = [.dateModified, .dateCreated]

    /// The sort order that clicking this column's header starts with.
    public var sortField: ProjectSortField? {
        switch self {
        case .dateModified: .dateModified
        case .dateCreated: .dateCreated
        case .dateSaved: .dateSaved
        case .size: .size
        case .tags: nil          // tags aren't ordered
        }
    }

    /// Saved form of a visible set (stable order), and the way back; unknown names are ignored.
    public static func encode(_ columns: Set<ProjectColumn>) -> [String] { allCases.filter(columns.contains).map(\.rawValue) }
    public static func decode(_ names: [String]?) -> Set<ProjectColumn> {
        guard let names else { return defaultVisible }
        return Set(names.compactMap(ProjectColumn.init(rawValue:)))
    }
}
