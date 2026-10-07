import Foundation

public struct AuvalEntry: Equatable, Hashable, Sendable, Codable {
    public var fingerprint: String
    public var type4CC: String
    /// Leading/trailing spaces are significant ("EB  ").
    public var subtype4CC: String
    public var manufacturer4CC: String
    public var name: String
}

public enum AuvalParser {
    /// Parse one line of `auval -l`; nil for headers, blanks and malformed lines.
    ///
    /// The columns are fixed-width (type @0, subtype @5, manufacturer @10), NOT
    /// whitespace separated: 4CCs can contain literal spaces ("kHs "). Works on
    /// UTF-8 bytes so a multi-byte character in the column area is rejected
    /// rather than mis-sliced.
    public static func parseLine(_ line: String) -> AuvalEntry? {
        let bytes = Array(line.utf8)
        let sep = Array(" - ".utf8)
        guard let sepAt = indexOf(sep, in: bytes), sepAt >= 14 else { return nil }
        guard let type = fourCC(bytes, 0), let sub = fourCC(bytes, 5), let mfr = fourCC(bytes, 10) else { return nil }

        let rest = bytes[(sepAt + sep.count)...]
        var nameBytes = rest
        if let f = indexOf(Array("(file:".utf8), in: Array(rest)) {
            nameBytes = rest.prefix(f)
        }
        let name = String(decoding: nameBytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return AuvalEntry(fingerprint: "\(type)/\(sub)/\(mfr)", type4CC: type, subtype4CC: sub, manufacturer4CC: mfr, name: name)
    }

    private static func fourCC(_ b: [UInt8], _ start: Int) -> String? {
        guard start + 4 <= b.count else { return nil }
        return String(validatingUTF8: b[start ..< start + 4].map { CChar(bitPattern: $0) } + [0])
    }

    private static func indexOf(_ needle: [UInt8], in hay: [UInt8]) -> Int? {
        guard !needle.isEmpty, hay.count >= needle.count else { return nil }
        for i in 0...(hay.count - needle.count) where hay[i] == needle[0] && Array(hay[i ..< i + needle.count]) == needle {
            return i
        }
        return nil
    }
}
