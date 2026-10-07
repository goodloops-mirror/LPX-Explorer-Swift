import XCTest
@testable import LpxCore

final class PluginCatalogTests: XCTestCase {
    func testCoarseCategoryFromTypeCode() {
        for t in ["aufx", "aufc", "aupn", "augn", "auol"] { XCTAssertEqual(PluginCatalog.category(ofType: t), .effect, t) }
        XCTAssertEqual(PluginCatalog.category(ofType: "aumu"), .instrument)
        // aumf = "music effect": an AUDIO effect that also responds to MIDI (FabFilter Pro-Q, u-he MFM2…).
        // Logic hosts it in the audio FX slots. Only aumi is a true MIDI processor.
        XCTAssertEqual(PluginCatalog.category(ofType: "aumf"), .effect)
        XCTAssertEqual(PluginCatalog.category(ofType: "aumi"), .midi)
        XCTAssertEqual(PluginCatalog.category(ofType: "xxxx"), .other)
    }

    func testCoarseCategoryFromFingerprint() {
        XCTAssertEqual(PluginCatalog.category(ofFingerprint: "aumu/EZk2/Toon"), .instrument)
        XCTAssertEqual(PluginCatalog.category(ofFingerprint: "aufx/Comp/appl"), .effect)
        XCTAssertEqual(PluginCatalog.category(ofFingerprint: "garbage"), .other)
    }

    func testKnownStockNamesGetTheirFineCategory() {
        let cases: [(String, AuFineCategory)] = [
            ("Channel EQ", .eq), ("Compressor", .dynamics), ("Limiter", .dynamics), ("ChromaVerb", .reverb),
            ("Space Designer", .reverb), ("Tape Delay", .delay), ("Chorus", .modulation), ("Overdrive", .distortion),
            ("Pitch Correction", .pitch), ("Direction Mixer", .imaging), ("Multimeter", .metering), ("Gain", .utility),
            ("Exciter", .specialty), ("Drum Machine Designer", .drumMachine), ("Quick Sampler", .sampler),
            ("AUDynamicsProcessor", .dynamics), ("EXS24", .sampler),
        ]
        for (name, cat) in cases {
            XCTAssertEqual(PluginCatalog.fineCategory(displayName: name, fingerprint: "aufx/xxxx/appl"), cat, name)
        }
    }

    func testTableIsComplete() {
        XCTAssertEqual(PluginCatalog.fineCategoriesByName.count, 91, "ported from the original table")
    }

    func testUnknownEffectIsUncategorised() {
        XCTAssertEqual(PluginCatalog.fineCategory(displayName: "Some Boutique Plug", fingerprint: "aufx/Bout/Mfr1"), .uncategorised)
        XCTAssertEqual(PluginCatalog.fineCategory(displayName: nil, fingerprint: "aufx/Bout/Mfr1"), .uncategorised)
    }

    func testInstrumentsAndMidiFallBackToCoarseBuckets() {
        XCTAssertEqual(PluginCatalog.fineCategory(displayName: "Kontakt", fingerprint: "aumu/NiMa/-NI-"), .instrument)
        XCTAssertEqual(PluginCatalog.fineCategory(displayName: nil, fingerprint: "aumu/xxxx/yyyy"), .instrument)
        XCTAssertEqual(PluginCatalog.fineCategory(displayName: "Scaler 2", fingerprint: "aumi/S2lc/iaMe"), .midiEffect)
        XCTAssertEqual(PluginCatalog.fineCategory(displayName: "Arp", fingerprint: "aumi/abcd/efgh"), .midiEffect)
        // A music effect is an audio effect, not a MIDI effect, and isn't an instrument either.
        XCTAssertEqual(PluginCatalog.fineCategory(displayName: "FabFilter: Pro-Q 3", fingerprint: "aumf/FQ3p/FabF"), .uncategorised)
    }

    func testNameTableWinsOverTypeCodeLookup() {
        XCTAssertEqual(PluginCatalog.fineCategory(displayName: "Sampler", fingerprint: "aumu/samp/appl"), .sampler)
    }

    func testLookupIsCaseSensitiveLikeAuval() {
        XCTAssertEqual(PluginCatalog.fineCategory(displayName: "channel eq", fingerprint: "aufx/chan/appl"), .uncategorised)
    }
}
