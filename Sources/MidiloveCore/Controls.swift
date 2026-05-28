import Foundation

/// A logical control on the PCR-500. Resolved from a `(channel, cc)` pair.
/// Numbers are 1-based to match the physical labels (R1, S1, B1, …).
public enum ControlID: Hashable, Sendable, CustomStringConvertible {
    case knob(Int)            // R1–R9
    case slider(Int)          // S1–S9
    case buttonA(Int)         // first row of assignable buttons
    case buttonB(Int)         // second row
    case buttonC(Int)         // third row
    case modWheel
    case sustainPedal
    case unknown(channel: UInt8, cc: UInt8)

    public var description: String {
        switch self {
        case .knob(let n):        return "R\(n)"
        case .slider(let n):      return "S\(n)"
        case .buttonA(let n):     return "A\(n)"
        case .buttonB(let n):     return "B\(n)"
        case .buttonC(let n):     return "C\(n)"
        case .modWheel:           return "ModWheel"
        case .sustainPedal:       return "Sustain"
        case .unknown(let ch, let cc):
            return "ch\(ch)·CC\(cc)"
        }
    }
}

/// Maps raw `(channel, cc)` tuples to logical controls based on the
/// channel-per-control layout discovered on the user's PCR-500. The PCR
/// sends the *same* CC number on different channels for each physical knob/
/// slider/button — channel becomes the index of the control within its row.
public struct ControlMap {
    public static func resolve(channel: UInt8, cc: UInt8) -> ControlID {
        switch (channel, cc) {
        case (16, 11): return .modWheel
        case (16, 64): return .sustainPedal
        // Eight main knobs share CC 16; ninth knob is CC 18 on ch1.
        case (1...8, 16): return .knob(Int(channel))
        case (1, 18):     return .knob(9)
        // Eight main sliders share CC 17; ninth slider is CC 18 on ch2.
        case (1...8, 17): return .slider(Int(channel))
        case (2, 18):     return .slider(9)
        // Three rows of assignable buttons (8 each).
        case (1...8, 80): return .buttonA(Int(channel))
        case (1...8, 81): return .buttonB(Int(channel))
        case (1...8, 82): return .buttonC(Int(channel))
        default:
            return .unknown(channel: channel, cc: cc)
        }
    }
}
