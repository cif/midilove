import SwiftUI
import MidiloveCore

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusBar
            Divider()
            HStack(alignment: .top, spacing: 24) {
                notesPanel
                Divider()
                wheelsPanel
            }
            Divider()
            controlsGrid
            Spacer()
            if !state.unknownCCs.isEmpty {
                Text("Unmapped controls: \(state.unknownCCs.joined(separator: ", "))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(state.connectedSources.isEmpty ? .orange : .green)
                .frame(width: 10, height: 10)
            Text(state.status).font(.system(.body, design: .monospaced))
        }
    }

    private var notesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active notes").font(.headline)
            if state.activeNotes.isEmpty {
                Text("—").foregroundStyle(.secondary)
            } else {
                Text(state.activeNotes.sorted().map(Self.noteName).joined(separator: " "))
                    .font(.system(.title3, design: .monospaced))
            }
            Text("Last velocity: \(state.lastVelocity)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var wheelsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wheels & pedal").font(.headline)
            wheel("Pitch", value: Double(state.pitchBend) / 8192.0, range: -1...1)
            wheel("Mod (CC11)",
                  value: Double(state.controlValues[.modWheel] ?? 0) / 127.0,
                  range: 0...1)
            HStack {
                Text("Sustain (or hold Space)")
                Circle()
                    .fill((state.controlValues[.sustainPedal] ?? 0) > 63 ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 12, height: 12)
            }.font(.caption.monospaced())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func wheel(_ label: String, value: Double, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.monospaced())
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 6)
                let norm = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor)
                        .frame(width: max(2, geo.size.width * norm), height: 6)
                }.frame(height: 6)
            }
        }
    }

    private var controlsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("Knobs (R1–R9)", ids: (1...9).map(ControlID.knob))
            row("Sliders (S1–S9)", ids: (1...9).map(ControlID.slider))
            row("Buttons A", ids: (1...8).map(ControlID.buttonA), boolean: true)
            row("Buttons B", ids: (1...8).map(ControlID.buttonB), boolean: true)
            row("Buttons C", ids: (1...8).map(ControlID.buttonC), boolean: true)
        }
    }

    private func row(_ title: String, ids: [ControlID], boolean: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.monospaced()).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(ids, id: \.self) { id in
                    cell(id: id, boolean: boolean)
                }
            }
        }
    }

    private func cell(id: ControlID, boolean: Bool) -> some View {
        let value = state.controlValues[id] ?? 0
        let active = boolean ? value > 63 : value > 0
        return VStack(spacing: 2) {
            Text(id.description).font(.system(.caption2, design: .monospaced))
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                RoundedRectangle(cornerRadius: 4)
                    .fill(active ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(height: max(2, CGFloat(value) / 127.0 * 36))
            }
            .frame(width: 36, height: 36)
            Text("\(value)").font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
        }
    }

    private static let noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
    private static func noteName(_ n: UInt8) -> String {
        let octave = Int(n) / 12 - 1
        return "\(noteNames[Int(n) % 12])\(octave)"
    }
}
