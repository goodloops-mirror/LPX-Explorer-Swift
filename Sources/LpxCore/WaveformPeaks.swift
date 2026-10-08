import AVFoundation
import Foundation

/// A coarse picture of an audio file for drawing its waveform: the peak level (0…1, loudest channel) of each of `bins`
/// equal slices of the file.
public struct WaveformPeaks: Equatable, Sendable {
    public var peaks: [Float]
    public var duration: Double

    /// Reads the file once, in chunks (bounded memory, however long the file). nil if it can't be opened as audio
    /// or `isCancelled` turned true.
    public static func compute(url: URL, bins: Int, isCancelled: () -> Bool = { false }) -> WaveformPeaks? {
        guard bins > 0, let file = try? AVAudioFile(forReading: url) else { return nil }
        let rate = file.processingFormat.sampleRate
        let length = Int(file.length)
        guard rate > 0, length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65_536) else { return nil }
        var peaks = [Float](repeating: 0, count: bins)
        let channels = Int(file.processingFormat.channelCount)
        var frame = 0
        var bin = 0
        // First frame that belongs to bin `k + 1`.
        func edge(_ k: Int) -> Int { Int(Double(k + 1) * Double(length) / Double(bins)) }
        var nextEdge = edge(0)
        while frame < length {
            if isCancelled() { return nil }
            do { try file.read(into: buffer, frameCount: 65_536) } catch { return nil }
            let n = Int(buffer.frameLength)
            guard n > 0, let data = buffer.floatChannelData else { break }
            for i in 0..<n {
                while frame >= nextEdge && bin < bins - 1 { bin += 1; nextEdge = edge(bin) }
                var peak: Float = 0
                for c in 0..<channels { peak = max(peak, abs(data[c][i])) }
                if peak > peaks[bin] { peaks[bin] = peak }
                frame += 1
            }
        }
        return WaveformPeaks(peaks: peaks.map { min($0, 1) }, duration: Double(length) / rate)
    }
}
