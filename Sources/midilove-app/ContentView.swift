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
                instrumentPanel
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

    private var instrumentPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Instrument").font(.headline)
            if let current = state.instruments[safe: state.currentInstrumentIndex] {
                Text(current.name)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.tint)
            }
            if let err = state.instrumentError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            Text("Press A1–A\(state.instruments.count) to switch")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            modWheelRow
            HStack {
                Text("Sustain (or hold Space)")
                Circle()
                    .fill((state.controlValues[.sustainPedal] ?? 0) > 63 ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 12, height: 12)
            }.font(.caption.monospaced())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Mod wheel row with an LFO pulse indicator that breathes at the same
    /// 0.6 Hz rate the audio engine modulates the filter cutoff. The pulse
    /// is dim and still when mod depth is 0, bright and dramatic at 1.
    private var modWheelRow: some View {
        let depth = Double(state.controlValues[.modWheel] ?? 0) / 127.0
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("Mod → filter LFO").font(.caption.monospaced())
                lfoPulse(depth: depth)
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 6)
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor)
                        .frame(width: max(2, geo.size.width * depth), height: 6)
                }.frame(height: 6)
            }
        }
    }

    @ViewBuilder
    private func lfoPulse(depth: Double) -> some View {
        if depth > 0 {
            TimelineView(.animation(minimumInterval: 1.0/30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = sin(t * 0.6 * 2 * .pi) // matches AudioEngine.lfoRateHz
                let pulse = 0.5 + 0.5 * phase      // 0…1
                let size = 8 + CGFloat(pulse) * CGFloat(depth) * 12
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: size, height: size)
                    .opacity(0.5 + 0.5 * depth * pulse)
                    .shadow(color: .accentColor.opacity(depth * 0.6),
                            radius: CGFloat(pulse) * 6 * CGFloat(depth))
            }
            .frame(width: 22, height: 22)
        } else {
            Circle()
                .fill(Color.gray.opacity(0.25))
                .frame(width: 8, height: 8)
        }
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
            hSliderRow
            instrumentButtonRow
            row("Buttons B", ids: (1...8).map(ControlID.buttonB), boolean: true)
            row("Buttons C", ids: (1...8).map(ControlID.buttonC), boolean: true)
        }
    }

    /// Horizontal H1/H2 bar — drawn full width with a marker, since unlike
    /// the vertical sliders it's actually horizontal on the hardware.
    private var hSliderRow: some View {
        let value = state.controlValues[.hSlider] ?? 64
        let norm = Double(value) / 127.0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("H-Bar (pan)").font(.caption.monospaced()).foregroundStyle(.secondary)
                Text(value < 60 ? "← L" : value > 67 ? "R →" : "·")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tint)
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 18)
                // Center tick.
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.gray.opacity(0.35))
                        .frame(width: 1, height: 18)
                        .position(x: geo.size.width / 2, y: 9)
                }.frame(height: 18)
                // Position marker.
                GeometryReader { geo in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 14, height: 14)
                        .position(x: max(7, min(geo.size.width - 7, geo.size.width * norm)), y: 9)
                }.frame(height: 18)
            }
        }
    }

    private var instrumentButtonRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Buttons A — instrument select")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(1...8, id: \.self) { i in
                    instrumentCell(slot: i)
                }
            }
        }
    }

    private func instrumentCell(slot: Int) -> some View {
        let index = slot - 1
        let isLoaded = state.instruments.indices.contains(index)
        let isActive = isLoaded && index == state.currentInstrumentIndex
        let name = isLoaded ? state.instruments[index].name : "—"
        return VStack(spacing: 2) {
            Text("A\(slot)").font(.system(.caption2, design: .monospaced))
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? Color.accentColor : Color.gray.opacity(0.15))
                Text(name)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(isActive ? Color.white : Color.primary)
                    .multilineTextAlignment(.center)
                    .padding(2)
                    .lineLimit(2)
            }
            .frame(width: 80, height: 44)
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
        let label = Self.wiredLabel(for: id)
        let isWired = label != nil
        return VStack(spacing: 2) {
            Text(id.description).font(.system(.caption2, design: .monospaced))
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                RoundedRectangle(cornerRadius: 4)
                    .fill(active ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(height: max(2, CGFloat(value) / 127.0 * 36))
                if isWired {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.accentColor, lineWidth: 1)
                }
            }
            .frame(width: 36, height: 36)
            Text(label ?? "\(value)")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(isWired ? Color.accentColor : Color.secondary)
        }
    }

    /// Friendly label for any control we've actually wired to an audio
    /// parameter. Returning nil means "just show the raw value."
    private static func wiredLabel(for id: ControlID) -> String? {
        switch id {
        case .knob(1):   return "cutoff"
        case .knob(2):   return "reverb"
        case .knob(3):   return "delay"
        case .knob(4):   return "feedback"
        case .slider(9): return "volume"
        case .hSlider:   return "pan"
        default:         return nil
        }
    }

    private static let noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
    private static func noteName(_ n: UInt8) -> String {
        let octave = Int(n) / 12 - 1
        return "\(noteNames[Int(n) % 12])\(octave)"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
