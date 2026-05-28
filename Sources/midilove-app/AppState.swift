import Foundation
import SwiftUI
import MidiloveCore

@MainActor
final class AppState: ObservableObject {
    @Published var status: String = "Not started"
    @Published var connectedSources: [String] = []
    @Published var activeNotes: Set<UInt8> = []
    @Published var lastVelocity: UInt8 = 0
    @Published var controlValues: [ControlID: UInt8] = [:]
    @Published var pitchBend: Int = 0
    @Published var unknownCCs: [String] = [] // for debugging stragglers

    private var midi: MIDIEngine?
    private let audio = AudioEngine()

    func start() {
        // Find the SoundFont — try the app-bundled resources first, then the
        // working-directory `Sounds/` folder for `swift run` development.
        guard let soundFontURL = locateSoundFont() else {
            status = "❌ GrandPiano.sf2 missing — run Scripts/fetch-sounds.sh"
            return
        }
        do {
            try audio.loadSoundFont(at: soundFontURL)
            try audio.start()
        } catch {
            status = "Audio engine failed: \(error.localizedDescription)"
            return
        }

        let engine = MIDIEngine(
            handler: { [weak self] event in
                Task { @MainActor in self?.apply(event) }
            },
            sourcesHandler: { [weak self] sources in
                Task { @MainActor in self?.updateSources(sources) }
            }
        )
        do {
            try engine.start()
            midi = engine
        } catch {
            status = "MIDI engine failed: \(error)"
        }
    }

    private func updateSources(_ sources: [String]) {
        connectedSources = sources
        status = sources.isEmpty
            ? "No MIDI source — power on the PCR-500"
            : "Listening on: \(sources.joined(separator: ", "))"
    }

    /// Synthesize a sustain-pedal event from a keyboard shortcut so the
    /// spacebar can stand in for the real pedal while it's misbehaving.
    func simulateSustain(down: Bool) {
        let value: UInt8 = down ? 127 : 0
        apply(.controlChange(channel: 16, cc: 64, value: value, control: .sustainPedal))
    }

    private func apply(_ event: MIDIEvent) {
        audio.handle(event)
        switch event {
        case .noteOn(_, let note, let velocity):
            activeNotes.insert(note)
            lastVelocity = velocity
        case .noteOff(_, let note):
            activeNotes.remove(note)
        case .controlChange(_, _, let value, let control):
            controlValues[control] = value
            if case .unknown(let ch, let cc) = control {
                let tag = "ch\(ch)·CC\(cc)"
                if !unknownCCs.contains(tag) {
                    unknownCCs.append(tag)
                }
            }
        case .pitchBend(_, let value):
            pitchBend = value
        default:
            break
        }
    }

    private func locateSoundFont() -> URL? {
        let cwd = FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: cwd).appendingPathComponent("Sounds/GrandPiano.sf2")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
