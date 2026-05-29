import Foundation
import AVFoundation

/// Wraps `AVAudioEngine` + `AVAudioUnitSampler` + a small effects chain
/// (low-pass filter → delay → reverb → master mixer). Exposes normalized
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
    public let delay = AVAudioUnitDelay()
    public let reverb = AVAudioUnitReverb()
    private let voiceChannel: UInt8 = 0

    // Sustain pedal bookkeeping.
    private var sustainOn = false
    private var sustainedNotes: Set<UInt8> = []
    private var heldNotes: Set<UInt8> = []

    // Filter LFO state — driven by the mod wheel.
    private var filterBase: Float = 1.0     // user-set cutoff, 0…1
    private var filterModDepth: Float = 0.0 // LFO depth, 0…1
    private var lfoPhase: Float = 0
    private let lfoRateHz: Float = 0.6      // slow wobble, classic mod-wheel feel
    private var lfoTimer: Timer?

    public init() {
        engine.attach(sampler)
        engine.attach(filter)
        engine.attach(delay)
        engine.attach(reverb)

        let band = filter.bands[0]
        band.filterType = .lowPass
        band.frequency = 20_000
        band.bypass = false

        // Delay defaults: ~3/8 of a second is a nice musical echo; feedback
        // and wet both start at 0 so the chain is silent on the dry path
        // until R3/R4 are turned up.
        delay.delayTime = 0.4
        delay.feedback = 0
        delay.wetDryMix = 0
        delay.lowPassCutoff = 8_000

        reverb.loadFactoryPreset(.smallRoom)
        reverb.wetDryMix = 0

        engine.connect(sampler, to: filter, format: nil)
        engine.connect(filter, to: delay, format: nil)
        engine.connect(delay, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)

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

    public func setFilterCutoff(normalized: Float) {
        filterBase = max(0, min(1, normalized))
        applyFilterFrequency()
    }

    /// Mod wheel → low-frequency oscillator on the filter. At 0 the filter
    /// sits exactly where R1 put it; at 1 it sweeps ±~50% of the range
    /// around that point at ~0.6 Hz.
    public func setFilterMod(normalized: Float) {
        filterModDepth = max(0, min(1, normalized))
        if filterModDepth > 0 {
            if lfoTimer == nil {
                let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                    self?.tickLFO()
                }
                RunLoop.main.add(timer, forMode: .common)
                lfoTimer = timer
            }
        } else {
            lfoTimer?.invalidate()
            lfoTimer = nil
            applyFilterFrequency()
        }
    }

    public func setReverbMix(normalized: Float) {
        let n = max(0, min(1, normalized))
        reverb.wetDryMix = n * 60
    }

    public func setDelayMix(normalized: Float) {
        let n = max(0, min(1, normalized))
        delay.wetDryMix = n * 50 // cap at 50% so dry signal always reads through
    }

    /// 0 = single slap-back, 1 = nearly self-oscillating chaos.
    public func setDelayFeedback(normalized: Float) {
        let n = max(0, min(1, normalized))
        delay.feedback = n * 90
    }

    public func setMasterVolume(normalized: Float) {
        let n = max(0, min(1, normalized))
        engine.mainMixerNode.outputVolume = n * n
    }

    /// 0 = full left, 0.5 = center, 1 = full right.
    /// Sends standard MIDI CC 10 (pan) so the SoundFont handles positioning
    /// at the synth level. AVAudioMixing.pan only applies on sources
    /// connected directly to a mixer; our chain has effects in between, so
    /// CC 10 is both simpler and more portable.
    public func setPan(normalized: Float) {
        let n = max(0, min(1, normalized))
        let panMidi = UInt8(n * 127)
        sampler.sendController(10, withValue: panMidi, onChannel: voiceChannel)
    }

    private func tickLFO() {
        lfoPhase += 2 * .pi * lfoRateHz / 60.0
        if lfoPhase > 2 * .pi { lfoPhase -= 2 * .pi }
        applyFilterFrequency()
    }

    private func applyFilterFrequency() {
        // Sin wave centered at 0, magnitude scaled by depth, applied around
        // user-set cutoff in normalized space then de-normalized to Hz.
        let lfoOffset = sin(lfoPhase) * 0.3 * filterModDepth
        let effective = max(0, min(1, filterBase + lfoOffset))
        filter.bands[0].frequency = 80.0 * powf(250.0, effective)
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
