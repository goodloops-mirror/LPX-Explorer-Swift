import AVFoundation
import XCTest
@testable import LpxCore

final class AudioInventoryTests: XCTestCase {
    private func write(_ url: URL, _ bytes: [UInt8] = Array("AAAA".utf8), mtime: Date? = nil) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: url)
        if let mtime { try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path) }
    }

    private func bundle() throws -> URL { try Fixture.tempDir().appendingPathComponent("song.logicx") }

    /// A real, valid mono 16-bit 44.1 kHz WAV of `seconds` length.
    private func writeWav(_ url: URL, seconds: Double) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44100, channels: 1, interleaved: true)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        let frames = AVAudioFrameCount(seconds * 44100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        try file.write(from: buffer)
    }

    func testEmptyWhenBundleHasNoAudioSubdirs() throws {
        let b = try bundle()
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        XCTAssertTrue(AudioInventory.collect(bundle: b).isEmpty)
    }

    func testFindsAllThreeBucketsAtRoot() throws {
        let b = try bundle()
        try write(b.appendingPathComponent("Bounces/mix.wav"))
        try write(b.appendingPathComponent("Audio Files/take.aif"))
        try write(b.appendingPathComponent("Freeze Files/gtr.caf"))

        let files = AudioInventory.collect(bundle: b, durations: false)

        XCTAssertEqual(Dictionary(uniqueKeysWithValues: files.map { ($0.fileName, $0.category) }),
                       ["mix.wav": .bounce, "take.aif": .audioRegion, "gtr.caf": .freezeFile])
    }

    func testWalksBucketsRecursively() throws {
        let b = try bundle()
        try write(b.appendingPathComponent("Audio Files/Drum Takes/Take 03/kick.wav"))
        let files = AudioInventory.collect(bundle: b, durations: false)
        XCTAssertEqual(files.map(\.fileName), ["kick.wav"])
        XCTAssertEqual(files.first?.category, .audioRegion)
    }

    func testWalksMediaSubdirectoryAndAlternatives() throws {
        let b = try bundle()
        try write(b.appendingPathComponent("Media/Audio Files/take.wav"))
        try write(b.appendingPathComponent("Media/Bounces/mix.wav"))
        try write(b.appendingPathComponent("Alternatives/001/Bounces/alt_mix.wav"))
        try write(b.appendingPathComponent("Alternatives/001/Media/Freeze Files/frz.wav"))

        let names = Set(AudioInventory.collect(bundle: b, durations: false).map(\.fileName))

        XCTAssertEqual(names, ["take.wav", "mix.wav", "alt_mix.wav", "frz.wav"])
    }

    func testIgnoresNonAudioFilesAndMatchesExtensionsCaseInsensitively() throws {
        let b = try bundle()
        try write(b.appendingPathComponent("Bounces/notes.txt"))
        try write(b.appendingPathComponent("Bounces/.DS_Store"))
        try write(b.appendingPathComponent("Bounces/LOUD.WAV"))
        XCTAssertEqual(AudioInventory.collect(bundle: b, durations: false).map(\.fileName), ["LOUD.WAV"])
    }

    func testRecordsSizeAndMtime() throws {
        let b = try bundle()
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        try write(b.appendingPathComponent("Bounces/a.wav"), [UInt8](repeating: 1, count: 123), mtime: when)
        let f = try XCTUnwrap(AudioInventory.collect(bundle: b, durations: false).first)
        XCTAssertEqual(f.sizeBytes, 123)
        XCTAssertEqual(f.mtimeUnix, 1_700_000_000)
        XCTAssertTrue(f.previewable)
        XCTAssertNil(f.durationSeconds)
    }

    func testDurationFromRealWavAndNilForGarbage() throws {
        let b = try bundle()
        try writeWav(b.appendingPathComponent("Bounces/two_seconds.wav"), seconds: 2)
        try write(b.appendingPathComponent("Bounces/broken.wav"), Array("not audio".utf8))

        let files = AudioInventory.collect(bundle: b)

        let good = try XCTUnwrap(files.first { $0.fileName == "two_seconds.wav" })
        XCTAssertEqual(try XCTUnwrap(good.durationSeconds), 2.0, accuracy: 0.01)
        XCTAssertNil(files.first { $0.fileName == "broken.wav" }?.durationSeconds)
        XCTAssertEqual(AudioDuration.seconds(of: b.appendingPathComponent("Bounces/two_seconds.wav")) ?? 0, 2.0, accuracy: 0.01)
    }

    func testHeroPrefersNewestBounceOverBiggerAudioFiles() throws {
        let b = try bundle()
        try write(b.appendingPathComponent("Audio Files/take_huge.wav"), [UInt8](repeating: 0, count: 10_000))
        try write(b.appendingPathComponent("Bounces/old_mix.wav"), mtime: Date(timeIntervalSince1970: 1_000))
        try write(b.appendingPathComponent("Bounces/new_mix.wav"), mtime: Date(timeIntervalSince1970: 2_000))

        XCTAssertEqual(AudioInventory.pickHero(AudioInventory.collect(bundle: b, durations: false))?.fileName, "new_mix.wav")
    }

    func testHeroFallsBackToLargestAudioRegionThenNewestFreeze() throws {
        let b = try bundle()
        try write(b.appendingPathComponent("Audio Files/small.wav"), [UInt8](repeating: 0, count: 10))
        try write(b.appendingPathComponent("Audio Files/big.wav"), [UInt8](repeating: 0, count: 1_000))
        try write(b.appendingPathComponent("Freeze Files/frz.wav"))
        XCTAssertEqual(AudioInventory.pickHero(AudioInventory.collect(bundle: b, durations: false))?.fileName, "big.wav")

        let b2 = try bundle()
        try write(b2.appendingPathComponent("Freeze Files/old.wav"), mtime: Date(timeIntervalSince1970: 1))
        try write(b2.appendingPathComponent("Freeze Files/new.wav"), mtime: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(AudioInventory.pickHero(AudioInventory.collect(bundle: b2, durations: false))?.fileName, "new.wav")
    }

    func testHeroIsNilWhenNothingPreviewable() {
        XCTAssertNil(AudioInventory.pickHero([]))
    }

    func testResultsAreDeterministicallyOrdered() throws {
        let b = try bundle()
        for n in ["c", "a", "b"] { try write(b.appendingPathComponent("Bounces/\(n).wav")) }
        XCTAssertEqual(AudioInventory.collect(bundle: b, durations: false).map(\.fileName), ["a.wav", "b.wav", "c.wav"])
    }
}
