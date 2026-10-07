import Foundation

/// Will this project open cleanly on this Mac? Compares the project's plug-ins with the
/// installed Audio Units (from `auval -l`).
public struct CompatibilityVerdict: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case unknown, clean, warnings, willNotOpen }

    public var status: Status
    public var headline: String
    public var summary: String?
    /// Unique plug-ins that are not installed (Apple stock plug-ins never count as missing).
    public var missing: [AURef]
    /// Unique plug-ins in the project.
    public var total: Int

    /// - Parameter installed: fingerprints of installed AUs, or nil when the registry hasn't been read yet.
    ///
    /// Counts unique plug-ins (by fingerprint), not instances: a plug-in used on ten tracks is
    /// one plug-in to install. Fingerprints are compared verbatim — 4CCs have significant spaces.
    public static func evaluate(plugins: [AURef], installed: Set<String>?) -> CompatibilityVerdict {
        var seen = Set<String>()
        let unique = plugins.filter { seen.insert($0.fingerprint).inserted }
        guard let installed else {
            return CompatibilityVerdict(status: .unknown, headline: "Haven't checked your AUs yet", summary: nil, missing: [], total: unique.count)
        }
        if unique.isEmpty {
            return CompatibilityVerdict(status: .clean, headline: "Opens cleanly", summary: "No plug-ins to check.", missing: [], total: 0)
        }
        // Parser-named plug-ins (Apple stock) ship with Logic, so they're present on any Mac that has it,
        // even when the synthesised fingerprint isn't in `auval -l`.
        let missing = unique.filter { !installed.contains($0.fingerprint) && $0.displayName == nil }
        let n = unique.count, m = missing.count
        func plural(_ k: Int) -> String { "plug-in\(k == 1 ? "" : "s")" }
        switch m {
        case 0:
            return CompatibilityVerdict(status: .clean, headline: "Opens cleanly", summary: "All \(n) \(plural(n)) installed on this Mac.", missing: [], total: n)
        case n:
            return CompatibilityVerdict(status: .willNotOpen, headline: "Will not open", summary: "\(m) of \(n) plug-ins missing on this Mac.", missing: missing, total: n)
        default:
            return CompatibilityVerdict(status: .warnings, headline: "\(m) \(plural(m)) missing", summary: "\(m) of \(n) plug-ins not installed on this Mac.", missing: missing, total: n)
        }
    }
}
