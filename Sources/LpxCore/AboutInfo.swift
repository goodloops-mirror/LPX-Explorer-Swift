import Foundation

/// What the About box says: branding, acknowledgement of the original author, licence, and the (optional) links.
/// Links open in the user's browser through the system; the app itself never makes a request.
public enum AboutInfo {
    public struct Segment: Equatable, Sendable {
        public var text: String
        public var link: String?
        public init(_ text: String, link: String? = nil) { self.text = text; self.link = link }
    }
    public struct Line: Equatable, Sendable {
        public var segments: [Segment]
        public init(_ segments: [Segment]) { self.segments = segments }
        public var text: String { segments.map(\.text).joined() }
    }

    public static let company = "Good Loops"
    public static let companyURL = "https://www.good-loops.com"
    public static let originalAuthor = "Rhyd Lewis"
    public static let license = "GPL-3.0-or-later"
    public static let copyright = "© 2026 Good Loops · GPL-3.0-or-later"

    /// (When you set one, also add its URL to `allowedAboutURLs` in NoNetworkTests — the guard is deliberate.)
    /// Placeholders until the public mirror and the coffee page exist: set these and the About box shows the links.
    public static let repositoryURL: String? = nil
    public static let coffeeURL: String? = nil

    /// The version line: release number, commit count and — when it adds information — the exact build from `git describe`.
    /// Nothing known (e.g. `swift run`) reads "Development build".
    public static func versionText(short: String?, build: String?, describe: String?) -> String {
        func clean(_ v: String?) -> String? { (v?.isEmpty ?? true) ? nil : v }
        guard let short = clean(short) else { return "Development build" }
        var parts = ["Version \(short)"]
        if let build = clean(build) { parts.append("build \(build)") }
        if let describe = clean(describe), describe != short, describe != "v" + short { parts.append(describe) }
        return parts.joined(separator: " · ")
    }

    public static func credits(repositoryURL: String? = AboutInfo.repositoryURL, coffeeURL: String? = AboutInfo.coffeeURL) -> [Line] {
        func optionalLink(_ lead: String, _ label: String, _ url: String?, soon: String) -> Line {
            if let url { return Line([Segment(lead), Segment(label, link: url)]) }
            return Line([Segment(lead + label + " — " + soon)])
        }
        return [
            Line([Segment("A "), Segment(company, link: companyURL), Segment(" app.")]),
            Line([Segment("Based on LPX Explorer by \(originalAuthor), whose reverse-engineering of the Logic Pro project format this app builds on. Thank you.")]),
            Line([Segment("Free software under the GNU General Public License, version 3 or later: you may use, change and share it; distributed derivatives must stay GPL with their source available.")]),
            optionalLink("Source code: ", "GitHub", repositoryURL, soon: "link coming soon"),
            optionalLink("Enjoying it? ", "Buy me a coffee", coffeeURL, soon: "link coming soon"),
            Line([Segment("Read-only: never changes your Logic projects. Local only: makes no network requests.")]),
        ]
    }
}
