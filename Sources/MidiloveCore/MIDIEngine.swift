import Foundation
import CoreMIDI

/// Receives MIDI from any CoreMIDI source whose name matches the PCR/Edirol/
/// Roland family, parses it into `MIDIEvent`s, and hands them to an event
/// handler. Also rescans whenever CoreMIDI's setup changes (devices plugged
/// in, powered on/off, etc.) so the connection survives a keyboard reboot.
public final class MIDIEngine: @unchecked Sendable {
    public typealias EventHandler = @Sendable (MIDIEvent) -> Void
    public typealias SourcesHandler = @Sendable ([String]) -> Void

    private var client: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private let handler: EventHandler
    private let sourcesHandler: SourcesHandler?
    private let queue = DispatchQueue(label: "midilove.engine")
    private var connectedSources: [String] = []

    public init(handler: @escaping EventHandler, sourcesHandler: SourcesHandler? = nil) {
        self.handler = handler
        self.sourcesHandler = sourcesHandler
    }

    public func start() throws {
        var status = MIDIClientCreateWithBlock("midilove" as CFString, &client) { [weak self] notification in
            self?.handleNotification(notification)
        }
        guard status == noErr else { throw MIDIError.clientCreate(status) }

        let h = handler
        status = MIDIInputPortCreateWithProtocol(
            client,
            "midilove-in" as CFString,
            ._1_0,
            &inputPort
        ) { eventListPtr, _ in
            Self.dispatch(eventListPtr: eventListPtr, to: h)
        }
        guard status == noErr else { throw MIDIError.portCreate(status) }

        queue.async { [weak self] in self?.rescanSources() }
    }

    private func handleNotification(_ notification: UnsafePointer<MIDINotification>) {
        // CoreMIDI calls this from an internal thread on any setup change.
        // Rescan unconditionally; the diff against our last snapshot decides
        // whether the UI needs updating.
        switch notification.pointee.messageID {
        case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved:
            queue.async { [weak self] in self?.rescanSources() }
        default:
            break
        }
    }

    private func rescanSources() {
        let count = MIDIGetNumberOfSources()
        var matched: [String] = []
        for i in 0..<count {
            let src = MIDIGetSource(i)
            let name = displayName(of: src)
            if isLikelyPCR(name) {
                // MIDIPortConnectSource is idempotent; safe to call on every
                // rescan whether or not we were already connected.
                MIDIPortConnectSource(inputPort, src, nil)
                matched.append(name)
            }
        }

        var sources = matched
        if matched.isEmpty && count > 0 {
            // No obvious match — fall back to listening to everything so
            // unusually-named devices still work.
            for i in 0..<count {
                let src = MIDIGetSource(i)
                MIDIPortConnectSource(inputPort, src, nil)
                sources.append(displayName(of: src) + " (fallback)")
            }
        }

        guard sources != connectedSources else { return }
        connectedSources = sources
        sourcesHandler?(sources)
    }

    private func isLikelyPCR(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("pcr") || lower.contains("edirol") || lower.contains("roland")
    }

    private func displayName(of obj: MIDIObjectRef) -> String {
        var ref: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(obj, kMIDIPropertyDisplayName, &ref)
        return (ref?.takeRetainedValue() as String?) ?? "<unknown>"
    }

    private static func dispatch(eventListPtr: UnsafePointer<MIDIEventList>, to handler: EventHandler) {
        let list = eventListPtr.pointee
        var packet = list.packet
        for _ in 0..<list.numPackets {
            let words = withUnsafeBytes(of: packet.words) { raw -> [UInt32] in
                let buf = raw.bindMemory(to: UInt32.self)
                return Array(buf.prefix(Int(packet.wordCount)))
            }
            for word in words {
                let mt = (word >> 28) & 0xF
                guard mt == 0x2 else { continue }
                let status = UInt8((word >> 16) & 0xFF)
                let d1 = UInt8((word >> 8) & 0x7F)
                let d2 = UInt8(word & 0x7F)
                if let event = decode(status: status, d1: d1, d2: d2) {
                    handler(event)
                }
            }
            packet = MIDIEventPacketNext(&packet).pointee
        }
    }

    private static func decode(status: UInt8, d1: UInt8, d2: UInt8) -> MIDIEvent? {
        let type = status & 0xF0
        let channel = (status & 0x0F) + 1
        switch type {
        case 0x80:
            return .noteOff(channel: channel, note: d1)
        case 0x90:
            return d2 == 0
                ? .noteOff(channel: channel, note: d1)
                : .noteOn(channel: channel, note: d1, velocity: d2)
        case 0xB0:
            let id = ControlMap.resolve(channel: channel, cc: d1)
            return .controlChange(channel: channel, cc: d1, value: d2, control: id)
        case 0xC0:
            return .programChange(channel: channel, program: d1)
        case 0xD0:
            return .aftertouch(channel: channel, pressure: d1)
        case 0xE0:
            let bend = (Int(d2) << 7) | Int(d1)
            return .pitchBend(channel: channel, value: bend - 8192)
        default:
            return nil
        }
    }
}

public enum MIDIError: Error {
    case clientCreate(OSStatus)
    case portCreate(OSStatus)
}
