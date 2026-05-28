import Foundation

/// A parsed MIDI message. We keep the raw channel + CC so consumers can
/// route untransformed events to a synth/sampler if they want, and we also
/// supply a resolved `ControlID` for any CC that maps to a known PCR-500
/// physical control.
public enum MIDIEvent: Sendable {
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8)
    case noteOff(channel: UInt8, note: UInt8)
    case controlChange(channel: UInt8, cc: UInt8, value: UInt8, control: ControlID)
    case pitchBend(channel: UInt8, value: Int) // -8192...+8191
    case aftertouch(channel: UInt8, pressure: UInt8)
    case programChange(channel: UInt8, program: UInt8)
}
