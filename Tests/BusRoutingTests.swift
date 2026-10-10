import Foundation
@main struct BusRoutingTests {
    static func main() throws {
        precondition(InternalBusRouting.source("VoicemeeterB1_UID") == .B1)
        precondition(InternalBusRouting.source("VoicemeeterB2_UID") == .B2)
        precondition(StereoPanControl.normalized(-0.000001) == 0)
        precondition(StereoPanControl.normalized(0.05) == 0)
        precondition(StereoPanControl.normalized(-0.05) == 0)
        precondition(StereoPanControl.label(-0.000001) == "C")
        precondition(StereoPanControl.label(-0.76) == "L76")
        precondition(StereoPanControl.normalized(5) == 1)
        var a = StripSettings(); a.deviceUID = "AudiomeeterB1_UID"; a.routing = RoutingMatrix(b1: true)
        precondition(InternalBusRouting.hasCycle([.hardware1:a]))
        a.routing = RoutingMatrix(b2:true)
        var b = StripSettings(); b.deviceUID = "AudiomeeterB2_UID"; b.routing = RoutingMatrix(b1:true)
        precondition(InternalBusRouting.hasCycle([.hardware1:a,.hardware2:b]))
        b.routing = RoutingMatrix(a1:true)
        precondition(!InternalBusRouting.hasCycle([.hardware1:a,.hardware2:b]))
        let returnBus: BusID = CommandLine.arguments.contains("--b2") ? .B2 : .B1
        let engine = AudiomeeterEngine()
        try engine.configureClock(rate:48000,frames:512)
        for strip in StripID.allCases { engine.updateStripSettings(strip:strip) { $0.routing = RoutingMatrix(); $0.dynamics = DynamicsConfig() } }
        engine.updateStripSettings(strip:.virtualVAIO) { $0.routing = RoutingMatrix(); $0.routing[returnBus] = true; $0.pan = 1 }
        engine.updateStripSettings(strip:.hardware1) { $0.deviceUID = returnBus == .B1 ? "VoicemeeterB1_UID" : "VoicemeeterB2_UID"; $0.routing = RoutingMatrix(a1:true) }
        let stereo = (0..<1024).map { $0 % 2 == 0 ? Float(0.1) : Float(0.2) }
        var previous = [Float](repeating:0,count:1024)
        for _ in 0..<8 {
            engine.feedOffline(.virtualVAIO,stereo)
            let buses = engine.renderOffline()
            precondition(zip(buses[.A1]!,previous).allSatisfy { abs($0-$1)<0.00001 },"Internal B1 must use exactly the previous completed block")
            previous = buses[returnBus]!
        }
        precondition(abs(previous[0])<0.00001 && abs(previous[1]-0.2)<0.00001,"Full right pan must retain right and silence left")
        var config = InsertConfig(path:FileManager.default.currentDirectoryPath+"/.build/plugin-host/VMTestSide_artefacts/Release/VST3/Audiomeeter Test Sidechain.vst3",name:"Side",position:.post)
        config.sidechainBus = returnBus
        let slot = try HostedInsert(config:config,rate:48000,block:512)
        for _ in 0..<500 { slot.refresh(); if slot.status.isEmpty { break }; usleep(20000) }
        precondition(slot.status.isEmpty,slot.status)
        engine.inserts[.bus(.A1)] = [slot]
        var final = [Float]()
        for _ in 0..<30 { engine.feedOffline(.virtualVAIO,stereo); final = engine.renderOffline()[.A1]!; usleep(11000) }
        precondition(abs(final[900])<0.0001 && abs(final[901]-0.15)<0.0001,"B1 sidechain must receive the rendered bus independently of bus order")
        engine.updateStripSettings(strip:.virtualVAIO) { $0.pan = 0 }
        for _ in 0..<12 { engine.feedOffline(.virtualVAIO,stereo); previous = engine.renderOffline()[returnBus]!; usleep(11000) }
        precondition(abs(previous[900]-0.1)<0.0001 && abs(previous[901]-0.2)<0.0001,"Center preserves stereo gain")
        print("Internal \(returnBus.name) previous-block return, direct/transitive cycle rejection, stereo PAN, and bus plugin sidechain passed")
    }
}
