import AVFoundation
import XCTest
@testable import LpxCore

final class WaveformPeaksTests: XCTestCase {
    /// Mono/stereo 16-bit 44.1 kHz WAV where `level(second)` gives the constant amplitude of each second.
    private func writeWav(_ url: URL, seconds: Int, channels: AVAudioChannelCount = 1, level: (Int) -> Float) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44_100, channels: channels, interleaved: true)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        for s in 0..<seconds {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
            buffer.frameLength = 44_100
            let amp = Int16(level(s) * 32_000)
            for c in 0..<Int(channels) {
                let data = buffer.int16ChannelData![c]
                for i in 0..<44_100 { data[i * Int(channels)] = amp }   // interleaved: one write per frame is enough for mono; stereo handled below
            }
            if channels == 2 { for i in 0..<44_100 { buffer.int16ChannelData![0][i * 2 + 1] = 0 } }
            try file.write(from: buffer)
        }
    }

    func testPeaksFollowTheLoudnessOverTime() throws {
        let url = try Fixture.tempDir().appendingPathComponent("a.wav")
        try writeWav(url, seconds: 4) { $0 < 2 ? 0.05 : 0.9 }
        let result = try XCTUnwrap(WaveformPeaks.compute(url: url, bins: 8))
        XCTAssertEqual(result.peaks.count, 8)
        XCTAssertEqual(result.duration, 4, accuracy: 0.01)
        XCTAssertTrue(result.peaks[0..<4].allSatisfy { $0 < 0.1 }, "\(result.peaks)")
        XCTAssertTrue(result.peaks[4..<8].allSatisfy { $0 > 0.8 }, "\(result.peaks)")
        XCTAssertTrue(result.peaks.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testAskingForMoreBinsThanSamplesStillWorks() throws {
        let url = try Fixture.tempDir().appendingPathComponent("short.wav")
        try writeWav(url, seconds: 1) { _ in 0.5 }
        let result = try XCTUnwrap(WaveformPeaks.compute(url: url, bins: 1000))
        XCTAssertEqual(result.peaks.count, 1000)
        XCTAssertTrue(result.peaks.allSatisfy { $0 > 0.4 }, "every bin covers some audio")
    }

    func testUnreadableFilesGiveNil() throws {
        let url = try Fixture.tempDir().appendingPathComponent("not-audio.wav")
        try Data("this is not audio".utf8).write(to: url)
        XCTAssertNil(WaveformPeaks.compute(url: url, bins: 10))
        XCTAssertNil(WaveformPeaks.compute(url: url.deletingLastPathComponent().appendingPathComponent("missing.wav"), bins: 10))
    }

    func testCancellationStopsTheRead() throws {
        let url = try Fixture.tempDir().appendingPathComponent("c.wav")
        try writeWav(url, seconds: 3) { _ in 0.5 }
        XCTAssertNil(WaveformPeaks.compute(url: url, bins: 10, isCancelled: { true }))
    }
}
