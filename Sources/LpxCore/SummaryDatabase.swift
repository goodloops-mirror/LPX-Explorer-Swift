import Foundation
import SQLite3

public struct DatabaseStamp: Equatable, Sendable {
    public var mtime: Int64
    public var size: UInt64
    public init(mtime: Int64, size: UInt64) { self.mtime = mtime; self.size = size }
}

public enum DatabaseError: Error, Equatable { case sqlite(String) }

/// On-disk cache of parsed projects (SQLite, in our own Application Support folder — never inside a
/// bundle). Each project is stored twice: a small `ProjectListEntry` loaded at launch for the list,
/// search and filters, and the full `ProjectSummary` loaded on demand when a project is selected.
public actor SummaryDatabase {
    /// Bump when parser output changes so stale rows are discarded on the next launch.
    public static let parserVersion = 6
    private static let schemaVersion = 2
    // SQLite must copy bound text/blobs: Swift's temporary buffers are gone after the bind call returns.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LpxExplorer/library.sqlite")
    }

    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Opens (creating if needed) the store. A corrupt file is deleted and recreated — it is only a
    /// cache, every row can be re-derived from the projects.
    public init(url: URL, parserVersion: Int = SummaryDatabase.parserVersion) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            db = try Self.openAndPrepare(url, parserVersion)
        } catch {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
            db = try Self.openAndPrepare(url, parserVersion)
        }
    }

    deinit { sqlite3_close(db) }

    // MARK: API

    public func entries() throws -> [ProjectListEntry] {
        var out: [ProjectListEntry] = []
        try query("SELECT entry FROM entries") { stmt in
            if let entry = try? decoder.decode(ProjectListEntry.self, from: blob(stmt, 0)) { out.append(entry) }
        }
        return out
    }

    public func stamps() throws -> [String: DatabaseStamp] {
        var out: [String: DatabaseStamp] = [:]
        try query("SELECT path, pd_mtime, pd_size FROM entries") { stmt in
            out[text(stmt, 0)] = DatabaseStamp(mtime: sqlite3_column_int64(stmt, 1), size: UInt64(bitPattern: sqlite3_column_int64(stmt, 2)))
        }
        return out
    }

    public func summary(forPath path: String) throws -> ProjectSummary? {
        var found: ProjectSummary?
        try query("SELECT summary FROM details WHERE path = ?", binds: [.text(path)]) { stmt in
            found = try? decoder.decode(ProjectSummary.self, from: blob(stmt, 0))
        }
        return found
    }

    public func upsert(_ summaries: [ProjectSummary]) throws {
        guard !summaries.isEmpty else { return }
        try exec("BEGIN IMMEDIATE")
        do {
            for s in summaries {
                let entry = try encoder.encode(ProjectListEntry(summary: s))
                let full = try encoder.encode(s)
                try run("INSERT OR REPLACE INTO entries(path, pd_mtime, pd_size, entry) VALUES (?,?,?,?)",
                        [.text(s.path), .int(s.projectDataMTime), .int(Int64(bitPattern: s.projectDataSize)), .blob(entry)])
                try run("INSERT OR REPLACE INTO details(path, summary) VALUES (?,?)", [.text(s.path), .blob(full)])
                try run("DELETE FROM tracks WHERE path = ?", [.text(s.path)])
                for r in TrackSearchRow.rows(for: s) {
                    try run("INSERT INTO tracks(path, position, kind, hidden, name, object_name, channel, text, fingerprints, project_text) VALUES (?,?,?,?,?,?,?,?,?,?)",
                            [.text(r.path), .int(Int64(r.position)), .text(r.kind.rawValue), .int(r.isHidden ? 1 : 0), .text(r.name),
                             .text(r.objectName), .text(r.channel), .text(r.text), .text(r.fingerprints), .text(r.projectText)])
                }
            }
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    public func remove(paths: [String]) throws {
        guard !paths.isEmpty else { return }
        try exec("BEGIN IMMEDIATE")
        do {
            for p in paths {
                try run("DELETE FROM entries WHERE path = ?", [.text(p)])
                try run("DELETE FROM details WHERE path = ?", [.text(p)])
                try run("DELETE FROM tracks WHERE path = ?", [.text(p)])
            }
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    /// Tracks matching every term. A term matches a track's own text (track, object, channel, stock plug-in names), a plug-in
    /// the registry resolved for it, or — for terms that aren't found at track level — the project's name; at least one term
    /// must match at track level, so a project-name match alone isn't expanded into all of that project's tracks.
    /// Ordered by project name (natural) then track number; `limit` cuts the list, `total` counts every match.
    public func searchTracks(_ query: TrackSearchQuery, limit: Int) throws -> TrackSearchResult {
        guard !query.isEmpty else { return TrackSearchResult(hits: [], total: 0) }
        func trackMatch(_ i: Int) -> (sql: String, binds: [Bind]) {
            var sql = "instr(text, ?) > 0"
            var b: [Bind] = [.text(query.terms[i])]
            for fp in i < query.pluginFingerprints.count ? query.pluginFingerprints[i] : [] {
                sql += " OR instr(fingerprints, ?) > 0"
                b.append(.text("|" + fp + "|"))
            }
            return ("(" + sql + ")", b)
        }
        var binds: [Bind] = []
        var all: [String] = [], any: [String] = []
        for i in query.terms.indices {
            let m = trackMatch(i)
            all.append("(" + m.sql + " OR instr(project_text, ?) > 0)")
            binds += m.binds + [.text(query.terms[i])]
        }
        for i in query.terms.indices { let m = trackMatch(i); any.append(m.sql); binds += m.binds }
        let sql = "SELECT id, path, position FROM tracks WHERE " + all.joined(separator: " AND ") + " AND (" + any.joined(separator: " OR ") + ")"
        var matches: [(id: Int64, path: String, position: Int)] = []
        try self.query(sql, binds: binds) { stmt in
            matches.append((sqlite3_column_int64(stmt, 0), text(stmt, 1), Int(sqlite3_column_int64(stmt, 2))))
        }
        var nameCache: [String: String] = [:]
        func projectName(_ path: String) -> String {
            if let n = nameCache[path] { return n }
            let n = ProjectBundle.bundleName(URL(fileURLWithPath: path)); nameCache[path] = n; return n
        }
        matches.sort { a, b in
            if a.path != b.path {
                let order = projectName(a.path).localizedStandardCompare(projectName(b.path))
                return order == .orderedSame ? a.path < b.path : order == .orderedAscending
            }
            return a.position < b.position
        }
        let page = Array(matches.prefix(max(0, limit)))
        var hits: [TrackHit] = []
        for m in page {
            try self.query("SELECT path, position, kind, hidden, name, object_name, channel, fingerprints FROM tracks WHERE id = ?", binds: [.int(m.id)]) { stmt in
                let fps = text(stmt, 7).split(separator: "|").map(String.init)
                hits.append(TrackHit(path: text(stmt, 0), position: Int(sqlite3_column_int64(stmt, 1)), kind: TrackKind(rawValue: text(stmt, 2)) ?? .unknown,
                                     isHidden: sqlite3_column_int64(stmt, 3) != 0, name: text(stmt, 4), objectName: text(stmt, 5),
                                     channel: text(stmt, 6), pluginFingerprints: fps))
            }
        }
        return TrackSearchResult(hits: hits, total: matches.count)
    }

    public func count() throws -> Int {
        var n = 0
        try query("SELECT COUNT(*) FROM entries") { n = Int(sqlite3_column_int64($0, 0)) }
        return n
    }

    /// Test hook: a row whose list entry cannot be decoded.
    func corruptEntryForTesting(path: String) throws {
        try run("INSERT OR REPLACE INTO entries(path, pd_mtime, pd_size, entry) VALUES (?,0,0,?)", [.text(path), .blob(Data([0x00, 0xFF, 0x7B]))])
    }

    // MARK: SQLite plumbing

    private enum Bind { case text(String), int(Int64), blob(Data) }

    private static func openAndPrepare(_ url: URL, _ parserVersion: Int) throws -> OpaquePointer {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let db = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            throw DatabaseError.sqlite(message)
        }
        func exec(_ sql: String) throws {
            var err: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
                let message = err.map { String(cString: $0) } ?? "sqlite error"
                sqlite3_free(err)
                sqlite3_close(db)
                throw DatabaseError.sqlite(message)
            }
        }
        try exec("PRAGMA journal_mode = WAL")
        try exec("PRAGMA synchronous = NORMAL")
        try exec("""
            CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS entries(path TEXT PRIMARY KEY, pd_mtime INTEGER NOT NULL, pd_size INTEGER NOT NULL, entry BLOB NOT NULL);
            CREATE TABLE IF NOT EXISTS details(path TEXT PRIMARY KEY, summary BLOB NOT NULL);
            CREATE TABLE IF NOT EXISTS tracks(id INTEGER PRIMARY KEY, path TEXT NOT NULL, position INTEGER NOT NULL, kind TEXT NOT NULL, hidden INTEGER NOT NULL,
                name TEXT NOT NULL, object_name TEXT NOT NULL, channel TEXT NOT NULL, text TEXT NOT NULL, fingerprints TEXT NOT NULL, project_text TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS tracks_path ON tracks(path);
            """)
        // Stale parser output (or schema) ⇒ drop every row; they are re-derived by the next scan.
        let wanted = "\(schemaVersion)/\(parserVersion)"
        var stored: String?
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = 'version'", -1, &stmt, nil) == SQLITE_OK, sqlite3_step(stmt) == SQLITE_ROW {
            stored = sqlite3_column_text(stmt, 0).map { String(cString: $0) }
        }
        sqlite3_finalize(stmt)
        if stored != wanted {
            try exec("DELETE FROM entries; DELETE FROM details; DELETE FROM tracks; INSERT OR REPLACE INTO meta(key, value) VALUES ('version', '\(wanted)')")
        }
        return db
    }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "sqlite error"
            sqlite3_free(err)
            throw DatabaseError.sqlite(message)
        }
    }

    private func run(_ sql: String, _ binds: [Bind]) throws {
        try query(sql, binds: binds) { _ in }
    }

    /// Prepares `sql`, binds the values (always copied by SQLite) and calls `row` for every result row.
    private func query(_ sql: String, binds: [Bind] = [], row: (OpaquePointer) throws -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw DatabaseError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        for (i, b) in binds.enumerated() {
            let idx = Int32(i + 1)
            let rc: Int32
            switch b {
            case .text(let s): rc = sqlite3_bind_text(stmt, idx, s, -1, Self.transient)
            case .int(let v): rc = sqlite3_bind_int64(stmt, idx, v)
            case .blob(let d): rc = d.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(d.count), Self.transient) }
            }
            guard rc == SQLITE_OK else { throw DatabaseError.sqlite(String(cString: sqlite3_errmsg(db))) }
        }
        while true {
            switch sqlite3_step(stmt) {
            case SQLITE_ROW: try row(stmt)
            case SQLITE_DONE: return
            default: throw DatabaseError.sqlite(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    private func text(_ stmt: OpaquePointer, _ col: Int32) -> String {
        sqlite3_column_text(stmt, col).map { String(cString: $0) } ?? ""
    }

    private func blob(_ stmt: OpaquePointer, _ col: Int32) -> Data {
        guard let p = sqlite3_column_blob(stmt, col) else { return Data() }
        return Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, col)))
    }
}

extension SummaryDatabase {
    /// One-time cleanup: earlier builds cached everything in `parse-cache.json` inside our own support
    /// folder. SQLite replaces it, so delete the obsolete file. Touches nothing else.
    public static func removeLegacyJSONCache(in supportDirectory: URL) {
        try? FileManager.default.removeItem(at: supportDirectory.appendingPathComponent("parse-cache.json"))
    }
}
