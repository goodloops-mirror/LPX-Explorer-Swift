import Foundation

/// One plug-in aggregated across projects ("EZdrummer 2 — used in 14 projects").
public struct RolledPlugin: Equatable, Sendable {
    public var fingerprint: String
    /// Parser-recovered name (Apple stock / Drummer); nil for 4CC-triple plug-ins.
    public var displayName: String?
    public var projectPaths: [String]
    /// Total occurrences across projects (a project with Compressor on two tracks adds 2).
    public var instanceCount: Int
    public var projectCount: Int { projectPaths.count }
}

public enum PluginRollup {
    /// Rows sorted by descending project count, then ascending fingerprint.
    public static func aggregate(_ entries: [String: ProjectListEntry]) -> [RolledPlugin] {
        struct Acc { var paths: [String] = []; var instances = 0; var displayName: String? }
        var acc: [String: Acc] = [:]
        for (path, entry) in entries {
            for use in entry.plugins {
                // Mutate in place: copying the Acc out first would copy its path array on every append (O(n²)).
                acc[use.fingerprint, default: Acc()].paths.append(path)
                acc[use.fingerprint]!.instances += use.instances
                if acc[use.fingerprint]!.displayName == nil { acc[use.fingerprint]!.displayName = use.ref.displayName }
            }
        }
        return acc.map { RolledPlugin(fingerprint: $0.key, displayName: $0.value.displayName,
                                      projectPaths: $0.value.paths.sorted(), instanceCount: $0.value.instances) }
            .sorted { $0.projectCount != $1.projectCount ? $0.projectCount > $1.projectCount : $0.fingerprint < $1.fingerprint }
    }
}

public enum InstallStatus: Equatable, Sendable { case installed, missing, unknown }

public struct PluginRow: Equatable, Sendable {
    public var fingerprint: String
    public var name: String
    public var hasRegistryEntry: Bool
    public var status: InstallStatus
    public var fineCategory: AuFineCategory
    public var projectPaths: [String]
    public var instanceCount: Int
    public var projectCount: Int { projectPaths.count }
}

public enum PluginStatusFilter: Equatable, Sendable { case all, installed, missing, multipleProjects }

public struct CategoryFacet: Equatable, Sendable {
    public var category: AuFineCategory
    public var count: Int
}

public enum PluginRail {
    /// - Parameter registry: installed AUs keyed by fingerprint, or nil when `auval -l` hasn't been read.
    /// Parser-named plug-ins (Apple stock, Drummer) ship with Logic, so they count as installed.
    public static func rows(_ rolled: [RolledPlugin], registry: [String: AuvalEntry]?) -> [PluginRow] {
        rolled.map { r in
            let entry = registry?[r.fingerprint]
            let status: InstallStatus
            if r.displayName != nil { status = .installed }
            else if let registry { status = registry[r.fingerprint] != nil ? .installed : .missing }
            else { status = .unknown }
            let name = r.displayName ?? entry?.name ?? r.fingerprint
            return PluginRow(
                fingerprint: r.fingerprint, name: name, hasRegistryEntry: r.displayName == nil && entry != nil, status: status,
                fineCategory: PluginCatalog.fineCategory(displayName: r.displayName ?? entry?.name, fingerprint: r.fingerprint),
                projectPaths: r.projectPaths, instanceCount: r.instanceCount)
        }
    }

    public static func filter(_ rows: [PluginRow], query: String, status: PluginStatusFilter, category: AuFineCategory?) -> [PluginRow] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return rows.filter { row in
            switch status {
            case .all: break
            case .installed: if row.status != .installed { return false }
            case .missing: if row.status != .missing { return false }
            case .multipleProjects: if row.projectCount < 2 { return false }
            }
            if let category, row.fineCategory != category { return false }
            return needle.isEmpty || row.name.lowercased().contains(needle) || row.fingerprint.lowercased().contains(needle)
        }
    }

    /// Per-category counts, descending then alphabetical, "Uncategorised" always last.
    public static func facets(_ rows: [PluginRow]) -> [CategoryFacet] {
        var counts: [AuFineCategory: Int] = [:]
        for r in rows { counts[r.fineCategory, default: 0] += 1 }
        return counts.map { CategoryFacet(category: $0.key, count: $0.value) }.sorted { a, b in
            if a.category == .uncategorised { return false }
            if b.category == .uncategorised { return true }
            return a.count != b.count ? a.count > b.count : a.category.rawValue < b.category.rawValue
        }
    }

    /// Most-used first (the answer to "what do I depend on?"), ties by name.
    public static func sortedByUsage(_ rows: [PluginRow]) -> [PluginRow] {
        rows.sorted {
            $0.projectCount != $1.projectCount ? $0.projectCount > $1.projectCount
                : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
