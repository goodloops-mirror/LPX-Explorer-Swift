import AVFoundation
import Foundation

/// Logic's three audio storage buckets; drives the smart-pick chain Bounce → AudioRegion → FreezeFile.
public enum AudioCategory: String, Codable, Sendable, Equatable {
    /// `Bounces/` — finished or in-progress mixdowns.
    case bounce
    /// `Audio Files/` — raw recorded regions.
    case audioRegion = "audio-region"
    /// `Freeze Files/` — single-track CPU renders.
    case freezeFile = "freeze-file"
}

public struct AudioFile: Equatable, Sendable, Codable {
    public var path: String
    public var fileName: String
    public var category: AudioCategory
    public var sizeBytes: UInt64
    public var mtimeUnix: Int64
    /// AVFoundation can play the container (everything we list).
    public var previewable: Bool
    public var durationSeconds: Double?
}

public enum AudioDuration {
    /// Duration via AVFoundation; nil when the file can't be opened as audio.
    public static func seconds(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let rate = file.processingFormat.sampleRate
        guard rate > 0, file.length > 0 else { return nil }
        return Double(file.length) / rate
    }
}

public enum AudioInventory {
    private static let knownExtensions: Set<String> = ["aiff", "aif", "wav", "mp3", "m4a", "aac", "caf"]
    private static let buckets: [(String, AudioCategory)] = [
        ("Bounces", .bounce), ("Audio Files", .audioRegion), ("Freeze Files", .freezeFile),
    ]

    /// Every recognised audio file in the bundle's Bounces / Audio Files / Freeze Files
    /// buckets, under the bundle root, `Media/`, and each `Alternatives/<NNN>/` (+ its `Media/`).
    /// Read-only. Pass `durations: false` to skip opening each file.
    public static func collect(bundle: URL, durations: Bool = true) -> [AudioFile] {
        let fm = FileManager.default
        var parents = [bundle, bundle.appendingPathComponent("Media")]
        let alternatives = bundle.appendingPathComponent("Alternatives")
        for name in ((try? fm.contentsOfDirectory(atPath: alternatives.path)) ?? []).sorted() {
            let dir = alternatives.appendingPathComponent(name)
            parents += [dir, dir.appendingPathComponent("Media")]
        }
        var out: [AudioFile] = []
        for parent in parents {
            for (name, category) in buckets {
                walk(parent.appendingPathComponent(name), category, durations, fm, &out)
            }
        }
        return out
    }

    private static func walk(_ root: URL, _ category: AudioCategory, _ durations: Bool, _ fm: FileManager, _ out: inout [AudioFile]) {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { return }
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return }
        var found: [AudioFile] = []
        for case let url as URL in e {
            guard knownExtensions.contains(url.pathExtension.lowercased()),
                  let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            found.append(AudioFile(
                path: url.path, fileName: url.lastPathComponent, category: category,
                sizeBytes: UInt64(v.fileSize ?? 0),
                mtimeUnix: v.contentModificationDate.map { Int64($0.timeIntervalSince1970) } ?? 0,
                previewable: true,
                durationSeconds: durations ? AudioDuration.seconds(of: url) : nil))
        }
        out += found.sorted { $0.path < $1.path }
    }

    /// Best answer to "what does this song sound like?": newest bounce → largest audio
    /// region → newest freeze file. Only previewable files are eligible.
    public static func pickHero(_ files: [AudioFile]) -> AudioFile? {
        func newest(_ c: AudioCategory) -> AudioFile? { files.filter { $0.category == c && $0.previewable }.max { $0.mtimeUnix < $1.mtimeUnix } }
        func largest(_ c: AudioCategory) -> AudioFile? { files.filter { $0.category == c && $0.previewable }.max { $0.sizeBytes < $1.sizeBytes } }
        return newest(.bounce) ?? largest(.audioRegion) ?? newest(.freezeFile)
    }
}
