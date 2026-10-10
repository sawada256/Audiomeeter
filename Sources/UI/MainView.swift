import SwiftUI

/// Main Mixing Console View for Voicemeeter Banana
public struct MainView: View {
    @StateObject private var appState = AppState.shared
    @State private var showingSettings = false
    @State private var showingInfoSheet: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            topBarView

            // Integrated Cassette Recorder & Player Deck
            TapeRecorderView(appState: appState)
                .disabled(appState.isStartingAudio)
                .padding(.horizontal, 6)
                .padding(.top, 4)
                .padding(.bottom, 2)

            // Main Mixer Console
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                HStack(alignment: .top, spacing: 2) {
                    // Hardware Inputs 1, 2, 3
                    HStack(spacing: 2) {
                        HardwareStripView(stripID: .hardware1, appState: appState)
                        HardwareStripView(stripID: .hardware2, appState: appState)
                        HardwareStripView(stripID: .hardware3, appState: appState)
                    }

                    // Virtual Inputs (VAIO, AUX)
                    HStack(spacing: 2) {
                        VirtualStripView(stripID: .virtualVAIO, appState: appState)
                        VirtualStripView(stripID: .virtualAUX, appState: appState)
                    }

                    // Master Section (A1, A2, A3, B1, B2)
                    MasterSectionView(appState: appState)
                }
                .padding(6)
            }
            .background(VMTheme.consoleBg)
            .disabled(appState.isStartingAudio)

            // Bottom Status Bar
            bottomStatusBar
        }
        .frame(minWidth: 1040, minHeight: 620)
        .background(VMTheme.consoleBg)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings) { AudioSettingsView(appState: appState) }
        .alert("オーディオ", isPresented: Binding(get: { appState.audioError != nil }, set: { if !$0 { appState.audioError = nil } })) {
            Button("OK") { appState.audioError = nil }
        } message: { Text(appState.audioError ?? "") }
        .sheet(isPresented: $showingInfoSheet) {
            InfoSheetView()
        }
    }

    private var topBarView: some View {
        HStack(spacing: 12) {
            // Voicemeeter Banana Logo
            HStack(spacing: 6) {
                Text("VOICEMEETER")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundColor(VMTheme.textPrimary)
                Text("Banana")
                    .font(.system(size: 16, weight: .heavy, design: .serif))
                    .italic()
                    .foregroundColor(VMTheme.textGold)
                Text("for Mac")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(VMTheme.textAccent.opacity(0.2))
                    .foregroundColor(VMTheme.textAccent)
                    .cornerRadius(3)
            }

            Spacer()

            // Real-time Engine Status Badges
            HStack(spacing: 8) {
                // Engine Running LED
                HStack(spacing: 4) {
                    Circle()
                        .fill(appState.isEngineRunning ? VMTheme.ledAActive : VMTheme.ledMuteActive)
                        .frame(width: 8, height: 8)
                        .shadow(color: appState.isEngineRunning ? VMTheme.ledAActive : .clear, radius: 3)
                    Text(appState.isStartingAudio ? "ENGINE STARTING" : (appState.isEngineRunning ? "ENGINE LIVE" : "ENGINE STOPPED"))
                        .font(VMTheme.fontDigit)
                        .foregroundColor(appState.isEngineRunning ? VMTheme.ledAActive : VMTheme.ledMuteActive)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.4))
                .cornerRadius(3)

                // Master Sample Rate Badge
                Text(String(format: "%.0f Hz", appState.engineSampleRate))
                    .font(VMTheme.fontDigit)
                    .foregroundColor(VMTheme.textAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(3)

                // Buffer Size Badge
                Text(String(format: "%d samples (~%.1fms)", appState.engineBufferSize, (Double(appState.engineBufferSize) / appState.engineSampleRate) * 1000.0))
                    .font(VMTheme.fontDigit)
                    .foregroundColor(VMTheme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(3)
            }

            // Menu Dropdown
            Menu {
                Button("オーディオ設定…") { showingSettings = true }
                Divider()
                Button("Restart Audio Engine") {
                    appState.restartAudioEngine()
                }
                Button("Refresh Audio Devices") {
                    appState.rescanDevices()
                }
                Divider()
                Button("Setup & Routing Guide...") {
                    showingInfoSheet = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Menu")
                }
                .font(VMTheme.fontDigit)
                .foregroundColor(VMTheme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(VMTheme.stripBgTop)
                .cornerRadius(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(VMTheme.panelBorder, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .disabled(appState.isStartingAudio)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(VMTheme.grooveDark)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(VMTheme.panelBorder),
            alignment: .bottom
        )
    }

    private var bottomStatusBar: some View {
        HStack {
            Text("ARM64 • A1 Master Clock • Adaptive Clock Correction")
                .font(VMTheme.fontSmall)
                .foregroundColor(VMTheme.textSecondary)
            Spacer()
            Text("Voicemeeter Banana v1.2 Mac")
                .font(VMTheme.fontSmall)
                .foregroundColor(VMTheme.textSecondary.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(VMTheme.grooveDark)
    }
}

/// Help & Information Sheet View
public struct InfoSheetView: View {
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Voicemeeter Banana for Mac - セットアップと使用法")
                    .font(.headline)
                    .foregroundColor(VMTheme.textPrimary)
                Spacer()
                Button("閉じる") { dismiss() }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("1. 基本構成とルーティング")
                        .font(.subheadline).bold()
                        .foregroundColor(VMTheme.textGold)
                    Text("• 入力ストリップの「A1〜A3」を押すと、指定した物理出力（スピーカー/ヘッドホン）から音が出ます。\n• 入力ストリップの「B1」「B2」を押すと、仮想出力（OBSやDiscordへ送る音声）へルーティングされます。")
                        .font(.caption)

                    Text("2. 仮想入力（VAIO / AUX）のMac側設定")
                        .font(.subheadline).bold()
                        .foregroundColor(VMTheme.textGold)
                    Text("• システム音声（YouTubeやiTunes等）: Macの「システム設定」→「サウンド」→「出力」で「Voicemeeter」を選択し、ソフト上の「VOICEMEETER VAIO」の入力にVoicemeeterを割り当てます。\n• 通話音声（DiscordやZoom）: 通話アプリの出力先を「Voicemeeter AUX」に設定し、ソフト上の「VOICEMEETER AUX」で受信します。")
                        .font(.caption)

                    Text("3. 仮想出力（B1 / B2）でDiscordやOBSに声を届ける")
                        .font(.subheadline).bold()
                        .foregroundColor(VMTheme.textGold)
                    Text("• Master Sectionの「B1」の出力先を「Voicemeeter B1」に設定します。\n• DiscordやOBS側のマイク（入力）デバイスで同じ「Voicemeeter B1」を選択することで、マイク音声＋PC音声を自在にミックスした音を配信や通話に流せます。")
                        .font(.caption)

                    Text("4. 高度な最適化（クロックドリフト補正）")
                        .font(.subheadline).bold()
                        .foregroundColor(VMTheme.textGold)
                    Text("• Windows版Voicemeeterで頻発する「長時間使用時のロボット音・パチパチノイズ」は、適応型PIクロック補正で軽減します。安定性はデバイスやバッファ設定にも依存するため、実際の構成で確認してください。")
                        .font(.caption)
                }
                .foregroundColor(VMTheme.textPrimary)
            }
        }
        .padding(20)
        .frame(width: 580, height: 440)
        .background(VMTheme.consoleBg)
    }
}
