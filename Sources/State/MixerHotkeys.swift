import AppKit
import Carbon
import ApplicationServices
import CoreAudio

@MainActor final class MixerHotkeys {
    private let state: AppState
    var overlayHeld: ((Bool) -> Void)?
    var volumeHotkeyPerformed: (() -> Void)?
    private var registrations: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var actions: [UInt32: MixerHotkeyBinding] = [:]
    private var mediaCapture: MediaKeyCapture?
    private var mediaGeneration = UUID()
    private var suspended = false
    private var refreshTimer: Timer?
    private var registrationFailures: [String] = []
    init(state: AppState) {
        self.state = state
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key) == noErr else { return OSStatus(eventNotHandledErr) }
            guard key.signature == 0x564D484B else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                Unmanaged<MixerHotkeys>.fromOpaque(context).takeUnretainedValue().handle(key.id, down: GetEventKind(event) == UInt32(kEventHotKeyPressed))
                return noErr
            }
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.repairMediaCapture() }
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        // Queued watchdog/configuration tasks must not recreate a tap while quitting.
        suspended = true
        refreshTimer?.invalidate(); refreshTimer = nil
        unregister()
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
    private func unregister() {
        for ref in registrations { UnregisterEventHotKey(ref) }; registrations.removeAll(); actions.removeAll()
        mediaGeneration = UUID()
        mediaCapture?.stop(); mediaCapture = nil
        overlayHeld?(false)
    }
    func suspend() { suspended = true; unregister() }
    func resume() { suspended = false; configure() }
    func configure() {
        guard !suspended else { return }
        unregister()
        let settings = state.desktopControls
        var failures: [String] = [], occupied: Set<MixerShortcut> = []
        func register(_ shortcut: MixerShortcut, id: UInt32) {
            guard occupied.insert(shortcut).inserted else { failures.append(L10n.text("重複キー: {0}", [String(describing: shortcut.displayName)])); return }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x564D484B, id: id), GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { registrations.append(ref) }
            else { failures.append(L10n.text("登録できません: {0}（他の機能と競合）", [String(describing: shortcut.displayName)])) }
        }
        if settings.overlayMode == .held { register(settings.overlayShortcut, id: 1) }
        for (index, binding) in settings.hotkeys.enumerated() {
            if let shortcut = binding.shortcut {
                let id = UInt32(100 + index); actions[id] = binding; register(shortcut, id: id)
            }
        }
        registrationFailures = failures
        repairMediaCapture()
    }
    private func repairMediaCapture() {
        guard !suspended else { return }
        var failures = registrationFailures
        if state.desktopControls.mediaKeysEnabled {
            if mediaCapture == nil {
                let generation = mediaGeneration
                mediaCapture = MediaKeyCapture { [weak self] action in
                    DispatchQueue.main.async {
                        guard let self, self.mediaGeneration == generation, !self.suspended, self.state.desktopControls.mediaKeysEnabled else { return }
                        self.state.applyHotkey(target: self.state.desktopControls.mediaTarget, action: action)
                        self.volumeHotkeyPerformed?()
                    }
                }
            }
            switch mediaCapture?.status {
            case .ready: break
            case .starting: failures.append(L10n.text("音量キー: 捕捉を接続中"))
            default: failures.append(L10n.text("音量キー: macOSが捕捉を許可していません。許可登録を確認してください。自動で再試行します。"))
            }
        }
        let status = failures.isEmpty ? (state.desktopControls.mediaKeysEnabled ? L10n.text("ホットキー・音量キー捕捉: 有効") : L10n.text("ホットキー: 有効／音量キー置換: OFF")) : failures.joined(separator: "\n")
        if state.desktopControlsStatus != status { state.desktopControlsStatus = status }
    }
    private func handle(_ id: UInt32, down: Bool) {
        if id == 1 { overlayHeld?(down); return }
        guard down, let binding = actions[id] else { return }
        state.applyHotkey(target: binding.target, action: binding.action)
        volumeHotkeyPerformed?()
    }
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
}

/// Keep only Audiomeeter's public playback devices at unity, including OS mute.
/// Property listeners avoid polling every audio callback and never touch physical outputs.
@MainActor final class VirtualOutputVolumeGuard {
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var ids: [AudioObjectID] = []
    private var timer: Timer?
    func configure(enabled: Bool, devices: [AudioDeviceInfo]) {
        let next = enabled ? devices.filter { ["Audiomeeter_UID", "AudiomeeterAUX_UID", "Voicemeeter_UID", "VoicemeeterAUX_UID"].contains($0.uid) }.map(\.id) : []
        guard next != ids else { return }
        stop(); ids = next
        for id in next {
            for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
                for element: UInt32 in [0, 1, 2] {
                    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
                    guard AudioObjectHasProperty(id, &address) else { continue }
                    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in Task { @MainActor in self?.enforce() } }
                    if AudioObjectAddPropertyListenerBlock(id, &address, .main, block) == noErr { listeners.append((id, address, block)) }
                }
            }
        }
        enforce()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.enforce() } }
    }
    private func enforce() {
        for (id, savedAddress, _) in listeners {
            var address = savedAddress, size: UInt32 = 4, settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(id, &address, &settable) == noErr, settable.boolValue else { continue }
            if address.mSelector == kAudioDevicePropertyVolumeScalar {
                var value: Float32 = 1
                if AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, abs(value - 1) > 0.0001 {
                    value = 1; AudioObjectSetPropertyData(id, &address, 0, nil, size, &value)
                }
            } else {
                var value: UInt32 = 0
                if AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, value != 0 {
                    value = 0; AudioObjectSetPropertyData(id, &address, 0, nil, size, &value)
                }
            }
        }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        for (id, saved, block) in listeners { var address = saved; AudioObjectRemovePropertyListenerBlock(id, &address, .main, block) }
        listeners.removeAll(); ids.removeAll()
    }
}
