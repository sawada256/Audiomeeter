import Foundation
import CoreMIDI

/// Receives controller input from every MIDI source. CoreMIDI delivers on its own
/// high-priority thread; events are batched and drained once per main-queue turn,
/// so a fast knob sweep produces one UI update per batch instead of one per message.
final class MIDIInputManager {
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var connected: [MIDIEndpointRef] = []
    private let lock = NSLock()
    private var pending: [MIDIEvent] = []
    private var drainScheduled = false
    /// Called on the main queue with events in arrival order.
    var onEvents: (([MIDIEvent]) -> Void)?
    /// Called on the main queue when the set of sources changes.
    var onSourcesChanged: (([String]) -> Void)?
    private(set) var lastError: OSStatus = noErr

    func start() {
        guard client == 0 else { return }
        var status = MIDIClientCreateWithBlock("Audiomeeter" as CFString, &client) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged {
                DispatchQueue.main.async { self?.connectSources() }
            }
        }
        guard status == noErr else { lastError = status; client = 0; return }
        status = MIDIInputPortCreateWithProtocol(client, "Audiomeeter Control" as CFString, ._1_0, &port) { [weak self] list, _ in
            self?.receive(list)
        }
        guard status == noErr else { lastError = status; MIDIClientDispose(client); client = 0; port = 0; return }
        connectSources()
    }

    func stop() {
        guard client != 0 else { return }
        for source in connected { MIDIPortDisconnectSource(port, source) }
        connected.removeAll()
        MIDIPortDispose(port); MIDIClientDispose(client)
        port = 0; client = 0
    }

    private func connectSources() {
        guard port != 0 else { return }
        for source in connected { MIDIPortDisconnectSource(port, source) }
        connected.removeAll()
        var names: [String] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            guard source != 0, MIDIPortConnectSource(port, source, nil) == noErr else { continue }
            connected.append(source)
            var name: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name) == noErr, let name {
                names.append(name.takeRetainedValue() as String)
            }
        }
        onSourcesChanged?(names)
    }

    private func receive(_ list: UnsafePointer<MIDIEventList>) {
        var events: [MIDIEvent] = []
        for packet in list.unsafeSequence() {
            let count = Int(packet.pointee.wordCount)
            withUnsafeBytes(of: packet.pointee.words) { raw in
                let words = raw.bindMemory(to: UInt32.self)
                var index = 0
                while index < min(count, words.count) {
                    let word = words[index]
                    if word >> 28 == 2 {
                        // Plugins with MIDI input receive every channel-voice message, unbatched.
                        MIDIPluginRouter.shared.forward(status: UInt8((word >> 16) & 0xFF), data1: UInt8((word >> 8) & 0x7F), data2: UInt8(word & 0x7F))
                    }
                    if let event = MIDIEvent.decode(umpWord: word) { events.append(event) }
                    index += MIDIEvent.umpWordCount(words[index])
                }
            }
        }
        guard !events.isEmpty else { return }
        lock.lock()
        pending.append(contentsOf: events)
        let schedule = !drainScheduled
        drainScheduled = true
        lock.unlock()
        if schedule { DispatchQueue.main.async { [weak self] in self?.drain() } }
    }

    private func drain() {
        lock.lock()
        let events = pending
        pending.removeAll(keepingCapacity: true)
        drainScheduled = false
        lock.unlock()
        onEvents?(events)
    }
}

/// Live MIDI status for the settings screen only, so incoming messages never
/// invalidate the whole mixer through AppState.
final class MIDIMonitor: ObservableObject {
    @Published var sources: [String] = []
    @Published var lastMessage = ""
}
