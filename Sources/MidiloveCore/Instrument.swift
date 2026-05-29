import Foundation
import AVFoundation

/// One slot in the instrument rack. Refers to a specific patch inside a
/// SoundFont so the AudioEngine can load it on demand.
public struct Instrument: Sendable, Hashable {
    public let name: String
    public let soundFontURL: URL
    public let program: UInt8
    public let bankMSB: UInt8
    public let bankLSB: UInt8

    public init(name: String,
                soundFontURL: URL,
                program: UInt8 = 0,
                bankMSB: UInt8 = UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8 = UInt8(kAUSampler_DefaultBankLSB)) {
        self.name = name
        self.soundFontURL = soundFontURL
        self.program = program
        self.bankMSB = bankMSB
        self.bankLSB = bankLSB
    }
}
