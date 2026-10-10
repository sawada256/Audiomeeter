import Foundation
@main struct MixerLatencyTests {
    static func main() throws {
        let virtual = CommandLine.arguments.contains("--virtual")
        let first: StripID = virtual ? .virtualVAIO : .hardware1
        let second: StripID = virtual ? .virtualAUX : .hardware2
        let engine=VoicemeeterEngine()
        try engine.configureClock(rate:48000,frames:512)
        for strip in StripID.allCases {
            engine.updateStripSettings(strip:strip) { $0.routing=RoutingMatrix(a1: strip == first || strip == second,b1:strip == first || strip == second) }
        }
        let root=FileManager.default.currentDirectoryPath+"/.build/plugin-host/"
        let input=try HostedInsert(config:InsertConfig(path:root+"VMTestGain_artefacts/Release/VST3/Voicemeeter Test Gain.vst3",name:"Gain",position:.pre),rate:48000,block:512)
        var config=InsertConfig(path:root+"VMTestSide_artefacts/Release/VST3/Voicemeeter Test Sidechain.vst3",name:"Side",position:.post)
        config.sidechain = second
        let output=try HostedInsert(config:config,rate:48000,block:512)
        engine.inserts[.strip(first)]=[input];engine.inserts[.bus(.A1)]=[output]
        for slot in [input,output] {
            for _ in 0..<500 { slot.refresh();if slot.status.isEmpty {break};usleep(20000) }
            precondition(slot.status.isEmpty,slot.status)
        }
        var a1=[Float](),b1=[Float]()
        for block in 0..<14 {
            var source=[Float](repeating:0,count:1024)
            if block==0 { source[0]=0.1 }
            engine.feedOffline(first,source)
            if block==0 { source[0]=0.05 }
            engine.feedOffline(second,source)
            let buses=engine.renderOffline();a1 += buses[.A1]!;b1 += buses[.B1]!
            usleep(11000)
        }
        let ai=a1.indices.max { abs(a1[$0])<abs(a1[$1]) }!,bi=b1.indices.max { abs(b1[$0])<abs(b1[$1]) }!
        print("Mixer impulse A1 @\(ai/2)=\(a1[ai]); B1 @\(bi/2)=\(b1[bi])");fflush(stdout)
        precondition(ai==bi && ai/2==2085)
        precondition(abs(a1[ai]-0.0625)<0.0001 && abs(b1[bi]-0.1)<0.0001,"Input PDC must align the two strips; sidechain must align with the mixed input")
        print("Actual mixer (virtual=\(virtual)): input PRE, bus POST, input + bus PDC, and upstream sidechain delay passed")
    }
}
