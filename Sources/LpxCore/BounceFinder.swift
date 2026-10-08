import Foundation

public struct BounceFile: Equatable, Sendable, Codable {
    public var path: String
    public var fileName: String
    public var kind: BounceKind
    public var stemNumber: Int?
    public var sizeBytes: UInt64
    public var mtimeUnix: Int64
    public init(path: String, fileName: String, kind: BounceKind, stemNumber: Int?, sizeBytes: UInt64, mtimeUnix: Int64) {
        self.path = path; self.fileName = fileName; self.kind = kind; self.stemNumber = stemNumber
        self.sizeBytes = sizeBytes; self.mtimeUnix = mtimeUnix
    }
}

/// Remembers directory listings during one lookup pass: libraries often keep many projects next to one shared `Bounces` folder.
public final class BounceListingCache: @unchecked Sendable {
    struct Entry { var url: URL; var size: UInt64; var mtime: Int64 }
    private let lock = NSLock()
    private var listings: [String: [Entry]] = [:]
    public init() {}

    func audioFiles(under directory: URL) -> [Entry] {
        lock.lock(); let cached = listings[directory.path]; lock.unlock()
        if let cached { return cached }
        let found = BounceFinder.listAudioFiles(under: directory)
        lock.lock(); listings[directory.path] = found; lock.unlock()
        return found
    }
}

/// Finds the bounces of a project: audio files whose names match the project's name (see `BounceNaming`) in
/// - a `Bounces` folder next to the `.logicx` (any subfolder of it), the layout of "folder" projects and flat libraries, and
/// - `Bounces` folders inside the package (package root, `Media/`, each alternative).
/// Read-only.
public enum BounceFinder {
    public static func find(project: URL, cache: BounceListingCache = BounceListingCache()) -> [BounceFile] {
        let fm = FileManager.default
        let name = project.deletingPathExtension().lastPathComponent
        var folders = [project.deletingLastPathComponent().appendingPathComponent("Bounces")]
        var parents = [project, project.appendingPathComponent("Media")]
        let alternatives = project.appendingPathComponent("Alternatives")
        for alt in ((try? fm.contentsOfDirectory(atPath: alternatives.path)) ?? []).sorted() {
            let dir = alternatives.appendingPathComponent(alt)
            parents += [dir, dir.appendingPathComponent("Media")]
        }
        folders += parents.map { $0.appendingPathComponent("Bounces") }

        var seen = Set<String>()
        var out: [BounceFile] = []
        for folder in folders {
            for entry in cache.audioFiles(under: folder) where seen.insert(entry.url.path).inserted {
                guard let match = BounceNaming.match(fileName: entry.url.lastPathComponent, projectName: name) else { continue }
                out.append(BounceFile(path: entry.url.path, fileName: entry.url.lastPathComponent, kind: match.kind, stemNumber: match.stemNumber,
                                      sizeBytes: entry.size, mtimeUnix: entry.mtime))
            }
        }
        return out.sorted { a, b in
            if a.kind != b.kind { return a.kind == .mix }
            if a.kind == .stem, a.stemNumber != b.stemNumber { return (a.stemNumber ?? 0) < (b.stemNumber ?? 0) }
            return a.mtimeUnix != b.mtimeUnix ? a.mtimeUnix > b.mtimeUnix : a.path < b.path
        }
    }

    /// Every audio file in `directory` and its subfolders (empty when it doesn't exist).
    static func listAudioFiles(under directory: URL) -> [BounceListingCache.Entry] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else { return [] }
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let e = fm.enumerator(at: directory, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return [] }
        var out: [BounceListingCache.Entry] = []
        for case let url as URL in e {
            guard BounceNaming.audioExtensions.contains(url.pathExtension.lowercased()),
                  let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            out.append(.init(url: url, size: UInt64(v.fileSize ?? 0), mtime: v.contentModificationDate.map { Int64($0.timeIntervalSince1970) } ?? 0))
        }
        return out
    }
}
