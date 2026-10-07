import Foundation

/// Thin wrappers over libc `memchr` / `memmem` (SIMD-accelerated) for jumping between
/// candidate positions in multi-megabyte ProjectData buffers.
enum ByteSearch {
    /// Index of the first `byte` at or after `from`, or nil.
    @inline(__always)
    static func indexOf(_ byte: UInt8, in buf: UnsafeBufferPointer<UInt8>, from: Int) -> Int? {
        guard let base = buf.baseAddress, from < buf.count,
              let p = memchr(base + from, Int32(byte), buf.count - from) else { return nil }
        return base.distance(to: p.assumingMemoryBound(to: UInt8.self))
    }

    /// Index of the first occurrence of `needle` at or after `from`, or nil.
    static func indexOf(_ needle: [UInt8], in buf: UnsafeBufferPointer<UInt8>, from: Int) -> Int? {
        guard let base = buf.baseAddress, from + needle.count <= buf.count else { return nil }
        return needle.withUnsafeBufferPointer { n in
            guard let p = memmem(base + from, buf.count - from, n.baseAddress, n.count) else { return nil }
            return base.distance(to: p.assumingMemoryBound(to: UInt8.self))
        }
    }
}
