import Foundation

public struct BundleStats: Equatable, Sendable, Codable {
    public var sizeBytes: UInt64
    public var createdAt: Int64
    public var modifiedAt: Int64
}

public struct ProjectSummary: Equatable, Sendable, Codable {
    public var path: String
    public var fingerprints: [AURef]
    public var tracks: [Track] = []
    public var metadata: ProjectMetadata
    public var stats: BundleStats
    /// mtime/size of the ProjectData file parsed — the cache validation key.
    public var projectDataMTime: Int64
    public var projectDataSize: UInt64
    public var alternatives: [Alternative] = []
    /// "Logic Pro 12.2 (6644)" from ProjectInformation.plist, when present.
    public var lastSavedFrom: String?
    /// Which `Alternatives/<NNN>/` this summary was parsed from.
    public var variant: Int = 0
}

public enum ParseError: Error, Equatable {
    case projectDataMissing(String)
    case metadataMissing(String)
    case io(String)
    case metadataInvalid(String)
}

public enum ProjectParser {
    /// Read-only: opens files for reading, never writes inside the bundle.
    public static func parse(bundle: URL, variant: Int? = nil) throws -> ProjectSummary {
        let fm = FileManager.default
        let located: URL?
        if let variant {
            let dir = bundle.appendingPathComponent(String(format: "Alternatives/%03d", variant))
            located = fm.fileExists(atPath: dir.appendingPathComponent("ProjectData").path) ? dir : nil
        } else {
            located = locateAlternative(bundle, fm)
        }
        guard let alt = located else { throw ParseError.projectDataMissing(bundle.path) }
        let projectDataURL = alt.appendingPathComponent("ProjectData")
        let plistURL = alt.appendingPathComponent("MetaData.plist")
        guard fm.fileExists(atPath: plistURL.path) else { throw ParseError.metadataMissing(bundle.path) }

        let projectData: Data, plist: Data
        do {
            projectData = try Data(contentsOf: projectDataURL, options: .mappedIfSafe)
            plist = try Data(contentsOf: plistURL)
        } catch {
            throw ParseError.io(error.localizedDescription)
        }
        let metadata: ProjectMetadata
        do { metadata = try MetadataParser.parse(plist) } catch {
            throw ParseError.metadataInvalid("\(error)")
        }
        let (fingerprints, tracks) = projectData.withUnsafeBytes { raw -> ([AURef], [Track]) in
            let bytes = raw.bindMemory(to: UInt8.self)
            let aus = AUFinder.findAUs(in: bytes)
            return (aus, TrackPipeline.tracks(in: bytes, aus: aus))
        }
        let attrs = try? fm.attributesOfItem(atPath: projectDataURL.path)
        return ProjectSummary(
            path: bundle.path,
            fingerprints: fingerprints,
            tracks: tracks,
            metadata: metadata,
            stats: bundleStats(bundle, fm),
            projectDataMTime: unixSeconds(attrs?[.modificationDate] as? Date),
            projectDataSize: UInt64(projectData.count),
            alternatives: ProjectBundle.alternatives(of: bundle),
            lastSavedFrom: ProjectBundle.lastSavedFrom(bundle: bundle),
            variant: Int(alt.lastPathComponent) ?? 0)
    }

    /// Cheap cache-validation stat of the ProjectData file only.
    public static func projectDataStat(bundle: URL) -> (mtime: Int64, size: UInt64)? {
        let fm = FileManager.default
        guard let alt = locateAlternative(bundle, fm),
              let attrs = try? fm.attributesOfItem(atPath: alt.appendingPathComponent("ProjectData").path) else { return nil }
        return (unixSeconds(attrs[.modificationDate] as? Date), (attrs[.size] as? NSNumber)?.uint64Value ?? 0)
    }

    /// Lowest-numbered `Alternatives/<n>/` that contains ProjectData (deterministic).
    public static func locateAlternative(_ bundle: URL, _ fm: FileManager) -> URL? {
        let alts = bundle.appendingPathComponent("Alternatives")
        guard let names = try? fm.contentsOfDirectory(atPath: alts.path) else { return nil }
        for name in names.sorted() {
            let dir = alts.appendingPathComponent(name)
            if fm.fileExists(atPath: dir.appendingPathComponent("ProjectData").path) { return dir }
        }
        return nil
    }

    static func bundleStats(_ bundle: URL, _ fm: FileManager) -> BundleStats {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        var total: UInt64 = 0
        if let e = fm.enumerator(at: bundle, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) {
            for case let url as URL in e {
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
                total &+= UInt64(v.fileSize ?? 0)
            }
        }
        let attrs = try? fm.attributesOfItem(atPath: bundle.path)
        let modified = unixSeconds(attrs?[.modificationDate] as? Date)
        let created = (attrs?[.creationDate] as? Date).map { unixSeconds($0) } ?? modified
        return BundleStats(sizeBytes: total, createdAt: created, modifiedAt: modified)
    }

    private static func unixSeconds(_ d: Date?) -> Int64 { d.map { Int64($0.timeIntervalSince1970) } ?? 0 }
}
