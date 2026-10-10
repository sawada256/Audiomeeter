import SwiftUI
import AppKit

public struct TapeRecorderView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var recorderPlayer: AudioRecorderPlayer


    public init(appState: AppState) {
        self.appState = appState
        self.recorderPlayer = appState.recorderPlayer
    }

    public var body: some View {
        VStack(spacing: 6) {
            if let error = recorderPlayer.recordingError {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            // Header Bar
            HStack {
                Text(L10n.text("INTEGRATED RECORDER & PLAYER"))
                    .font(VMTheme.fontSection)
                    .foregroundColor(VMTheme.textPrimary)

                Spacer()

                Button {
                    if let url = recorderPlayer.currentRecordingURL, FileManager.default.fileExists(atPath: url.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else {
                        let folder = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first!.appendingPathComponent("AudiomeeterRecordings", isDirectory: true)
                        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(folder)
                    }
                } label: {
                    Label(L10n.text("録音をFinderで表示"), systemImage: "folder.badge.magnifyingglass")
                        .font(VMTheme.fontSmallBold)
                }.buttonStyle(.plain).foregroundColor(VMTheme.textSecondary)
                    .help(L10n.text("直近の録音をFinderで選択。録音がない場合は保存フォルダを開きます"))

                // File Open Button
                Button(action: openAudioFileDialog) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                        Text(L10n.text("LOAD FILE"))
                            .font(VMTheme.fontSmallBold)
                    }
                    .foregroundColor(VMTheme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(VMTheme.panelBackgroundDark)
                    .cornerRadius(3)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            // Cassette Tape Window & Transport
            HStack(spacing: 12) {
                // Cassette Deck Graphic
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(red: 0.12, green: 0.14, blue: 0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(VMTheme.panelBorder, lineWidth: 1)
                        )

                    // Tape Center Cutout
                    HStack(spacing: 30) {
                        // Left Reel
                        TapeReelView(isSpinning: recorderPlayer.isPlaying || recorderPlayer.isRecording)

                        // Center Window with Tape Counter
                        VStack(spacing: 2) {
                            Text(formatTime(recorderPlayer.isRecording ? recorderPlayer.recordedDuration : recorderPlayer.currentTime))
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundColor(recorderPlayer.isRecording ? Color.red : (recorderPlayer.isPlaying ? VMTheme.faderCyanLine : Color.gray))
                                .shadow(color: recorderPlayer.isRecording ? Color.red.opacity(0.8) : (recorderPlayer.isPlaying ? VMTheme.faderCyanLine.opacity(0.8) : Color.clear), radius: 4)

                            Text(recorderPlayer.isRecording ? L10n.text("● RECORDING") : (recorderPlayer.isPlaying ? L10n.text("▶ PLAYING") : (recorderPlayer.isPaused ? L10n.text("❚❚ PAUSED") : L10n.text("■ STOPPED"))))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(recorderPlayer.isRecording ? Color.red : (recorderPlayer.isPlaying ? VMTheme.faderCyanLine : Color.gray))
                        }
                        .frame(width: 100)

                        // Right Reel
                        TapeReelView(isSpinning: recorderPlayer.isPlaying || recorderPlayer.isRecording)
                    }
                }
                .frame(width: 250, height: 60)

                // Transport Buttons & Format Settings
                VStack(spacing: 6) {
                    // Transport Buttons Row
                    HStack(spacing: 6) {
                        // RECORD Button
                        Button(action: {
                            if recorderPlayer.isRecording {
                                Task { @MainActor in await recorderPlayer.finishRecording() }
                            } else {
                                _ = recorderPlayer.startRecording(sampleRate: appState.engineSampleRate)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(recorderPlayer.isRecording ? Color.white : Color.red)
                                    .frame(width: 8, height: 8)
                                Text(L10n.text("REC"))
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(recorderPlayer.isRecording ? Color.white : Color.red)
                            .frame(width: 52, height: 24)
                            .background(recorderPlayer.isRecording ? Color.red : Color.red.opacity(0.2))
                            .cornerRadius(3)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.red, lineWidth: 1))
                            .shadow(color: recorderPlayer.isRecording ? Color.red : Color.clear, radius: 4)
                        }
                        .buttonStyle(PlainButtonStyle())

                        // PLAY Button
                        Button(action: {
                            recorderPlayer.play()
                        }) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(recorderPlayer.isPlaying ? Color.black : VMTheme.accentGreen)
                                .frame(width: 32, height: 24)
                                .background(recorderPlayer.isPlaying ? VMTheme.accentGreen : VMTheme.panelBackgroundDark)
                                .cornerRadius(3)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(VMTheme.accentGreen.opacity(0.6), lineWidth: 1))
                        }
                        .buttonStyle(PlainButtonStyle())

                        // PAUSE Button
                        Button(action: {
                            recorderPlayer.pause()
                        }) {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(recorderPlayer.isPaused ? Color.black : VMTheme.vuYellow)
                                .frame(width: 32, height: 24)
                                .background(recorderPlayer.isPaused ? VMTheme.vuYellow : VMTheme.panelBackgroundDark)
                                .cornerRadius(3)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(VMTheme.vuYellow.opacity(0.6), lineWidth: 1))
                        }
                        .buttonStyle(PlainButtonStyle())

                        // STOP Button
                        Button(action: {
                            if recorderPlayer.isRecording {
                                Task { @MainActor in await recorderPlayer.finishRecording() }
                            }
                            recorderPlayer.stopPlayback()
                        }) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color.gray)
                                .frame(width: 32, height: 24)
                                .background(VMTheme.panelBackgroundDark)
                                .cornerRadius(3)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(VMTheme.panelBorder, lineWidth: 1))
                        }
                        .buttonStyle(PlainButtonStyle())

                        // LOOP Toggle
                        Button(action: {
                            recorderPlayer.isLooping.toggle()
                        }) {
                            Image(systemName: "repeat")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(recorderPlayer.isLooping ? Color.black : VMTheme.faderCyanLine)
                                .frame(width: 32, height: 24)
                                .background(recorderPlayer.isLooping ? VMTheme.faderCyanLine : VMTheme.panelBackgroundDark)
                                .cornerRadius(3)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(VMTheme.faderCyanLine.opacity(0.6), lineWidth: 1))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Recording Source & Format Pickers
                    HStack(spacing: 8) {
                        // Source
                        HStack(spacing: 4) {
                            Text("SRC:")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(VMTheme.textSecondary)

                            Picker("", selection: $recorderPlayer.recordingSource) {
                                ForEach(RecordingSource.allCases) { src in
                                    Text(L10n.text(src.displayName)).tag(src)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 190)
                        }

                        RecorderSourceMeter(meters: appState.meterStore, source: recorderPlayer.recordingSource)
                            .frame(width: 70, height: 12)
                            .accessibilityLabel(L10n.text("録音ソース {0} レベルメーター", [String(describing: recorderPlayer.recordingSource.displayName)]))
                            .help(L10n.text("選択中の録音ソースの入力レベル。録音前にも確認できます"))

                        // Format
                        HStack(spacing: 4) {
                            Text("FMT:")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(VMTheme.textSecondary)

                            Picker("", selection: $recorderPlayer.recordingFormat) {
                                ForEach(RecorderFormat.allCases) { fmt in
                                    Text(L10n.text(fmt.rawValue)).tag(fmt)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 155)
                        }
                    }
                }

                // Playback Routing Buttons (A1-A3, B1-B2)
                VStack(spacing: 4) {
                    Text(L10n.text("PLAY TO"))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(VMTheme.textSecondary)

                    HStack(spacing: 3) {
                        ForEach(BusID.allCases) { bus in
                            let isRouted = recorderPlayer.playbackRouting[bus] ?? false
                            Button(action: {
                                recorderPlayer.playbackRouting[bus] = !isRouted
                            }) {
                                Text(bus.name)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(isRouted ? Color.black : (bus.isPhysical ? VMTheme.btnA : VMTheme.btnB))
                                    .frame(width: 24, height: 22)
                                    .background(isRouted ? (bus.isPhysical ? VMTheme.btnA : VMTheme.btnB) : VMTheme.panelBackgroundDark)
                                    .cornerRadius(2)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(bus.isPhysical ? VMTheme.btnA.opacity(0.6) : VMTheme.btnB.opacity(0.6), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.3))
                .cornerRadius(4)
            }
            .padding(.horizontal, 10)

            // Scrubber Slider & Filename
            HStack(spacing: 8) {
                Text(L10n.text(recorderPlayer.currentFileName))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(VMTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 140, alignment: .leading)

                // Seek slider
                Slider(
                    value: Binding(
                        get: {
                            recorderPlayer.totalDuration > 0 ? recorderPlayer.currentTime / recorderPlayer.totalDuration : 0.0
                        },
                        set: { newProgress in
                            recorderPlayer.seek(progress: newProgress)
                        }
                    ),
                    in: 0.0...1.0
                )
                .accentColor(VMTheme.faderCyanLine)

                Text(formatTime(recorderPlayer.totalDuration))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(VMTheme.textSecondary)
                    .frame(width: 50, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
        }
        .disabled(recorderPlayer.isFinalizingRecording)
        .background(VMTheme.panelBackground)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(VMTheme.panelBorder, lineWidth: 1)
        )
    }

    private func openAudioFileDialog() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            _ = recorderPlayer.loadAudioFile(url: url)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSecs = Int(seconds)
        let m = totalSecs / 60
        let s = totalSecs % 60
        let ms = Int((seconds - Double(totalSecs)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, ms)
    }
}

private struct RecorderSourceMeter: View {
    @ObservedObject var meters: MixerMeterStore
    let source: RecordingSource
    private var target: InsertTarget {
        switch source {
        case .busA1: return .bus(.A1)
        case .busA2: return .bus(.A2)
        case .busA3: return .bus(.A3)
        case .busB1: return .bus(.B1)
        case .busB2: return .bus(.B2)
        case .strip1: return .strip(.hardware1)
        case .strip2: return .strip(.hardware2)
        case .strip3: return .strip(.hardware3)
        case .stripVAIO: return .strip(.virtualVAIO)
        case .stripAUX: return .strip(.virtualAUX)
        }
    }
    var body: some View { CompactStereoMeter(level: meters.level(target)) }
}

/// Animated Tape Reel
private struct TapeReelView: View {
    let isSpinning: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/15, paused: !isSpinning)) { time in
        let angle = isSpinning ? time.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) * 180 : 0
        ZStack {
            Circle()
                .fill(Color(red: 0.18, green: 0.20, blue: 0.24))
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))

            // 3-Spoke Reel Teeth
            ForEach(0..<3) { i in
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 4, height: 32)
                    .rotationEffect(.degrees(Double(i) * 60 + angle))
            }

            Circle()
                .fill(Color.black)
                .frame(width: 14, height: 14)
        }
        }
    }
}
