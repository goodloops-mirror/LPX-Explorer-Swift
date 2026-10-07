import Foundation

/// One Logic "alternative" (variant) of a project: `Alternatives/<index:03>/`.
public struct Alternative: Equatable, Sendable, Codable {
    public var index: Int
    public var displayName: String
    public var isActive: Bool
    /// Path to `WindowImage.jpg` when Logic wrote one (recent versions only).
    public var windowImagePath: String?
    /// mtime of that alternative's ProjectData, unix seconds; 0 when unknown.
    public var lastSavedUnix: Int64

    public init(index: Int, displayName: String, isActive: Bool, windowImagePath: String? = nil, lastSavedUnix: Int64 = 0) {
        self.index = index; self.displayName = displayName; self.isActive = isActive
        self.windowImagePath = windowImagePath; self.lastSavedUnix = lastSavedUnix
    }
}

public enum AlternativesError: Error, Equatable { case invalid(String) }

public enum AlternativesManifest {
    private static let placeholder = "{PROJECT_NAME}"

    /// Parse `Resources/ProjectInformation.plist`. `VariantNamesV2` (with `{PROJECT_NAME}`
    /// placeholder) is preferred, falling back to `VariantNames`. Empty when neither has entries.
    public static func parse(_ data: Data, bundleName: String) throws -> [Alternative] {
        let dict = try rootDictionary(data)
        let active = (dict["ActiveVariant"] as? NSNumber).map(\.intValue).flatMap { $0 >= 0 ? $0 : nil } ?? 0
        let v2 = dict["VariantNamesV2"] as? [String: Any]
        let v1 = dict["VariantNames"] as? [String: Any]
        let source: [String: Any]
        if let v2, !v2.isEmpty { source = v2 } else if let v1 { source = v1 } else { return [] }
        return source.compactMap { key, value -> (Int, String)? in
            guard let index = Int(key), index >= 0, let raw = value as? String else { return nil }
            return (index, raw.replacingOccurrences(of: placeholder, with: bundleName))
        }
        .sorted { $0.0 < $1.0 }
        .map { Alternative(index: $0.0, displayName: $0.1, isActive: $0.0 == active) }
    }

    /// The Logic version that last saved the project, verbatim ("Logic Pro 12.2 (6644)").
    public static func lastSavedFrom(_ data: Data) -> String? {
        (try? rootDictionary(data))?["LastSavedFrom"] as? String
    }

    private static func rootDictionary(_ data: Data) throws -> [String: Any] {
        let root: Any
        do { root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) } catch {
            throw AlternativesError.invalid(error.localizedDescription)
        }
        guard let dict = root as? [String: Any] else { throw AlternativesError.invalid("plist root is not a dictionary") }
        return dict
    }
}

public enum ProjectBundle {
    public static func informationPlistURL(_ bundle: URL) -> URL { bundle.appendingPathComponent("Resources/ProjectInformation.plist") }

    public static func hasInformationPlist(_ bundle: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: informationPlistURL(bundle).path, isDirectory: &isDir) && !isDir.boolValue
    }

    public static func lastSavedFrom(bundle: URL) -> String? {
        (try? Data(contentsOf: informationPlistURL(bundle))).flatMap(AlternativesManifest.lastSavedFrom)
    }

    /// Bundle basename without the `.logicx` extension (any case).
    public static func bundleName(_ bundle: URL) -> String {
        let name = bundle.lastPathComponent
        return name.lowercased().hasSuffix(".logicx") ? String(name.dropLast(".logicx".count)) : name
    }

    /// Alternatives inside a bundle. A missing/invalid manifest on a bundle that still has
    /// ProjectData yields one synthetic entry; a bundle with neither yields none.
    public static func alternatives(of bundle: URL) -> [Alternative] {
        let fm = FileManager.default
        let name = bundleName(bundle)
        var parsed: [Alternative] = []
        if let data = try? Data(contentsOf: informationPlistURL(bundle)),
           let alts = try? AlternativesManifest.parse(data, bundleName: name), !alts.isEmpty {
            parsed = alts
        } else if ProjectParser.locateAlternative(bundle, fm) != nil {
            parsed = [Alternative(index: 0, displayName: name, isActive: true)]
        }
        return parsed.map { alt in
            var alt = alt
            let dir = bundle.appendingPathComponent(String(format: "Alternatives/%03d", alt.index))
            let image = dir.appendingPathComponent("WindowImage.jpg")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: image.path, isDirectory: &isDir), !isDir.boolValue { alt.windowImagePath = image.path }
            let attrs = try? fm.attributesOfItem(atPath: dir.appendingPathComponent("ProjectData").path)
            alt.lastSavedUnix = (attrs?[.modificationDate] as? Date).map { Int64($0.timeIntervalSince1970) } ?? 0
            return alt
        }
    }
}
