import Foundation

/// Coarse category from the AU type 4CC. Logic's fine-grained taxonomy isn't recoverable from
/// plug-in bundles, so the type code is the only universal signal.
public enum AuCategory: String, Sendable, Equatable { case effect, instrument, midi, other }

/// Logic-Plug-in-Manager-style category. Effects are subdivided via a static name table;
/// instruments and MIDI processors keep their coarse buckets.
public enum AuFineCategory: String, Sendable, Equatable, CaseIterable {
    case eq = "EQ", dynamics = "Dynamics", reverb = "Reverb", delay = "Delay", modulation = "Modulation"
    case distortion = "Distortion", pitch = "Pitch", imaging = "Imaging", metering = "Metering"
    case utility = "Utility", specialty = "Specialty", drumMachine = "Drum Machine", sampler = "Sampler"
    case instrument = "Instrument", midiEffect = "MIDI Effect", uncategorised = "Uncategorised"
}

public enum PluginCatalog {
    // `aumf` ("music effect") is an audio effect that also responds to MIDI and lives in Logic's audio
    // FX slots; only `aumi` is a MIDI processor. (The legacy app treated both as MIDI effects.)
    private static let effectTypes: Set<String> = ["aufx", "aufc", "aupn", "augn", "auol", "aumf"]
    private static let midiTypes: Set<String> = ["aumi"]

    public static func category(ofType typeCode: String) -> AuCategory {
        if effectTypes.contains(typeCode) { return .effect }
        if typeCode == "aumu" { return .instrument }
        if midiTypes.contains(typeCode) { return .midi }
        return .other
    }

    /// Fingerprints look like `"{type}/{subtype}/{manufacturer}"`; anything else is `.other`.
    public static func category(ofFingerprint fingerprint: String) -> AuCategory {
        guard let slash = fingerprint.firstIndex(of: "/") else { return .other }
        return category(ofType: String(fingerprint[..<slash]))
    }

    /// Resolve the fine category from a plug-in's display name (preferred; case-sensitive like
    /// `auval`), else fall back to the coarse bucket so instruments / MIDI plug-ins don't land in
    /// "Uncategorised".
    public static func fineCategory(displayName: String?, fingerprint: String) -> AuFineCategory {
        if let displayName, let hit = fineCategoriesByName[displayName] { return hit }
        switch category(ofFingerprint: fingerprint) {
        case .instrument: return .instrument
        case .midi: return .midiEffect
        default: return .uncategorised
        }
    }

    /// Logic's stock plug-ins aren't registered system AUs (`auval -l` doesn't list them), so the
    /// display name recovered from ProjectData is the only reliable key. Coverage is deliberately
    /// partial; the rail reports how many plug-ins are categorised.
    static let fineCategoriesByName: [String: AuFineCategory] = [
        "Channel EQ": .eq,
        "Linear Phase EQ": .eq,
        "Match EQ": .eq,
        "Single-Band EQ": .eq,
        "Vintage Console EQ": .eq,
        "Vintage Graphic EQ": .eq,
        "Vintage Tube EQ": .eq,
        "Graphic EQ": .eq,
        "AUNBandEQ": .eq,
        "AUParametricEQ": .eq,
        "AUGraphicEQ": .eq,
        "Compressor": .dynamics,
        "Adaptive Limiter": .dynamics,
        "Limiter": .dynamics,
        "Multipressor": .dynamics,
        "DeEsser 2": .dynamics,
        "Noise Gate": .dynamics,
        "Expander": .dynamics,
        "Enveloper": .dynamics,
        "AUDynamicsProcessor": .dynamics,
        "AUPeakLimiter": .dynamics,
        "AUMultibandCompressor": .dynamics,
        "Space Designer": .reverb,
        "ChromaVerb": .reverb,
        "EnVerb": .reverb,
        "SilverVerb": .reverb,
        "PlatinumVerb": .reverb,
        "AUMatrixReverb": .reverb,
        "AUReverb2": .reverb,
        "Echo": .delay,
        "Tape Delay": .delay,
        "Sample Delay": .delay,
        "Delay Designer": .delay,
        "Stereo Delay": .delay,
        "AUDelay": .delay,
        "AUSampleDelay": .delay,
        "Chorus": .modulation,
        "Ensemble": .modulation,
        "Modulation Delay": .modulation,
        "Phaser": .modulation,
        "Flanger": .modulation,
        "Tremolo": .modulation,
        "RingShifter": .modulation,
        "Microphaser": .modulation,
        "Scanner Vibrato": .modulation,
        "Spreader": .modulation,
        "RotorCabinet": .modulation,
        "Distortion": .distortion,
        "Overdrive": .distortion,
        "Phase Distortion": .distortion,
        "Bitcrusher": .distortion,
        "Clip Distortion": .distortion,
        "Distortion II": .distortion,
        "AUDistortion": .distortion,
        "Pitch Correction": .pitch,
        "Pitch Shifter": .pitch,
        "Pitch Shifter II": .pitch,
        "Vocal Transformer": .pitch,
        "AUNewPitch": .pitch,
        "AUPitch": .pitch,
        "AUNewTimePitch": .pitch,
        "Direction Mixer": .imaging,
        "Stereo Spread": .imaging,
        "Binaural Post-Processing": .imaging,
        "Multimeter": .metering,
        "Tuner": .metering,
        "Loudness Meter": .metering,
        "Level Meter": .metering,
        "Correlation Meter": .metering,
        "BPM Counter": .metering,
        "Gain": .utility,
        "Test Oscillator": .utility,
        "I/O": .utility,
        "External Instrument": .utility,
        "AUFilter": .utility,
        "AUHipass": .utility,
        "AULowpass": .utility,
        "AUBandpass": .utility,
        "AUHighShelfFilter": .utility,
        "AULowShelfFilter": .utility,
        "Speech Enhancer": .specialty,
        "Exciter": .specialty,
        "Spectral Gate": .specialty,
        "Drum Machine Designer": .drumMachine,
        "Drum Synth": .drumMachine,
        "Drum Kit Designer": .drumMachine,
        "Sampler": .sampler,
        "Quick Sampler": .sampler,
        "Auto Sampler": .sampler,
        "AUSampler": .sampler,
        "EXS24": .sampler,
    ]
}
