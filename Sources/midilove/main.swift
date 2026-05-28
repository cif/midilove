import Foundation
import CoreMIDI

// ──────────────────────────────────────────────────────────────────────────
// midilove — phase 1: MIDI monitor
// Plug in the Edirol PCR-500, run `swift run`, then wiggle every knob,
// slider, pad, button, and wheel. We'll see exactly what your unit sends.
// ──────────────────────────────────────────────────────────────────────────

let noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
func noteName(_ n: UInt8) -> String {
    let octave = Int(n) / 12 - 1
    return "\(noteNames[Int(n) % 12])\(octave)"
}

// Track which CCs we've seen so we can print a running discovery table.
var seenCCs: [UInt8: (min: UInt8, max: UInt8, last: UInt8, count: Int)] = [:]
var seenNotes: Set<UInt8> = []
let startTime = Date()

func ts() -> String {
    String(format: "%7.3f", Date().timeIntervalSince(startTime))
}

func handle(_ status: UInt8, _ d1: UInt8, _ d2: UInt8) {
    let type = status & 0xF0
    let ch = (status & 0x0F) + 1
    switch type {
    case 0x90 where d2 > 0:
        seenNotes.insert(d1)
        print("[\(ts())] ch\(ch)  NOTE ON   \(noteName(d1)) (\(d1))  vel=\(d2)")
    case 0x80, 0x90:
        print("[\(ts())] ch\(ch)  NOTE OFF  \(noteName(d1)) (\(d1))")
    case 0xB0:
        let prev = seenCCs[d1]
        let newMin = min(prev?.min ?? d2, d2)
        let newMax = max(prev?.max ?? d2, d2)
        let count = (prev?.count ?? 0) + 1
        seenCCs[d1] = (newMin, newMax, d2, count)
        print("[\(ts())] ch\(ch)  CC \(String(format: "%3d", d1))     val=\(String(format: "%3d", d2))   (range so far: \(newMin)–\(newMax), hits: \(count))")
    case 0xE0:
        let bend = (Int(d2) << 7) | Int(d1)
        print("[\(ts())] ch\(ch)  PITCH BEND \(bend - 8192)")
    case 0xC0:
        print("[\(ts())] ch\(ch)  PROGRAM CHANGE \(d1)")
    case 0xD0:
        print("[\(ts())] ch\(ch)  AFTERTOUCH \(d1)")
    default:
        print("[\(ts())] ch\(ch)  raw: \(String(format: "%02X %02X %02X", status, d1, d2))")
    }
}

// CoreMIDI callback — parses packets and dispatches.
let readBlock: MIDIReceiveBlock = { eventListPtr, _ in
    let eventList = eventListPtr.pointee
    var packet = eventList.packet
    for _ in 0..<eventList.numPackets {
        let words = withUnsafeBytes(of: packet.words) { raw -> [UInt32] in
            let buf = raw.bindMemory(to: UInt32.self)
            return Array(buf.prefix(Int(packet.wordCount)))
        }
        for word in words {
            // UMP message type lives in the top nibble.
            let mt = (word >> 28) & 0xF
            if mt == 0x2 {
                // MIDI 1.0 channel voice message in UMP form.
                let status = UInt8((word >> 16) & 0xFF)
                let d1 = UInt8((word >> 8) & 0x7F)
                let d2 = UInt8(word & 0x7F)
                handle(status, d1, d2)
            }
        }
        packet = MIDIEventPacketNext(&packet).pointee
    }
}

var client = MIDIClientRef()
var status = MIDIClientCreateWithBlock("midilove" as CFString, &client) { _ in }
guard status == noErr else {
    print("MIDIClientCreate failed: \(status)"); exit(1)
}

var inputPort = MIDIPortRef()
status = MIDIInputPortCreateWithProtocol(
    client,
    "midilove-in" as CFString,
    ._1_0,
    &inputPort,
    readBlock
)
guard status == noErr else {
    print("MIDIInputPortCreate failed: \(status)"); exit(1)
}

// Discover sources and connect to anything that looks like a PCR / Edirol /
// Roland device. If we don't find one, connect to everything so the user
// still sees output and we can figure out the device name.
let sourceCount = MIDIGetNumberOfSources()
print("Found \(sourceCount) MIDI source(s):")
var connectedAny = false
for i in 0..<sourceCount {
    let src = MIDIGetSource(i)
    var nameRef: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(src, kMIDIPropertyDisplayName, &nameRef)
    let name = (nameRef?.takeRetainedValue() as String?) ?? "<unknown>"
    let lower = name.lowercased()
    let isLikely = lower.contains("pcr") || lower.contains("edirol") || lower.contains("roland")
    let marker = isLikely ? "  ← connecting" : ""
    print("  [\(i)] \(name)\(marker)")
    if isLikely {
        MIDIPortConnectSource(inputPort, src, nil)
        connectedAny = true
    }
}
if !connectedAny && sourceCount > 0 {
    print("No obvious PCR/Edirol/Roland source found — connecting to all sources so we can see what's there.")
    for i in 0..<sourceCount {
        MIDIPortConnectSource(inputPort, MIDIGetSource(i), nil)
    }
}
if sourceCount == 0 {
    print("⚠️  No MIDI sources detected. Plug in the PCR-500 (USB) and re-run.")
    print("    macOS sees it as a class-compliant device — no driver needed.")
}

print("")
print("Listening. Wiggle each control on the PCR-500 — knobs, sliders, pads,")
print("transport buttons, pitch/mod wheels. Press Ctrl-C when done. After")
print("you stop, send me the output and I'll build the control map.")
print("─────────────────────────────────────────────────────────────────────")

// Print a summary on Ctrl-C.
let sig = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
signal(SIGINT, SIG_IGN)
sig.setEventHandler {
    print("\n\n──────── Summary ────────")
    print("Notes seen: \(seenNotes.sorted().map { "\(noteName($0))(\($0))" }.joined(separator: ", "))")
    print("CCs seen (cc# → range, hits):")
    for cc in seenCCs.keys.sorted() {
        let info = seenCCs[cc]!
        print("  CC \(String(format: "%3d", cc))  range \(info.min)–\(info.max)  hits=\(info.count)  last=\(info.last)")
    }
    exit(0)
}
sig.resume()

RunLoop.main.run()
