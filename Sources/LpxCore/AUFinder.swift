import Foundation

public enum AUFinder {
    /// Scan `raw` for Audio Unit component descriptors.
    ///
    /// Standard storage shape: three contiguous little-endian 4CCs laid out as
    /// `manufacturer | type | subtype`. The type field is the anchor; we scan for
    /// `umua` / `xfua` / `fmua` / `imua` (aumu, aufx, aumf, aumi reversed) and read
    /// four bytes either side. Candidates with a non-printable neighbour are noise.
    public static func findAUs(_ raw: [UInt8]) -> [AURef] {
        raw.withUnsafeBufferPointer { findAUs(in: $0) }
    }

    public static func findAUs(in raw: UnsafeBufferPointer<UInt8>) -> [AURef] {
        var found: [AURef] = []
        let n = raw.count
        guard n >= 12 else { return found }
        // Every tag has "u" at index 2 and "a" at index 3: jump between 'u' bytes with
        // memchr, then confirm the tag. (Also lands on the tag's own first 'u'; that
        // candidate simply fails the check.)
        var search = 6 // earliest 'u' = off(4) + 2
        while let pos = ByteSearch.indexOf(UInt8(ascii: "u"), in: raw, from: search) {
            search = pos + 1
            let off = pos - 2
            guard off >= 4, off + 8 <= n, raw[off + 3] == UInt8(ascii: "a"), isTypeTag(raw[off], raw[off + 1]) else { continue }
            let mfr = (raw[off - 4], raw[off - 3], raw[off - 2], raw[off - 1])
            let sub = (raw[off + 4], raw[off + 5], raw[off + 6], raw[off + 7])
            if isPrintable(mfr) && isPrintable(sub) && !isInsideTextBlob(raw, off) {
                found.append(AURef(
                    typeCode: reversed(raw[off], raw[off + 1], raw[off + 2], raw[off + 3]),
                    subtype: reversed(sub.0, sub.1, sub.2, sub.3),
                    manufacturer: reversed(mfr.0, mfr.1, mfr.2, mfr.3),
                    offset: off))
            }
        }
        found += AppleStock.findAUs(in: raw)
        found += AppleDrummer.findAUs(in: raw)
        // Stable by offset (ties keep discovery order: standard triples first).
        return found.enumerated().sorted { ($0.element.offset, $0.offset) < ($1.element.offset, $1.offset) }.map(\.element)
    }

    /// ProjectData embeds base64/plist text blobs. A type tag can occur by chance inside one, with
    /// printable "4CCs" on both sides. Real descriptors sit in binary structure, so a candidate is
    /// noise when the 8 bytes before the manufacturer AND the 8 bytes after the subtype are all text.
    /// (On `example_projects`: 114/114 false hits were text-surrounded, 0/1439 real ones were.)
    /// A window that is empty (candidate at a buffer edge) can't prove text, so the candidate is kept.
    private static func isInsideTextBlob(_ raw: UnsafeBufferPointer<UInt8>, _ off: Int) -> Bool {
        let beforeStart = max(0, off - 12), beforeEnd = off - 4
        let afterStart = off + 8, afterEnd = min(raw.count, off + 16)
        guard beforeEnd > beforeStart, afterEnd > afterStart else { return false }
        return isText(raw, beforeStart, beforeEnd) && isText(raw, afterStart, afterEnd)
    }

    @inline(__always)
    private static func isText(_ raw: UnsafeBufferPointer<UInt8>, _ from: Int, _ to: Int) -> Bool {
        for k in from..<to {
            let b = raw[k]
            if !((b >= 0x20 && b <= 0x7e) || b == 0x09 || b == 0x0a || b == 0x0d) { return false }
        }
        return true
    }

    /// First two bytes of the little-endian type tags: "um", "xf", "fm", "im".
    @inline(__always)
    private static func isTypeTag(_ b0: UInt8, _ b1: UInt8) -> Bool {
        (b0 == 0x75 && b1 == 0x6d) || (b0 == 0x78 && b1 == 0x66) ||
        (b0 == 0x66 && b1 == 0x6d) || (b0 == 0x69 && b1 == 0x6d)
    }

    @inline(__always)
    private static func isPrintable(_ b: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
        func p(_ x: UInt8) -> Bool { x >= 0x20 && x <= 0x7e }
        return p(b.0) && p(b.1) && p(b.2) && p(b.3)
    }

    @inline(__always)
    private static func reversed(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) -> String {
        String(decoding: [b3, b2, b1, b0], as: UTF8.self)
    }
}
