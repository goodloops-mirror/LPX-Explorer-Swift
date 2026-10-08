import Foundation

/// How project metadata is written out in the inspector (ported from the original app's ProjectInfo).
public enum MetadataFormat {
    /// Logic stores the frame rate as an index into a SMPTE table; nil for an index we don't know.
    public static func frameRate(index: Int) -> String? {
        let table = ["24 fps", "25 fps", "29.97 fps (drop)", "30 fps (drop)", "29.97 fps", "30 fps", "23.976 fps", "23.976 fps"]
        return table.indices.contains(index) ? table[index] : nil
    }

    /// "48.0 kHz"; "—" when unknown.
    public static func sampleRate(hz: Int) -> String {
        hz > 0 ? String(format: "%.1f kHz", Double(hz) / 1000) : "—"
    }

    /// "C major"; just the key when the mode is unknown; nil when the key was never set.
    public static func key(_ key: String, gender: String) -> String? {
        guard !key.isEmpty, key != "?" else { return nil }
        return gender.isEmpty || gender == "?" ? key : "\(key) \(gender.lowercased())"
    }

    /// "2026-10-08 (3 days ago)"; "—" when the date is unknown.
    public static func dateWithRelative(unix: Int64, now: Date = Date(), locale: Locale = .current) -> String {
        guard unix > 0 else { return "—" }
        let date = Date(timeIntervalSince1970: TimeInterval(unix))
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        let relative = RelativeDateTimeFormatter()
        relative.locale = locale
        relative.unitsStyle = .full
        return "\(day.string(from: date)) (\(relative.localizedString(for: date, relativeTo: now)))"
    }
}
