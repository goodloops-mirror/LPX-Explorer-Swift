import Foundation

public enum DiscoveryError: Error, Equatable {
    case notFound(String)
    case readFailed(String)
}

public enum LogicxDiscovery {
    /// Walk `root` and return every `.logicx` bundle. Bundles are leaves (Logic
    /// never nests projects), symlinks are not followed, and unreadable subtrees
    /// are skipped. Only an unreadable *root* is an error.
    public static func discover(in root: URL, isCancelled: () -> Bool = { false }) throws -> [URL] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw DiscoveryError.notFound(root.path)
        }
        do { _ = try fm.contentsOfDirectory(atPath: root.path) } catch {
            throw DiscoveryError.readFailed("\(root.path): \(error.localizedDescription)")
        }
        var out: [URL] = []
        walk(root, fm, isCancelled, &out)
        return out
    }

    private static func walk(_ dir: URL, _ fm: FileManager, _ isCancelled: () -> Bool, _ out: inout [URL]) {
        if isCancelled() { return }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return }
        for url in entries {
            if isCancelled() { return }
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.isDirectory == true, v.isSymbolicLink != true else { continue }
            if url.lastPathComponent.lowercased().hasSuffix(".logicx") {
                out.append(url)
            } else {
                walk(url, fm, isCancelled, &out)
            }
        }
    }
}
