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
    @Published var unknownCCs: [String] = []
    @Published var instruments: [Instrument] = []
    @Published var currentInstrumentIndex: Int = 0
    @Published var instrumentError: String? = nil

    private var midi: MIDIEngine?
    private let audio = AudioEngine()

    func start() {
        let rack = buildInstrumentRack()
        guard !rack.isEmpty else {
            status = "❌ No SoundFonts found — run Scripts/fetch-sounds.sh"
            return
        }
        instruments = rack
        do {
            try audio.load(rack[0])
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
            applyControl(control, value: value)
            if case .unknown(let ch, let cc) = control {
                let tag = "ch\(ch)·CC\(cc)"
                if !unknownCCs.contains(tag) { unknownCCs.append(tag) }
            }
        case .pitchBend(_, let value):
            pitchBend = value
        default:
            break
        }
    }

    /// Routes wired knobs/sliders to live audio parameters. Anything not
    /// mapped here just shows in the UI without affecting sound.
    private func applyControl(_ control: ControlID, value: UInt8) {
        let normalized = Float(value) / 127.0
        switch control {
        case .knob(1):
            audio.setFilterCutoff(normalized: normalized)
        case .knob(2):
            audio.setReverbMix(normalized: normalized)
        case .slider(9):
            audio.setMasterVolume(normalized: normalized)
        case .buttonA(let n) where value > 63:
            selectInstrument(slot: n - 1)
        default:
            break
        }
    }

    func selectInstrument(slot index: Int) {
        guard instruments.indices.contains(index) else { return }
        do {
            try audio.load(instruments[index])
            currentInstrumentIndex = index
            instrumentError = nil
        } catch {
            instrumentError = "Failed to load \(instruments[index].name): \(error.localizedDescription)"
        }
    }

    /// 8 default voices spanning piano, EP, organ, strings, pads, bass.
    /// Steinway takes slot 1 (our nicest piano); the rest come from the
    /// GeneralUser GM bank so we get variety without juggling 8 SoundFonts.
    private func buildInstrumentRack() -> [Instrument] {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let steinway = cwd.appendingPathComponent("Sounds/Steinway.sf2")
        let gm = cwd.appendingPathComponent("Sounds/GM.sf2")
        let fm = FileManager.default

        let steinwayExists = fm.fileExists(atPath: steinway.path)
        let gmExists = fm.fileExists(atPath: gm.path)

        var rack: [Instrument] = []
        if steinwayExists {
            rack.append(Instrument(name: "Steinway Grand", soundFontURL: steinway, program: 0))
        }
        if gmExists {
            rack.append(contentsOf: [
                Instrument(name: "Electric Piano",  soundFontURL: gm, program: 4),
                Instrument(name: "Drawbar Organ",   soundFontURL: gm, program: 16),
                Instrument(name: "Strings",         soundFontURL: gm, program: 48),
                Instrument(name: "Choir Aahs",      soundFontURL: gm, program: 52),
                Instrument(name: "Synth Pad",       soundFontURL: gm, program: 88),
                Instrument(name: "Synth Lead",      soundFontURL: gm, program: 81),
                Instrument(name: "Acoustic Bass",   soundFontURL: gm, program: 32),
            ])
        }
        return Array(rack.prefix(8))
    }

    private func locateSoundFont() -> URL? {
        let cwd = FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: cwd).appendingPathComponent("Sounds/Steinway.sf2")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
