import Foundation
import LpxCore
import Observation

/// Plug-in name lookup built from `auval -l`, cached on disk. The scan can take
/// a while on machines with many plug-ins, so it only runs on demand (first run
/// or "Refresh plug-in names").
@MainActor @Observable
final class AuRegistry {
    private(set) var entries: [String: AuvalEntry] = [:] { didSet { installed = entries.isEmpty ? nil : Set(entries.keys) } }
    /// Fingerprints of installed AUs; nil until `auval -l` has been read (cached across launches).
    private(set) var installed: Set<String>?
    private(set) var isScanning = false
    private(set) var lastError: String?
    /// Bumped whenever `entries` changes so dependents can rebuild search indexes.
    private(set) var version = 0

    private struct CacheFile: Codable { var scannedAt: Date; var entries: [AuvalEntry] }

    private static var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LpxExplorer/au-registry.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.cacheURL),
           let file = try? JSONDecoder().decode(CacheFile.self, from: data) {
            entries = Dictionary(file.entries.map { ($0.fingerprint, $0) }, uniquingKeysWith: { a, _ in a })
            installed = entries.isEmpty ? nil : Set(entries.keys) // didSet doesn't fire from init
        }
    }

    var needsScan: Bool { entries.isEmpty }

    func name(for au: AURef) -> String {
        au.displayName ?? entries[au.fingerprint]?.name ?? "\(au.subtype) · \(au.manufacturer)"
    }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        lastError = nil
        Task {
            let result = await Task.detached(priority: .utility) { Self.runAuval() }.value
            isScanning = false
            switch result {
            case .success(let list):
                entries = Dictionary(list.map { ($0.fingerprint, $0) }, uniquingKeysWith: { a, _ in a })
                version += 1
                let file = CacheFile(scannedAt: Date(), entries: list)
                try? FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? JSONEncoder().encode(file).write(to: Self.cacheURL, options: .atomic)
            case .failure(let message):
                lastError = message
            }
        }
    }

    private enum ScanResult { case success([AuvalEntry]), failure(String) }

    private nonisolated static func runAuval() -> ScanResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/auval")
        process.arguments = ["-l"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .failure("couldn't run auval: \(error.localizedDescription)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return .failure("auval exited with status \(process.terminationStatus)")
        }
        let list = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { AuvalParser.parseLine(String($0)) }
        return .success(list)
    }
}
