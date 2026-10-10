import Foundation
import CoreAudio
import AVFoundation
import VMNative

@main
struct AudioRegressionTests {
    static func main() throws {
        testConcurrentRing()
        testGroupedBuffers()
        testUnityDSP()
        testStreamingResampler()
        try testTapeRoutingAndRate()
        try testRecordingDrain()
        testPluginHost()
        print("Audio regression tests passed")
    }

    static func testConcurrentRing() {
        let ring = StereoRingBuffer(capacityFrames: 4096)
        let count = 500_000
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            var samples = [Float](repeating: 0, count: 128 * 2)
            var index = 0
            while index < count {
                let frames = min(128, count - index)
                for frame in 0..<frames { samples[frame * 2] = Float(index + frame); samples[frame * 2 + 1] = -Float(index + frame) }
                let written = samples.withUnsafeBufferPointer { ring.write(from: $0.baseAddress!, frameCount: frames) }
                index += written
                if written == 0 { usleep(1) }
            }
            group.leave()
        }
        var index = 0
        var output = [Float](repeating: 0, count: 193 * 2)
        while index < count {
            let read = output.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, frameCount: min(193, count - index)) }
            for frame in 0..<read {
                precondition(output[frame * 2] == Float(index + frame))
                precondition(output[frame * 2 + 1] == -Float(index + frame))
            }
            index += read
            if read == 0 { usleep(1) }
        }
        group.wait()
        precondition(ring.availableRead() == 0)
        print("  SPSC concurrent transfer: 500,000 ordered stereo frames")
    }

    static func testGroupedBuffers() {
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        defer { list.unsafeMutablePointer.deallocate() }
        let a = UnsafeMutablePointer<Float>.allocate(capacity: 8)
        let b = UnsafeMutablePointer<Float>.allocate(capacity: 6)
        defer { a.deallocate(); b.deallocate() }
        a.initialize(repeating: 9, count: 8); b.initialize(repeating: 9, count: 6)
        list[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 32, mData: a)
        list[1] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 24, mData: b)
        let source: [Float] = [0.2, -0.3, 0.4, -0.5]
        source.withUnsafeBufferPointer { StereoAudioBufferIO.write($0.baseAddress!, frames: 2, to: list.unsafeMutablePointer, channelOffset: 2) }
        precondition((0..<8).allSatisfy { a[$0] == 0 })
        precondition(b[0] == 0.2 && b[1] == -0.3 && b[4] == 0 && b[5] == 0)
        var output = [Float](repeating: 1, count: 8)
        let frames = output.withUnsafeMutableBufferPointer { StereoAudioBufferIO.read(list.unsafeMutablePointer, into: $0.baseAddress!, capacity: 4, channelOffset: 2) }
        precondition(frames == 3 && output[0] == 0.2 && output[1] == -0.3 && output[4] == 0)
        source.withUnsafeBufferPointer { StereoAudioBufferIO.write($0.baseAddress!, frames: 2, to: list.unsafeMutablePointer, leftChannel: 2, rightChannel: 0) }
        precondition(b[0] == 0.2 && a[0] == -0.3 && a[1] == 0 && b[1] == 0)
        let mappedFrames = output.withUnsafeMutableBufferPointer { StereoAudioBufferIO.read(list.unsafeMutablePointer, into: $0.baseAddress!, capacity: 4, leftChannel: 2, rightChannel: 0) }
        precondition(mappedFrames == 3 && output[0] == 0.2 && output[1] == -0.3)
        source.withUnsafeBufferPointer { StereoAudioBufferIO.write($0.baseAddress!, frames: 2, to: list.unsafeMutablePointer, leftChannel: 3, rightChannel: 2) }
        precondition(b[1] == 0.2 && b[0] == -0.3)
        source.withUnsafeBufferPointer { StereoAudioBufferIO.write($0.baseAddress!, frames: 2, to: list.unsafeMutablePointer, leftChannel: 2, rightChannel: 2) }
        precondition(abs(b[0] - (source[0] + source[1]) * 0.5) < 0.00001 && b[1] == 0)
        _ = output.withUnsafeMutableBufferPointer { StereoAudioBufferIO.read(list.unsafeMutablePointer, into: $0.baseAddress!, capacity: 4, leftChannel: 2, rightChannel: 2) }
        precondition(output[0] == output[1])
        source.withUnsafeBufferPointer { StereoAudioBufferIO.write($0.baseAddress!, frames: 2, to: list.unsafeMutablePointer, leftChannel: 99, rightChannel: 0) }
        precondition(a[0] == -0.3 && a[1] == 0 && b[0] == 0)
        _ = output.withUnsafeMutableBufferPointer { StereoAudioBufferIO.read(list.unsafeMutablePointer, into: $0.baseAddress!, capacity: 4, leftChannel: 99, rightChannel: 0) }
        precondition(output[0] == 0 && output[1] == -0.3)
        print("  Grouped stereo streams, channel offsets, and silence tails")
    }

    static func testUnityDSP() {
        var samples = [Float](repeating: 0.25, count: 512)
        let strip = StripDSP()
        samples.withUnsafeMutableBufferPointer {
            strip.process(buffer: $0.baseAddress!, frames: 256, sampleRate: 48000, gainDB: 0, isMuted: false, dynamicsConfig: DynamicsConfig(), intellipan: IntellipanState(), eq: EQ3Band(), isVirtual: true)
        }
        precondition(samples.allSatisfy { abs($0 - 0.25) < 0.00001 }, "Neutral strip must retain unity gain")
        let bus = BusDSP()
        samples.withUnsafeMutableBufferPointer {
            bus.process(buffer: $0.baseAddress!, frames: 256, sampleRate: 48000, gainDB: 0, isMuted: false, mode: .normal)
        }
        precondition(samples.allSatisfy { abs($0 - 0.25) < 0.00001 }, "Limiter must be transparent below threshold")
        var config = MasterEQConfig(isEnabled: true); config.bands = []
        samples.withUnsafeMutableBufferPointer { bus.process(buffer: $0.baseAddress!, frames: 256, sampleRate: 48000, gainDB: 0, isMuted: false, mode: .normal, isEQEnabled: true, eqConfig: config) }
        print("  Neutral DSP unity, transparent limiter, and truncated EQ safety")
    }

    static func testStreamingResampler() {
        let source = (0..<4096).flatMap { index -> [Float] in let value = sin(Float(index) * 0.08); return [value, -value] }
        func render(block: Int) -> [Float] {
            let converter = AdaptiveResampler(sourceRate: 44100, targetRate: 48000)
            var result: [Float] = []
            var offset = 0
            while offset < 4096 {
                let frames = min(block, 4096 - offset)
                let target = converter.outputFrameCount(forSourceFrames: frames)
                var out = [Float](repeating: 0, count: target * 2)
                source.withUnsafeBufferPointer { src in out.withUnsafeMutableBufferPointer { dst in _ = converter.resample(source: src.baseAddress!.advanced(by: offset * 2), sourceFrames: frames, destination: dst.baseAddress!, targetFrames: target) } }
                result += out; offset += frames
            }
            return result
        }
        let small = render(block: 128), large = render(block: 1024)
        precondition(small.count == large.count)
        precondition(zip(small, large).allSatisfy { abs($0 - $1) < 0.0001 }, "Resampling must preserve phase across callbacks")
        print("  Streaming resampler: callback-size independent waveform")
    }

    static func testTapeRoutingAndRate() throws {
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("tape-fixture.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 2)!
        var settings = format.settings
        settings[AVLinearPCMIsNonInterleaved] = false
        var file: AVAudioFile? = try AVAudioFile(forWriting: fixture, settings: settings)
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        pcm.frameLength = 1024
        for i in 0..<1024 { pcm.floatChannelData![0][i] = Float(i) / 1024; pcm.floatChannelData![1][i] = -Float(i) / 1024 }
        try file!.write(from: pcm)
        file = nil
        let player = AudioRecorderPlayer()
        precondition(player.loadAudioFile(url: fixture))
        player.playbackRouting = [.A2: true, .A3: true, .B2: true]
        player.play()
        player.renderPlayback(frames: 128, engineRate: 48000)
        var a = [Float](repeating: 0, count: 256), b = a
        a.withUnsafeMutableBufferPointer { player.mixRenderedPlayback(bus: .A2, buffer: $0.baseAddress!, frames: 128) }
        b.withUnsafeMutableBufferPointer { player.mixRenderedPlayback(bus: .B2, buffer: $0.baseAddress!, frames: 128) }
        precondition(a == b, "Every bus must receive the same playback block")
        precondition(abs(a[2] - 0.5 / 1024) < 0.00001)
        player.renderPlayback(frames: 128, engineRate: 48000)
        a = [Float](repeating: 0, count: 256)
        a.withUnsafeMutableBufferPointer { player.mixRenderedPlayback(bus: .A2, buffer: $0.baseAddress!, frames: 128) }
        precondition(abs(a[0] - 64.0 / 1024) < 0.00001, "A2-only routing must advance playback")
        print("  Tape playback: multi-bus alignment, A2-only advance, 24→48 kHz rate")
    }

    static func testRecordingDrain() throws {
        let recorder = AudioRecorderPlayer()
        recorder.recordingFormat = .wavFloat32
        guard let url = recorder.startRecording(sampleRate: 48000) else { fatalError("Cannot create recording") }
        let samples = [Float](repeating: 0.125, count: 512)
        for _ in 0..<100 { samples.withUnsafeBufferPointer { recorder.pushRecordingFrames(buffer: $0.baseAddress!, frames: 256) } }
        recorder.stopRecording()
        let file = try AVAudioFile(forReading: url)
        precondition(file.length == 25_600, "Stop must drain all queued frames before closing file")
        try FileManager.default.removeItem(at: url)
        print("  Recording: full 25,600-frame drain before file disposal")
    }

    static func testPluginHost() {
        let root = CommandLine.arguments[2]
        precondition(vm_host_load(root + "/libVMPluginHost.dylib") != 0)
        var error = [CChar](repeating: 0, count: 1024)
        let path = root + "/VMTestGain_artefacts/Release/VST3/Voicemeeter Test Gain.vst3"
        let scanned = String(cString: vm_plugin_scan(path))
        let data = Data(scanned.utf8)
        let entries = try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        precondition(entries.count == 1)
        precondition(entries[0]["name"] as? String == "Voicemeeter Test Gain")
        let identifier = entries[0]["identifier"] as! String
        precondition(vm_plugin_create_named(path, "invalid-id", 48000, 256, &error, 1024) == nil)
        guard let plugin = vm_plugin_create_named(path, identifier, 48000, 256, &error, 1024) else { fatalError(String(cString: error)) }
        defer { vm_plugin_destroy(plugin) }
        var samples = [Float](repeating: 0.5, count: 512)
        samples.withUnsafeMutableBufferPointer { vm_plugin_process(plugin, $0.baseAddress!, 256) }
        precondition(samples.allSatisfy { abs($0 - 0.25) < 0.00001 })
        let state = String(cString: vm_plugin_state(plugin)); precondition(!state.isEmpty)
        vm_plugin_restore(plugin, state)
        vm_plugin_prepare(plugin, 96000, 512)
        precondition(vm_plugin_latency(plugin) == 0)
        print("  ARM64 VST3: load, stereo processing, state roundtrip, rate reconfiguration")
    }
}
