import Foundation
import AVFoundation

/// Wraps `AVAudioEngine` + `AVAudioUnitSampler`, loaded with a SoundFont.
/// MIDI events from `MIDIEngine` get forwarded into the sampler so it
/// responds to notes, pitch bend, etc. — the way a hardware synth would.
///
/// CC 64 (sustain pedal) is *not* forwarded to the sampler; we implement
/// piano-style sustain ourselves so behaviour doesn't depend on whether the
/// loaded SF2 author bothered to define release behaviour.
public final class AudioEngine: @unchecked Sendable {
    public let engine = AVAudioEngine()
    public let sampler = AVAudioUnitSampler()
    private let voiceChannel: UInt8 = 0

    // Sustain pedal bookkeeping.
    private var sustainOn = false
    private var sustainedNotes: Set<UInt8> = []
    private var heldNotes: Set<UInt8> = []

    public init() {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
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

    public func handle(_ event: MIDIEvent) {
        switch event {
        case .noteOn(_, let note, let velocity):
            heldNotes.insert(note)
            sustainedNotes.remove(note) // re-trigger overrides a pending sustained release
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
            // Pedal released — flush any notes whose physical key was let
            // go while the pedal was down.
            for note in sustainedNotes where !heldNotes.contains(note) {
                sampler.stopNote(note, onChannel: voiceChannel)
            }
            sustainedNotes.removeAll()
        }
    }

    /// Panic — emergency all-notes-off (handy for stuck-note diagnostics).
    public func panic() {
        for note in heldNotes.union(sustainedNotes) {
            sampler.stopNote(note, onChannel: voiceChannel)
        }
        heldNotes.removeAll()
        sustainedNotes.removeAll()
        sustainOn = false
    }
}
