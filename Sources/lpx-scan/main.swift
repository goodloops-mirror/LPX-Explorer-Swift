import Foundation
import LpxCore

// Read-only diagnostic: `lpx-scan <folder> [workers]` discovers .logicx bundles,
// parses them in parallel and prints timings. Never writes anywhere.
let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: lpx-scan <folder> [workers]\n".utf8))
    exit(2)
}
if args.contains("--profile") {
    // Serial per-stage timing over every bundle's ProjectData (read-only).
    var t = [String: Double](), bytes = 0
    for b in try LogicxDiscovery.discover(in: URL(fileURLWithPath: args[1])) {
        guard let alt = ProjectParser.locateAlternative(b, .default),
              let data = try? Data(contentsOf: alt.appendingPathComponent("ProjectData"), options: .mappedIfSafe) else { continue }
        bytes += data.count
        data.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            func time<T>(_ k: String, _ f: () -> T) -> T { let s = Date(); let r = f(); t[k, default: 0] += Date().timeIntervalSince(s); return r }
            let aus = time("findAUs(standard+stock+drummer)") { AUFinder.findAUs(in: p) }
            _ = time("  of which AppleStock") { AppleStock.findAUs(in: p) }
            _ = time("  of which AppleDrummer") { AppleDrummer.findAUs(in: p) }
            var tracks = time("findTracks") { TrackFinder.findTracks(in: p) }
            time("assignAUs") { TrackFinder.assignAUs(&tracks, aus) }
            let recs = time("Regions.findRecords") { Regions.findRecords(in: p) }
            _ = time("Regions.cluster") { Regions.cluster(recs) }
            _ = time("TrackRegistry.findRecords") { TrackRegistry.findRecords(in: p) }
        }
    }
    print(String(format: "%.0f MB of ProjectData", Double(bytes) / 1e6))
    for (k, v) in t.sorted(by: { $0.key < $1.key }) { print(String(format: "%-34@ %8.1f ms  (%.2f ms/MB)", k as NSString, v * 1000, v * 1000 / (Double(bytes) / 1e6))) }
    exit(0)
}
if let dbPath = args.firstIndex(of: "--db").flatMap({ $0 + 1 < args.count ? args[$0 + 1] : nil }) {
    // Incremental scan against a SQLite library: unchanged projects are skipped via their stamps.
    let db = try SummaryDatabase(url: URL(fileURLWithPath: dbPath))
    let bundles = try LogicxDiscovery.discover(in: URL(fileURLWithPath: args[1]))
    let known = try await db.stamps()
    final class Counts: @unchecked Sendable {
        let lock = NSLock(); var parsed: [ProjectSummary] = [], unchanged = 0, failed = 0
        func add(_ o: ScanOutcome) { lock.lock(); defer { lock.unlock() }
            switch o { case .parsed(let s): parsed.append(s); case .unchanged: unchanged += 1; case .failed: failed += 1 } }
    }
    let c = Counts()
    let t = Date()
    await LibraryScanner.scan(bundles: bundles, workers: LibraryScanner.defaultWorkerCount(), known: known, onOutcome: c.add)
    try await db.upsert(c.parsed)
    let total = try await db.count()
    if let q = args.firstIndex(of: "--search").flatMap({ $0 + 1 < args.count ? args[$0 + 1] : nil }) {
        // Time a library-wide track search against the database that was just updated.
        let t0 = Date()
        let r = try await db.searchTracks(TrackSearchQuery(text: q), limit: 500)
        print(String(format: "search '%@': %d tracks in %d shown, %.1f ms", q, r.total, r.hits.count, Date().timeIntervalSince(t0) * 1000))
        for h in r.hits.prefix(8) { print("  \(URL(fileURLWithPath: h.path).lastPathComponent) #\(h.position) \(h.name)\(h.isHidden ? " [hidden]" : "")") }
    }
    print(String(format: "db scan: %d bundles, %d re-parsed, %d unchanged, %d failed; db now holds %d; %.0f ms", bundles.count, c.parsed.count, c.unchanged, c.failed, total, Date().timeIntervalSince(t) * 1000))
    exit(0)
}
if let idx = args.firstIndex(of: "--tracks"), idx + 1 < args.count {
    // Print the track list of one bundle in Logic's order (read-only): `lpx-scan <folder> --tracks <bundle-name-substring>`
    let bundles = try LogicxDiscovery.discover(in: URL(fileURLWithPath: args[1]))
    guard let b = bundles.first(where: { $0.lastPathComponent.contains(args[idx + 1]) }) else { print("no bundle matches"); exit(1) }
    let s = try ProjectParser.parse(bundle: b)
    let shown = s.tracks.sorted { ($0.position ?? Int.max, $0.offset) < ($1.position ?? Int.max, $1.offset) }
    print(b.lastPathComponent, "—", shown.count, "tracks,", shown.filter(\.isHidden).count, "hidden")
    for t in shown {
        let pos = (t.position.map(String.init) ?? "—") as NSString
        print(String(format: "%4@ %@ %-9@ %-9@ %@", pos, (t.isHidden ? "h" : " ") as NSString, "\(t.kind)" as NSString, t.name as NSString, t.displayName as NSString))
    }
    exit(0)
}
let workers = args.count > 2 ? Int(args[2]) ?? LibraryScanner.defaultWorkerCount() : LibraryScanner.defaultWorkerCount()

let t0 = Date()
let bundles = try LogicxDiscovery.discover(in: URL(fileURLWithPath: args[1]))
let tDiscover = Date().timeIntervalSince(t0)

let cachePath = args.firstIndex(of: "--save-cache").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }

final class Tally: @unchecked Sendable {
    private let lock = NSLock()
    var parsed = 0, failed = 0, plugins = 0, tracks = 0
    var summaries: [String: ProjectSummary] = [:]
    func add(_ o: ScanOutcome) {
        lock.lock(); defer { lock.unlock() }
        switch o {
        case .unchanged: break
        case .parsed(let s): parsed += 1; plugins += s.fingerprints.count; tracks += s.tracks.count; summaries[s.path] = s
        case .failed: failed += 1
        }
    }
}
let tally = Tally()
let t1 = Date()
await LibraryScanner.scan(bundles: bundles, workers: workers, onOutcome: tally.add)
let tScan = Date().timeIntervalSince(t1)

print(String(format: "discovered %d bundles in %.3fs", bundles.count, tDiscover))
print(String(format: "parsed %d, failed %d, %d AU refs, %d tracks with %d workers in %.3fs (%.2f ms/project)",
             tally.parsed, tally.failed, tally.plugins, tally.tracks, workers, tScan,
             tScan * 1000 / Double(max(1, bundles.count))))

if let cachePath {
    // Writes only the SQLite file the caller named (never inside a bundle).
    let db = try SummaryDatabase(url: URL(fileURLWithPath: cachePath))
    let t = Date()
    try await db.upsert(Array(tally.summaries.values))
    let size = (try? FileManager.default.attributesOfItem(atPath: cachePath)[.size] as? Int) ?? 0
    print(String(format: "sqlite cache: %.1f MB main file (%.0f KB/project), written in %.0f ms", Double(size) / 1e6, Double(size) / 1e3 / Double(max(1, tally.parsed)), Date().timeIntervalSince(t) * 1000))
}

if args.contains("--verdict") {
    // Installed AUs from `auval -l` (read-only system tool), then a verdict per project
    // and how many projects each similarity pivot would return.
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/auval")
    proc.arguments = ["-l"]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    try proc.run()
    let out = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    let installed = Set(String(decoding: out, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { AuvalParser.parseLine(String($0))?.fingerprint })
    print("\ninstalled AUs on this Mac: \(installed.count)")
    var counts: [String: Int] = [:]
    for s in tally.summaries.values.sorted(by: { $0.path < $1.path }) {
        let v = CompatibilityVerdict.evaluate(plugins: s.fingerprints, installed: installed)
        counts[v.headline.contains("missing") ? "warnings" : String(describing: v.status), default: 0] += 1
        print(String(format: "%-62@ %@", URL(fileURLWithPath: s.path).lastPathComponent as NSString, "\(v.headline) (\(v.total) unique)" as NSString))
        for m in v.missing.prefix(3) { print("      missing: \(m.fingerprint)") }
    }
    print("verdicts:", counts)
    let all = tally.summaries.values.map(\.metadata)
    for m in all.prefix(3) {
        for axis in [SimilarityAxis.key(of: m), SimilarityAxis.bpm(of: m), SimilarityAxis.keyAndBPM(of: m)].compactMap({ $0 }) {
            print("pivot \(axis.label): \(all.filter(axis.matches).count) of \(all.count) projects")
        }
    }
}

if args.contains("--plugins") {
    // The plug-in rail's data for this folder: usage, install status, categories.
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/auval")
    proc.arguments = ["-l"]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    try proc.run()
    let out = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    let entries = String(decoding: out, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { AuvalParser.parseLine(String($0)) }
    let registry = Dictionary(entries.map { ($0.fingerprint, $0) }, uniquingKeysWith: { a, _ in a })
    let rows = PluginRail.sortedByUsage(PluginRail.rows(PluginRollup.aggregate(tally.summaries.mapValues(ProjectListEntry.init(summary:))), registry: registry))
    print("\nplug-ins used across \(tally.parsed) projects: \(rows.count)  (missing: \(rows.filter { $0.status == .missing }.count), uncategorised: \(rows.filter { $0.fineCategory == .uncategorised }.count))")
    for r in rows.prefix(15) {
        print(String(format: "%-34@ %-13@ %-9@ %2d projects ×%d", r.name as NSString, r.fineCategory.rawValue as NSString, "\(r.status)" as NSString, r.projectCount, r.instanceCount))
    }
    print("facets:", PluginRail.facets(rows).map { "\($0.category.rawValue) \($0.count)" }.joined(separator: ", "))
    print("uncategorised sample:", rows.filter { $0.fineCategory == .uncategorised }.prefix(12).map(\.name).joined(separator: " | "))
}
