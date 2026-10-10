import Foundation
import Darwin
import VMNative

enum AudioConfigurationError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let s) = self { return s }; return nil } }
@main struct PluginWorkerTests {
    static func main() throws {
        let root = FileManager.default.currentDirectoryPath + "/.build/plugin-host/"
        let gain = try HostedInsert(config: InsertConfig(path: root+"VMTestGain_artefacts/Release/VST3/Voicemeeter Test Gain.vst3", name: "Gain", position: .pre), rate: 48000, block: 512)
        let side = try HostedInsert(config: InsertConfig(path: root+"VMTestSide_artefacts/Release/VST3/Voicemeeter Test Sidechain.vst3", name: "Side", position: .post), rate: 48000, block: 512)
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
