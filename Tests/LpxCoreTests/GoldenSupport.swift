import Foundation
import XCTest

/// Golden files come from the legacy Rust parser run over `example_projects/`
/// (see scripts/make-golden.sh). Tests skip when either side is absent.
enum Golden {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static var projectsDir: URL { root.appendingPathComponent("example_projects") }
    static var goldenDir: URL { root.appendingPathComponent("Tests/Golden") }

    struct Case { let name: String; let projectData: [UInt8]; let json: [String: Any] }

    static func cases() throws -> [Case] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: goldenDir.path))?.filter { $0.hasSuffix(".json") }.sorted() ?? []
        if names.isEmpty { throw XCTSkip("no golden files — run scripts/make-golden.sh") }
        return try names.map { file in
            let bundle = String(file.dropLast(".json".count))
            let pd = projectsDir.appendingPathComponent("\(bundle)/Alternatives/000/ProjectData")
            guard let data = try? Data(contentsOf: pd, options: .mappedIfSafe) else { throw XCTSkip("example_projects missing") }
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: goldenDir.appendingPathComponent(file))) as! [String: Any]
            return Case(name: bundle, projectData: [UInt8](data), json: json)
        }
    }
}
