import Foundation

public enum ScanOutcome: Sendable, Equatable {
    /// Freshly parsed (new or changed on disk).
    case parsed(ProjectSummary)
    /// ProjectData mtime+size match the stored stamp: nothing to do, the cached row is still valid.
    case unchanged(path: String)
    case failed(path: String, message: String)
}

public enum LibraryScanner {
    /// 70% of the logical cores, at least one.
    public static func defaultWorkerCount(cores: Int = ProcessInfo.processInfo.activeProcessorCount) -> Int {
        max(1, Int(Double(cores) * 0.7))
    }

    /// Parse `bundles` with at most `workers` in flight. Calls `onOutcome` once per
    /// bundle, from worker threads (callers must be thread-safe). A bundle whose
    /// cached summary still matches its ProjectData mtime+size is not re-parsed.
    /// Cancelling the calling task stops handing out new work.
    public static func scan(
        bundles: [URL],
        workers: Int,
        known: [String: DatabaseStamp] = [:],
        parse: @escaping @Sendable (URL) throws -> ProjectSummary = { try ProjectParser.parse(bundle: $0) },
        onOutcome: @escaping @Sendable (ScanOutcome) -> Void
    ) async {
        let limit = max(1, workers)
        await withTaskGroup(of: Void.self) { group in
            var next = 0
            func submit(_ url: URL) {
                group.addTask {
                    onOutcome(process(url, known: known[url.path], parse: parse))
                }
            }
            while next < min(limit, bundles.count) { submit(bundles[next]); next += 1 }
            while await group.next() != nil {
                if next < bundles.count && !Task.isCancelled {
                    submit(bundles[next]); next += 1
                }
            }
        }
    }

    private static func process(_ url: URL, known: DatabaseStamp?, parse: (URL) throws -> ProjectSummary) -> ScanOutcome {
        if let known, let stat = ProjectParser.projectDataStat(bundle: url), stat.mtime == known.mtime, stat.size == known.size {
            return .unchanged(path: url.path)
        }
        do {
            return .parsed(try parse(url))
        } catch {
            return .failed(path: url.path, message: describe(error))
        }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case ParseError.projectDataMissing: return "ProjectData not found inside bundle"
        case ParseError.metadataMissing: return "MetaData.plist not found inside bundle"
        case ParseError.io(let m): return "failed to read bundle: \(m)"
        case ParseError.metadataInvalid(let m): return "invalid MetaData.plist: \(m)"
        default: return error.localizedDescription
        }
    }
}
