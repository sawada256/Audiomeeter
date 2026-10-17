import Foundation
import Darwin
import VMNative

enum AudioConfigurationError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let s) = self { return s }; return nil } }
@main struct PluginWorkerTests {
    static func main() throws {
        let root = FileManager.default.currentDirectoryPath + "/.build/plugin-host/"
        let gain = try HostedInsert(config: InsertConfig(path: root+"VMTestGain_artefacts/Release/VST3/Audiomeeter Test Gain.vst3", name: "Gain", position: .pre), rate: 48000, block: 512)
        let side = try HostedInsert(config: InsertConfig(path: root+"VMTestSide_artefacts/Release/VST3/Audiomeeter Test Sidechain.vst3", name: "Side", position: .post), rate: 48000, block: 512)
        for slot in [gain,side] {
            let deadline = Date().addingTimeInterval(15)
            while slot.status == "読込中…" && Date() < deadline { usleep(20000); slot.refresh() }
            precondition(slot.status.isEmpty, slot.status)
        }
        precondition(side.sidechainChannels == 2 && side.latency == 549 && gain.latency == 512)
        let a = UnsafeMutablePointer<Float>.allocate(capacity: 1024), b = UnsafeMutablePointer<Float>.allocate(capacity: 1024)
        let sc = UnsafeMutablePointer<Float>.allocate(capacity: 1024)
        defer { a.deallocate();b.deallocate();sc.deallocate() }
        let compensate = StereoDelayLine()
        var gainImpulse = -1, sideImpulse = -1
        for block in 0..<12 {
            a.update(repeating: 0, count: 1024);b.update(repeating: 0, count: 1024);sc.update(repeating: 0,count:1024)
            if block == 0 { a[0] = 1; b[0] = 1; sc[0] = 1 }
            gain.process(a, sidechain: nil, upstreamLatency: 0, frames: 512)
            side.process(b, sidechain: sc, upstreamLatency: 0, frames: 512)
            compensate.process(a, frames: 512, delay: side.latency-gain.latency)
            for i in 0..<512 {
                if abs(a[i*2] - 0.5) < 0.0001 { gainImpulse = block*512+i }
                if abs(b[i*2] - 0.75) < 0.0001 { sideImpulse = block*512+i }
            }
            usleep(11000)
        }
        precondition(gainImpulse == 549 && sideImpulse == gainImpulse,"PDC impulses \(gainImpulse), \(sideImpulse)")
        fflush(stdout); print("Required sidechain, assigned audio, 37-sample latency + 512 IPC, and PDC impulse alignment passed")
        // Bypass while running: the mixer stops calling process (markIdle). On resume the
        // worker's last completed block (rendered before the pause) must not be replayed.
        for _ in 0..<4 { a.update(repeating: 1, count: 1024); gain.process(a, sidechain: nil, upstreamLatency: 0, frames: 512); usleep(11000) }
        precondition(abs(a[0] - 0.5) < 0.0001)
        gain.markIdle(); usleep(30000)
        a.update(repeating: 0, count: 1024); gain.process(a, sidechain: nil, upstreamLatency: 0, frames: 512)
        precondition(UnsafeBufferPointer(start: a, count: 1024).allSatisfy { $0 == 0 }, "Resumed insert replayed a stale pre-bypass block")
        for _ in 0..<4 { usleep(11000); a.update(repeating: 1, count: 1024); gain.process(a, sidechain: nil, upstreamLatency: 0, frames: 512) }
        precondition(abs(a[0] - 0.5) < 0.0001 && gain.status.isEmpty, "Worker must resume processing after resync")
        fflush(stdout); print("Bypass resume drops the stale wet block and resynchronizes the worker")
        // Soft (latency-preserving) bypass: the worker keeps running, PDC is unchanged and the
        // output is the dry signal (the plugin's own bypass, or latency-matched dry).
        func settle(_ value: Float, blocks: Int = 4) -> Float {
            for _ in 0..<blocks { usleep(11000); a.update(repeating: value, count: 1024); gain.process(a, sidechain: nil, upstreamLatency: 0, frames: 512) }
            return a[0]
        }
        let activeLatency = gain.latency
        gain.setBypass(.latency)
        precondition(!gain.fullyBypassed && gain.latency == activeLatency, "Soft bypass keeps the slot in the path and its latency")
        precondition(abs(settle(1) - 1) < 0.0001, "Soft bypass passes the dry signal")
        gain.setBypass(nil)
        precondition(abs(settle(1) - 0.5) < 0.0001, "Leaving soft bypass restores processing")
        gain.setBypass(.full)
        precondition(gain.fullyBypassed && gain.config.isFullyBypassed)
        gain.setBypass(nil)
        // Parameters: listed from the worker and set from the host (MIDI learn path).
        gain.refresh()
        precondition(gain.parameters.contains { $0.name == "Gain" }, "Worker must publish its parameter list: \(gain.parameters)")
        let gainIndex = gain.parameters.first { $0.name == "Gain" }!.index
        gain.setParameter(gainIndex, 1)
        precondition(abs(settle(0.4) - 0.4) < 0.0001 && gain.parameterValue(gainIndex) == 1, "Host parameter changes reach the plugin")
        gain.setParameter(gainIndex, 0.5)
        precondition(abs(settle(0.4) - 0.2) < 0.0001)
        // MIDI input ring: pushes are drained by the render thread.
        gain.setMIDIInput(0)
        var accepted = 0
        for round in 0..<3 {
            for note in 0..<300 { MIDIPluginRouter.shared.forward(status: 0x90, data1: UInt8(note % 128), data2: 100); accepted += 1 }
            _ = settle(0.4, blocks: 2 + round)
        }
        precondition(!MIDIPluginRouter.shared.isEmpty && accepted == 900 && gain.status.isEmpty, "MIDI forwarding must not disturb the worker")
        gain.setMIDIInput(nil)
        precondition(MIDIPluginRouter.shared.isEmpty)
        fflush(stdout); print("Soft bypass keeps latency, parameters list/set, MIDI input ring")
        side.reset()
        for i in 0..<6 {
            b.update(repeating: i == 0 ? 1 : 0,count:1024)
            side.process(b,sidechain:nil,upstreamLatency:0,frames:512);usleep(11000)
            if i >= 2 { precondition(b[0] == (i == 2 ? 0.5 : 0)) }
        }
        fflush(stdout); print("Unassigned required sidechain receives silence and still loads")
        side.requestSnapshot()
        for _ in 0..<20 { if side.snapshotReady { break };usleep(10000) }
        precondition(side.snapshotReady)
        // The test plugin deliberately aborts in its processBlock.
        b.update(repeating: 2000,count:1024);side.process(b,sidechain:nil,upstreamLatency:0,frames:512);usleep(30000);side.refresh()
        for _ in 0..<100 {
            b.update(repeating: 0.2, count: 1024); side.process(b, sidechain: nil, upstreamLatency: 0, frames: 512)
            usleep(11000); side.refresh(); if !side.status.isEmpty { break }
        }
        precondition(!side.status.isEmpty,"Crash must be reported independently")
        var longest: Double = 0
        for _ in 0..<60 {
            b.update(repeating:0.2,count:1024);a.update(repeating:0.2,count:1024)
            let begin=Date();side.process(b,sidechain:nil,upstreamLatency:0,frames:512);longest=max(longest,Date().timeIntervalSince(begin))
            gain.process(a,sidechain:nil,upstreamLatency:0,frames:512);usleep(11000)
        }
        precondition(abs(b[0] - 0.2)<0.0001 && abs(a[0] - 0.1)<0.0001 && gain.status.isEmpty && longest < 0.02)
        fflush(stdout); print("Plugin abort leaves sibling alive; latency-matched dry fallback; callback max \(longest*1000) ms")
        side.retry()
        for _ in 0..<100 { side.refresh();if side.status.isEmpty {break};usleep(20000) }
        precondition(side.status.isEmpty)
        b.update(repeating:-2000,count:1024);side.process(b,sidechain:nil,upstreamLatency:0,frames:512)
        for _ in 0..<35 { b.update(repeating:0.3,count:1024);side.process(b,sidechain:nil,upstreamLatency:0,frames:512);usleep(11000) }
        side.refresh();precondition(!side.status.isEmpty)
        precondition(abs(b[0] - 0.3)<0.0001)
        fflush(stdout); print("Hung process automatically quarantined with dry fallback; parent never waits")
    }
}
