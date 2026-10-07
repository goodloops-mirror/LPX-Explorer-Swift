import Foundation

/// Reference to an Audio Unit component descriptor stored in `ProjectData`.
/// The three 4CCs are in the human-readable order Logic / `auval` show
/// (little-endian reversal already undone).
public struct AURef: Equatable, Hashable, Sendable, Codable {
    public var typeCode: String
    public var subtype: String
    public var manufacturer: String
    /// Byte offset of the type-code 4CC in the input.
    public var offset: Int
    /// Set when the parser recovers the full name itself (Apple stock plug-ins).
    public var displayName: String?

    public init(typeCode: String, subtype: String, manufacturer: String, offset: Int, displayName: String? = nil) {
        self.typeCode = typeCode
        self.subtype = subtype
        self.manufacturer = manufacturer
        self.offset = offset
        self.displayName = displayName
    }

    /// `"{type}/{subtype}/{manufacturer}"` — lookup key shared with `auval -l`.
    public var fingerprint: String { "\(typeCode)/\(subtype)/\(manufacturer)" }
}
