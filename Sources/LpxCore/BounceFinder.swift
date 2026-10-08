import Foundation

public struct BounceFile: Equatable, Sendable, Codable {
    public var path: String
    public var fileName: String
    public var kind: BounceKind
    public var stemNumber: Int?
    /// The stem's own name ("PIANO"), when the file has one.
    public var stemLabel: String?
    /// A mix variant ("MIX ALL [30 SECS ALT 1]"), never the main mix.
    public var isAlternative: Bool
    public var sizeBytes: UInt64
    public var mtimeUnix: Int64
    public init(path: String, fileName: String, kind: BounceKind, stemNumber: Int?, stemLabel: String? = nil, isAlternative: Bool = false,
                sizeBytes: UInt64, mtimeUnix: Int64) {
        self.path = path; self.fileName = fileName; self.kind = kind; self.stemNumber = stemNumber
        self.stemLabel = stemLabel; self.isAlternative = isAlternative
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
    /// How many folders above the project are searched when no library root is given.
    static let maxLevelsUp = 5

    public static func find(project: URL, libraryRoot: URL? = nil, cache: BounceListingCache = BounceListingCache()) -> [BounceFile] {
        let fm = FileManager.default
        let name = project.deletingPathExtension().lastPathComponent

        // Bounces folders: next to the project and in every folder above it (a project in `Backups/` has its bounces beside
        // that folder), up to the library root; and inside the package.
        var folders: [URL] = []
        var dir = project.deletingLastPathComponent()
        let root = libraryRoot?.standardizedFileURL.path
        for _ in 0..<maxLevelsUp {
            folders.append(dir.appendingPathComponent("Bounces"))
            if dir.path == "/" || dir.standardizedFileURL.path == root { break }
            dir = dir.deletingLastPathComponent()
        }
        var parents = [project, project.appendingPathComponent("Media")]
        let alternatives = project.appendingPathComponent("Alternatives")
        for alt in ((try? fm.contentsOfDirectory(atPath: alternatives.path)) ?? []).sorted() {
            let altDir = alternatives.appendingPathComponent(alt)
            parents += [altDir, altDir.appendingPathComponent("Media")]
        }
        folders += parents.map { $0.appendingPathComponent("Bounces") }

        struct Candidate { var file: BounceFile; var archived: Bool; var lossy: Bool }
        var seen = Set<String>()
        var candidates: [Candidate] = []
        for folder in folders {
            let base = folder.pathComponents.count
            for entry in cache.audioFiles(under: folder) where seen.insert(entry.url.path).inserted {
                guard let match = BounceNaming.match(fileName: entry.url.lastPathComponent, projectName: name) else { continue }
                // A folder such as `_OLD` below Bounces marks an archived copy.
                let between = entry.url.pathComponents.dropFirst(base).dropLast()
                candidates.append(Candidate(
                    file: BounceFile(path: entry.url.path, fileName: entry.url.lastPathComponent, kind: match.kind, stemNumber: match.stemNumber,
                                     stemLabel: match.stemLabel, isAlternative: match.isAlternative, sizeBytes: entry.size, mtimeUnix: entry.mtime),
                    archived: between.contains { $0.hasPrefix("_") },
                    lossy: BounceNaming.lossyExtensions.contains(entry.url.pathExtension.lowercased())))
            }
        }

        // Best copy first: not archived, lossless, not a variant, newest.
        func better(_ a: Candidate, _ b: Candidate) -> Bool {
            if a.file.isAlternative != b.file.isAlternative { return !a.file.isAlternative }
            if a.archived != b.archived { return !a.archived }
            if a.lossy != b.lossy { return !a.lossy }
            return a.file.mtimeUnix != b.file.mtimeUnix ? a.file.mtimeUnix > b.file.mtimeUnix : a.file.path < b.file.path
        }
        let ranked = candidates.sorted(by: better)
        let mixes = ranked.filter { $0.file.kind == .mix }.map(\.file)
        // One entry per stem number: the best copy.
        var stems: [Int: BounceFile] = [:]
        for c in ranked where c.file.kind == .stem {
            let number = c.file.stemNumber ?? 0
            if stems[number] == nil { stems[number] = c.file }
        }
        return mixes + stems.sorted { $0.key < $1.key }.map(\.value)
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
