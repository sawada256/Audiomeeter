import SwiftUI

public struct EQWindowView: View {
    @ObservedObject var appState: AppState
    let bus: BusID
    let onClose: () -> Void

    @State private var selectedBandIndex: Int = 0

    private var config: MasterEQConfig {
        appState.buses[bus]?.eqConfig ?? MasterEQConfig()
    }

    private func hasPreset(_ slot: Int) -> Bool {
        guard let presets = appState.eqPresets[bus.rawValue], presets.indices.contains(slot) else { return false }
        return presets[slot] != nil
    }

    private let bandColors: [Color] = [
        Color(red: 0.95, green: 0.35, blue: 0.35), // Band 1 Red
        Color(red: 0.95, green: 0.65, blue: 0.20), // Band 2 Orange
        Color(red: 0.90, green: 0.85, blue: 0.25), // Band 3 Yellow
        Color(red: 0.35, green: 0.85, blue: 0.45), // Band 4 Green
        Color(red: 0.25, green: 0.75, blue: 0.95), // Band 5 Cyan
        Color(red: 0.75, green: 0.45, blue: 0.95)  // Band 6 Purple
    ]

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Circle()
                    .fill(config.isEnabled ? VMTheme.faderCyanLine : Color.gray)
                    .frame(width: 10, height: 10)
                    .shadow(color: config.isEnabled ? VMTheme.faderCyanLine : Color.clear, radius: 4)

                Text("MASTER 6-BAND EQUALIZER: \(bus.name) (\(bus.defaultLabel))")
                    .font(VMTheme.fontTitle)
                    .foregroundColor(VMTheme.textPrimary)

                Spacer()

                // Master EQ On/Off
                Button(action: {
                    appState.toggleBusEQ(bus: bus)
                }) {
                    Text(config.isEnabled ? "EQ ACTIVE" : "BYPASS")
                        .font(VMTheme.fontSmallBold)
                        .foregroundColor(config.isEnabled ? Color.black : VMTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(config.isEnabled ? VMTheme.faderCyanLine : VMTheme.panelBorder)
                        .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())

                // Reset Flat
                Button(action: {
                    appState.resetBusEQ(bus: bus)
                }) {
                    Text("RESET FLAT")
                        .font(VMTheme.fontSmallBold)
                        .foregroundColor(VMTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(VMTheme.panelBorder.opacity(0.6))
                        .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())

                // Prominent Close Button
                Button(action: onClose) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("CLOSE")
                            .font(VMTheme.fontSmallBold)
                    }
                    .foregroundColor(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.75))
                    .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(VMTheme.panelBackgroundDark)

            Divider().background(VMTheme.panelBorder)

            HStack(spacing: 16) {
                Text("EQ PRESETS").font(VMTheme.fontSmallBold)
                ForEach(0..<3) { slot in
                    HStack(spacing: 4) {
                        Button("\(slot + 1) 呼出") { appState.loadEQPreset(bus: bus, slot: slot) }
                            .disabled(!hasPreset(slot))
                        Button("保存") { appState.saveEQPreset(bus: bus, slot: slot) }
                            .help("現在のEQをプリセット\(slot + 1)に保存・上書き")
                    }
                }
                Spacer()
            }
            .controlSize(.small).padding(.horizontal, 16).padding(.vertical, 8)

            // Frequency Response Graph (Logarithmic 20Hz - 20kHz, -18dB - +18dB)
            GeometryReader { geo in
                ZStack {
                    // Background & Grid
                    Rectangle()
                        .fill(Color(red: 0.07, green: 0.08, blue: 0.11))

                    // Grid Lines (dB)
                    ForEach([-12, -6, 0, 6, 12], id: \.self) { db in
                        let y = dbToY(Float(db), height: geo.size.height)
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(db == 0 ? Color.white.opacity(0.4) : Color.white.opacity(0.08), lineWidth: db == 0 ? 1.2 : 0.5)

                        Text("\(db > 0 ? "+" : "")\(db) dB")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Color.gray.opacity(0.8))
                            .position(x: 28, y: y - 7)
                    }

                    // Grid Lines (Frequency)
                    ForEach([30, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000], id: \.self) { freq in
                        let x = freqToX(Float(freq), width: geo.size.width)
                        Path { path in
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: geo.size.height))
                        }
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)

                        Text(freq >= 1000 ? "\(freq / 1000)k" : "\(freq)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Color.gray.opacity(0.8))
                            .position(x: x + 12, y: geo.size.height - 10)
                    }

                    // Fill under curve
                    Path { path in
                        let steps = 200
                        let zeroY = dbToY(0, height: geo.size.height)
                        path.move(to: CGPoint(x: 0, y: zeroY))
                        for i in 0...steps {
                            let normX = Float(i) / Float(steps)
                            let freq = xToFreq(CGFloat(normX) * geo.size.width, width: geo.size.width)
                            let responseDB = ParametricEQ6Band.combinedResponseDB(config: config, freq: freq)
                            let y = dbToY(responseDB, height: geo.size.height)
                            path.addLine(to: CGPoint(x: CGFloat(normX) * geo.size.width, y: y))
                        }
                        path.addLine(to: CGPoint(x: geo.size.width, y: zeroY))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [config.isEnabled ? VMTheme.faderCyanLine.opacity(0.3) : Color.gray.opacity(0.15), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Combined EQ Response Stroke Curve
                    Path { path in
                        let steps = 200
                        for i in 0...steps {
                            let normX = Float(i) / Float(steps)
                            let freq = xToFreq(CGFloat(normX) * geo.size.width, width: geo.size.width)
                            let responseDB = ParametricEQ6Band.combinedResponseDB(config: config, freq: freq)
                            let y = dbToY(responseDB, height: geo.size.height)
                            let pt = CGPoint(x: CGFloat(normX) * geo.size.width, y: y)

                            if i == 0 {
                                path.move(to: pt)
                            } else {
                                path.addLine(to: pt)
                            }
                        }
                    }
                    .stroke(
                        config.isEnabled ? VMTheme.faderCyanLine : Color.gray.opacity(0.7),
                        lineWidth: 2.5
                    )
                    .shadow(color: config.isEnabled ? VMTheme.faderCyanLine.opacity(0.7) : Color.clear, radius: 4)

                    // Draggable Control Points for each of the 6 bands
                    ForEach(0..<min(6, config.bands.count), id: \.self) { idx in
                        let band = config.bands[idx]
                        let ptX = freqToX(band.freqHz, width: geo.size.width)
                        let ptY = dbToY(band.gainDB, height: geo.size.height)
                        let isSelected = selectedBandIndex == idx

                        ZStack {
                            Circle()
                                .fill(bandColors[idx].opacity(band.isEnabled ? 1.0 : 0.4))
                                .frame(width: isSelected ? 20 : 16, height: isSelected ? 20 : 16)
                                .overlay(
                                    Circle().stroke(Color.white, lineWidth: isSelected ? 2.5 : 1.2)
                                )
                                .shadow(color: bandColors[idx], radius: isSelected ? 8 : 3)

                            Text("\(idx + 1)")
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(.black)
                        }
                        .position(x: ptX, y: ptY)
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { val in
                                    selectedBandIndex = idx
                                    let newFreq = xToFreq(val.location.x, width: geo.size.width)
                                    let newGain = yToDB(val.location.y, height: geo.size.height)
                                    appState.setBusEQBand(bus: bus, bandIndex: idx, freqHz: newFreq, gainDB: newGain)
                                }
                        )
                        .onTapGesture {
                            selectedBandIndex = idx
                        }
                    }
                }
            }
            .frame(height: 200)

            Divider().background(VMTheme.panelBorder)

            // 6-Band Detailed Controls Strip
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 8) {
                    ForEach(0..<min(6, config.bands.count), id: \.self) { idx in
                        let band = config.bands[idx]
                        bandCard(band: band, index: idx)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(VMTheme.panelBackgroundDark)

            Divider().background(VMTheme.panelBorder)

            // Bottom Status / Help Bar
            HStack {
                Text("• Drag markers 1-6 directly on graph to tune Frequency & Gain. Double click any knob to reset.")
                    .font(.system(size: 10))
                    .foregroundColor(VMTheme.textSecondary)

                Spacer()

                Button(action: onClose) {
                    Text("Done")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                        .background(VMTheme.btnA)
                        .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(VMTheme.panelBackgroundDark)
        }
        .frame(minWidth: 800, maxWidth: 840, minHeight: 600, maxHeight: 640)
        .background(VMTheme.backgroundDark)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(VMTheme.panelBorder, lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.85), radius: 16)
    }

    // Individual Band Card
    @ViewBuilder
    private func bandCard(band: EQBandConfig, index: Int) -> some View {
        let isSelected = selectedBandIndex == index

        VStack(spacing: 4) {
            // Band Header
            HStack {
                Circle()
                    .fill(bandColors[index])
                    .frame(width: 8, height: 8)

                Text("BAND \(index + 1)")
                    .font(VMTheme.fontSmallBold)
                    .foregroundColor(bandColors[index])

                Spacer()

                // On/Off Toggle
                Button(action: {
                    appState.setBusEQBand(bus: bus, bandIndex: index, isEnabled: !band.isEnabled)
                }) {
                    Text(band.isEnabled ? "ON" : "OFF")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(band.isEnabled ? Color.black : Color.gray)
                        .frame(width: 28, height: 15)
                        .background(band.isEnabled ? bandColors[index] : Color.black.opacity(0.4))
                        .cornerRadius(2)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Filter Type Selector
            Picker("", selection: Binding(
                get: { band.type },
                set: { newType in appState.setBusEQBand(bus: bus, bandIndex: index, type: newType) }
            )) {
                ForEach(FilterType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .labelsHidden()
            .pickerStyle(MenuPickerStyle())
            .frame(width: 112)

            // Frequency Knob (Logarithmic!)
            RotaryKnobView(
                title: "FREQ",
                value: Binding(
                    get: { band.freqHz },
                    set: { appState.setBusEQBand(bus: bus, bandIndex: index, freqHz: $0) }
                ),
                range: 20.0...20000.0,
                defaultValue: defaultFreqForBand(index),
                unit: "Hz",
                isLogarithmic: true
            )

            // Gain Knob
            RotaryKnobView(
                title: "GAIN",
                value: Binding(
                    get: { band.gainDB },
                    set: { appState.setBusEQBand(bus: bus, bandIndex: index, gainDB: $0) }
                ),
                range: -15.0...15.0,
                defaultValue: 0.0,
                unit: "dB",
                isDB: true
            )

            // Q Factor Knob (Fully visible and accessible!)
            RotaryKnobView(
                title: "Q",
                value: Binding(
                    get: { band.q },
                    set: { appState.setBusEQBand(bus: bus, bandIndex: index, q: $0) }
                ),
                range: 0.1...10.0,
                defaultValue: (index == 0 || index == 5) ? 0.707 : 1.0,
                unit: ""
            )
        }
        .padding(8)
        .frame(width: 120, height: 260)
        .background(isSelected ? VMTheme.panelBackground.opacity(0.9) : VMTheme.panelBackground.opacity(0.4))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? bandColors[index] : VMTheme.panelBorder, lineWidth: isSelected ? 1.5 : 0.8)
        )
        .onTapGesture {
            selectedBandIndex = index
        }
    }

    private func defaultFreqForBand(_ idx: Int) -> Float {
        switch idx {
        case 0: return 80.0
        case 1: return 250.0
        case 2: return 800.0
        case 3: return 2500.0
        case 4: return 7500.0
        default: return 12000.0
        }
    }

    // Logarithmic Coordinate conversions (20 Hz - 20 kHz)
    private func freqToX(_ freq: Float, width: CGFloat) -> CGFloat {
        let minF: Float = 20.0
        let maxF: Float = 20000.0
        let logMin = log10f(minF)
        let logMax = log10f(maxF)
        let clamped = max(minF, min(maxF, freq))
        let norm = (log10f(clamped) - logMin) / (logMax - logMin)
        return CGFloat(norm) * width
    }

    private func xToFreq(_ x: CGFloat, width: CGFloat) -> Float {
        let minF: Float = 20.0
        let maxF: Float = 20000.0
        let logMin = log10f(minF)
        let logMax = log10f(maxF)
        let norm = max(0.0, min(1.0, Float(x / width)))
        let logF = logMin + norm * (logMax - logMin)
        let rawVal = powf(10.0, logF)
        if rawVal < 100 {
            return round(rawVal * 10.0) / 10.0
        } else if rawVal < 1000 {
            return round(rawVal)
        } else {
            return round(rawVal / 10.0) * 10.0
        }
    }

    private func dbToY(_ db: Float, height: CGFloat) -> CGFloat {
        let minDB: Float = -18.0
        let maxDB: Float = 18.0
        let clamped = max(minDB, min(maxDB, db))
        let norm = (clamped - minDB) / (maxDB - minDB)
        return CGFloat(1.0 - norm) * height
    }

    private func yToDB(_ y: CGFloat, height: CGFloat) -> Float {
        let minDB: Float = -18.0
        let maxDB: Float = 18.0
        let norm = Float(1.0 - (y / height))
        let db = minDB + norm * (maxDB - minDB)
        return round(max(minDB, min(maxDB, db)) * 10.0) / 10.0
    }
}
