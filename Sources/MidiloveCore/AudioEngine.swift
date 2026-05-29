import Foundation
import AVFoundation

/// Wraps `AVAudioEngine` + `AVAudioUnitSampler` + a simple effects chain
/// (low-pass filter → small reverb → master mixer). Exposes normalized
/// 0–1 setters so MIDI controls can map straight in.
///
/// MIDI events from `MIDIEngine` get forwarded into the sampler so it
/// responds to notes, pitch bend, etc. — the way a hardware synth would.
/// CC 64 (sustain pedal) is implemented in our own code rather than
/// delegated to the SoundFont.
public final class AudioEngine: @unchecked Sendable {
    public let engine = AVAudioEngine()
    public let sampler = AVAudioUnitSampler()
    public let filter = AVAudioUnitEQ(numberOfBands: 1)
    public let reverb = AVAudioUnitReverb()
    private let voiceChannel: UInt8 = 0

    // Sustain pedal bookkeeping.
    private var sustainOn = false
    private var sustainedNotes: Set<UInt8> = []
    private var heldNotes: Set<UInt8> = []

    public init() {
        engine.attach(sampler)
        engine.attach(filter)
        engine.attach(reverb)

        // Low-pass filter starts wide open so the dry sound is untouched
        // until the user turns R1 down.
        let band = filter.bands[0]
        band.filterType = .lowPass
        band.frequency = 20_000
        band.bypass = false

        // Small reverb preset keeps DSP cost low. Starts fully dry; R2 fades
        // it in.
        reverb.loadFactoryPreset(.smallRoom)
        reverb.wetDryMix = 0

        engine.connect(sampler, to: filter, format: nil)
        engine.connect(filter, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)

        // Default master volume — physical slider takes over once user
        // touches it.
        engine.mainMixerNode.outputVolume = 0.9
    }

    public func start() throws {
        try engine.start()
    }

    public func loadSoundFont(at url: URL) throws {
        try sampler.loadSoundBankInstrument(
            at: url,
            program: 0,
            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
            bankLSB: UInt8(kAUSampler_DefaultBankLSB)
        )
    }

    /// Switch to a different patch. Briefly silences anything ringing out
    /// so we don't get stuck notes after the swap.
    public func load(_ instrument: Instrument) throws {
        panic()
        try sampler.loadSoundBankInstrument(
            at: instrument.soundFontURL,
            program: instrument.program,
            bankMSB: instrument.bankMSB,
            bankLSB: instrument.bankLSB
        )
    }

    // MARK: - Live parameters

    /// 0 = closed (dark/muffled), 1 = wide open (bright). Log-mapped so the
    /// knob feels musical across its range.
    public func setFilterCutoff(normalized: Float) {
        let n = max(0, min(1, normalized))
        // 80 Hz → 20 kHz across the sweep.
        let freq = 80.0 * powf(250.0, n)
        filter.bands[0].frequency = freq
    }

    /// 0 = bone dry, 1 = drenched. Capped at 60% wet so it never drowns
    /// out the dry signal entirely.
    public func setReverbMix(normalized: Float) {
        let n = max(0, min(1, normalized))
        reverb.wetDryMix = n * 60
    }

    /// 0 = silent, 1 = full. Squared to give finer control at the quiet end.
    public func setMasterVolume(normalized: Float) {
        let n = max(0, min(1, normalized))
        engine.mainMixerNode.outputVolume = n * n
    }

    // MARK: - MIDI handling

    public func handle(_ event: MIDIEvent) {
        switch event {
        case .noteOn(_, let note, let velocity):
            heldNotes.insert(note)
            sustainedNotes.remove(note)
            sampler.startNote(note, withVelocity: velocity, onChannel: voiceChannel)

        case .noteOff(_, let note):
            heldNotes.remove(note)
            if sustainOn {
                sustainedNotes.insert(note)
            } else {
                sampler.stopNote(note, onChannel: voiceChannel)
            }

        case .controlChange(_, let cc, let value, _):
            if cc == 64 {
                handleSustain(value: value)
            } else {
                sampler.sendController(cc, withValue: value, onChannel: voiceChannel)
            }

        case .pitchBend(_, let value):
            let raw = UInt16(max(0, min(16383, value + 8192)))
            sampler.sendPitchBend(raw, onChannel: voiceChannel)

        case .aftertouch(_, let pressure):
            sampler.sendPressure(pressure, onChannel: voiceChannel)

        case .programChange:
            break
        }
    }

    private func handleSustain(value: UInt8) {
        let down = value >= 64
        if down == sustainOn { return }
        sustainOn = down
        if !down {
            for note in sustainedNotes where !heldNotes.contains(note) {
                sampler.stopNote(note, onChannel: voiceChannel)
            }
            sustainedNotes.removeAll()
        }
    }

    public func panic() {
        for note in heldNotes.union(sustainedNotes) {
            sampler.stopNote(note, onChannel: voiceChannel)
        }
        heldNotes.removeAll()
        sustainedNotes.removeAll()
        sustainOn = false
    }
}
