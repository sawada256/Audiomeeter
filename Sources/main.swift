import AppKit
import SwiftUI
import VMNative

final class MixerHostingView: NSHostingView<MainView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    private var desktopControls: DesktopControlsCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshLanguage), name: .audiomeeterLanguageChanged, object: nil)

        let contentView = MainView()
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1260, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Audiomeeter for Mac (ARM64)"
        window.minSize = NSSize(width: 1060, height: 640)
        window.contentView = MixerHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        if !ProcessInfo.processInfo.arguments.contains("--ui-preview") && Bundle.main.bundleIdentifier != "local.audiomeeter.uipreview" { desktopControls = DesktopControlsCoordinator(state: AppState.shared) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        desktopControls?.stop()
        Task { @MainActor in
            await AppState.shared.recorderPlayer.finishRecording()
            await AppState.shared.snapshotPlugins()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        desktopControls?.stop()
        AppState.shared.shutdown()
    }

    @objc private func showLicenses() {
        guard let resource = Bundle.main.resourceURL else { return }
        NSWorkspace.shared.open(resource.appendingPathComponent("LICENSE.md"))
    }

    @objc private func refreshLanguage() { setupMainMenu() }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. Application Menu (About, Hide, Quit)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        appMenu.addItem(withTitle: L10n.text("About Audiomeeter"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let licenses = appMenu.addItem(withTitle: L10n.text("ライセンスとソースコードについて"), action: #selector(showLicenses), keyEquivalent: "")
        licenses.target = self
        appMenu.addItem(NSMenuItem.separator())

        let show = appMenu.addItem(withTitle: L10n.text("ミキサーを表示"), action: #selector(showMixer), keyEquivalent: "")
        show.target = self

        let hideItem = appMenu.addItem(withTitle: L10n.text("Hide Audiomeeter"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.keyEquivalentModifierMask = [.command]

        let hideOthersItem = appMenu.addItem(withTitle: L10n.text("Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]

        appMenu.addItem(withTitle: L10n.text("Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())

        let quitItem = appMenu.addItem(withTitle: L10n.text("Quit Audiomeeter"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Text fields (plugin search, etc.) receive ⌘X/⌘C/⌘V/⌘A only through Edit menu key equivalents.
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: L10n.text("Edit"))
        editMenu.addItem(withTitle: L10n.text("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: L10n.text("Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: L10n.text("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.text("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.text("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.text("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 2. Window Menu (Minimize, Zoom, Close)
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: L10n.text("Window"))

        let closeItem = windowMenu.addItem(withTitle: L10n.text("Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeItem.keyEquivalentModifierMask = [.command]

        let minimizeItem = windowMenu.addItem(withTitle: L10n.text("Minimize"), action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        minimizeItem.keyEquivalentModifierMask = [.command]

        windowMenu.addItem(withTitle: L10n.text("Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")

        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let p = AppState.shared.desktopControls
        return p.overlayMode == .off && !p.mediaKeysEnabled && p.hotkeys.isEmpty
    }
    @objc private func showMixer() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMixer(); return true }
}

// A separate scanner process isolates crashes and hangs from the running mixer.
if (CommandLine.arguments.count == 4 || CommandLine.arguments.count == 5) && CommandLine.arguments[1] == "--scan-vst3" {
    guard vm_host_load(CommandLine.arguments[2]) != 0 else { exit(2) }
    let data = Data(String(cString: vm_plugin_scan(CommandLine.arguments[3])).utf8)
    if CommandLine.arguments.count == 5 {
        do { try data.write(to: URL(fileURLWithPath: CommandLine.arguments[4]), options: .atomic) }
        catch { exit(3) }
    } else { FileHandle.standardOutput.write(data) }
    exit(0)
}
if CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "--scan-vst3-library" {
    Task { @MainActor in
        let catalog = PluginCatalog.shared
        catalog.scan()
        while catalog.scanning { try? await Task.sleep(nanoseconds: 100_000_000) }
        let report: [String: Any] = ["effects": catalog.entries.count, "errors": catalog.failures, "status": catalog.progress]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]) {
            FileHandle.standardOutput.write(data)
        }
        exit(0)
    }
    RunLoop.main.run()
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
