import Foundation

/// One entry in the folder browser: a plain folder, or a Logic project (a `.logicx` bundle or a single-file `.lso`).
public struct FolderItem: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable { case folder, project }
    public let path: String
    public let name: String
    public let kind: Kind
    public var id: String { path }
    public init(path: String, name: String, kind: Kind) { self.path = path; self.name = name; self.kind = kind }
    public var isFolder: Bool { kind == .folder }
}

public enum FolderListing {
    /// What the folder browser shows inside `directory`: sub-folders first, then Logic projects, each in natural name order.
    /// Bundles are leaves (never opened), hidden items, symlinks and ordinary files are left out. Read-only.
    public static func items(in directory: URL) -> [FolderItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        var folders: [FolderItem] = [], projects: [FolderItem] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isSymbolicLink != true else { continue }
            let name = url.lastPathComponent
            if v.isDirectory == true {
                if name.lowercased().hasSuffix(".logicx") { projects.append(FolderItem(path: url.path, name: name, kind: .project)) }
                else { folders.append(FolderItem(path: url.path, name: name, kind: .folder)) }
            } else if url.pathExtension.lowercased() == "lso" {
                projects.append(FolderItem(path: url.path, name: name, kind: .project))
            }
        }
        let natural: (FolderItem, FolderItem) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return folders.sorted(by: natural) + projects.sorted(by: natural)
    }

    /// The chain of paths from just below `root` down to `path` (both ends included for `path`, `root` excluded):
    /// `["/r/a", "/r/a/b", "/r/a/b/p.logicx"]`. Nil when `path` is not inside `root`.
    public static func chain(to path: String, under root: String) -> [String]? {
        let base = root.hasSuffix("/") ? String(root.dropLast()) : root
        guard path.hasPrefix(base + "/") else { return nil }
        var current = base
        return path.dropFirst(base.count + 1).split(separator: "/").map { current += "/" + $0; return current }
    }
}
