import Foundation

enum Fixture {
    static func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lpx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // Canonicalise (/var -> /private/var) so paths compare equal to what the walker returns.
        return URL(fileURLWithPath: String(cString: realpath(url.path, nil)))
    }

    @discardableResult
    static func logicx(in parent: URL, name: String, projectData: [UInt8]? = nil, plistBody: String = "") throws -> URL {
        let bundle = parent.appendingPathComponent(name)
        let alt = bundle.appendingPathComponent("Alternatives/000")
        try FileManager.default.createDirectory(at: alt, withIntermediateDirectories: true)
        let pd = projectData ?? (Array("PADDING_".utf8) + Array("nooT".utf8) + Array("umua".utf8) + Array("2kZE".utf8))
        try Data(pd).write(to: alt.appendingPathComponent("ProjectData"))
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>\(plistBody)</dict></plist>
        """
        try Data(plist.utf8).write(to: alt.appendingPathComponent("MetaData.plist"))
        return bundle
    }
}
