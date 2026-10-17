import Foundation
import AVFoundation
import VMNative

/// Streams a file from disk on its own thread, converting to the engine rate with
/// AVAudioConverter (band-limited SRC), into an SPSC ring read by the render callback.
/// Files are never loaded whole, so long recordings play with bounded memory.
final class PlaybackStreamer: @unchecked Sendable {
    let ring = StereoRingBuffer(capacityFrames: 262144)
    let duration: TimeInterval
    let fileRate: Double
    private let url: URL
    private var thread: Thread?
    // Main -> reader.
    private let requestedGeneration = vm_counter_create()!
    private let seekFrameCounter = vm_counter_create()!
    private let loopingCounter = vm_counter_create()!
    private let stopCounter = vm_counter_create()!
    // Render callback -> reader.
    private let targetRateBits = vm_counter_create()!
    // Reader -> render callback: data for `readyGeneration` starts at `segmentStart`.
    private let readyGenerationCounter = vm_counter_create()!
    private let segmentStartCounter = vm_counter_create()!
    private let endGenerationCounter = vm_counter_create()!
    private let finished = DispatchSemaphore(value: 0)

    init(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        self.url = url
        fileRate = file.processingFormat.sampleRate
        duration = Double(file.length) / max(1, fileRate)
        vm_counter_store(endGenerationCounter, UInt64.max)
        let thread = Thread { [weak self] in self?.run(); }
        thread.name = "AudiomeeterPlaybackReader"
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
    }
    deinit {
        stop()
        for counter in [requestedGeneration, seekFrameCounter, loopingCounter, stopCounter, targetRateBits, readyGenerationCounter, segmentStartCounter, endGenerationCounter] { vm_counter_destroy(counter) }
    }
    func stop() {
        guard thread != nil else { return }
        vm_counter_store(stopCounter, 1)
        finished.wait()
        thread = nil
    }

    var looping: Bool { get { vm_counter_load(loopingCounter) != 0 } set { vm_counter_store(loopingCounter, newValue ? 1 : 0) } }
    /// Main thread: restart streaming at a file frame.
    func seek(toFileFrame frame: Int64) {
        vm_counter_store(seekFrameCounter, UInt64(max(0, frame)))
        vm_counter_store(requestedGeneration, vm_counter_load(requestedGeneration) &+ 1)
    }
    // Render callback side.
    func setTargetRate(_ rate: Double) { vm_counter_store(targetRateBits, rate.bitPattern) }
    var requested: UInt64 { vm_counter_load(requestedGeneration) }
    var ready: UInt64 { vm_counter_load(readyGenerationCounter) }
    var segmentStart: UInt64 { vm_counter_load(segmentStartCounter) }
    var reachedEnd: Bool { vm_counter_load(endGenerationCounter) == ready }

    private func run() {
        defer { finished.signal() }
        guard let file = try? AVAudioFile(forReading: url) else { return }
        let input = file.processingFormat
        var generation: UInt64 = .max
        var rate = 0.0
        var converter: AVAudioConverter?
        var output: AVAudioPCMBuffer?
        let chunk: AVAudioFrameCount = 4096
        guard let source = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: chunk) else { return }
        var atEnd = false
        while vm_counter_load(stopCounter) == 0 {
            let wantedRate = Double(bitPattern: vm_counter_load(targetRateBits))
            let wantedGeneration = vm_counter_load(requestedGeneration)
            if wantedRate < 8000 { usleep(5000); continue }
            if wantedGeneration != generation || wantedRate != rate {
                // New segment: reposition, rebuild the converter, then publish where it begins.
                if wantedRate != rate || converter == nil {
                    rate = wantedRate
                    guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: true),
                          let next = AVAudioConverter(from: input, to: format) else { return }
                    next.sampleRateConverterQuality = AVAudioQuality.max.rawValue
                    next.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering
                    next.channelMap = input.channelCount == 1 ? [0, 0] : [0, 1]
                    converter = next
                    output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(chunk) * rate / input.sampleRate) + 64)
                }
                if wantedGeneration != generation {
                    // A rate change alone keeps the playback position.
                    file.framePosition = min(file.length, Int64(vm_counter_load(seekFrameCounter)))
                }
                converter?.reset()
                generation = wantedGeneration; atEnd = false
                vm_counter_store(segmentStartCounter, ring.writePosition)
                vm_counter_store(readyGenerationCounter, generation)
            }
            guard let converter, let output else { return }
            if atEnd { usleep(5000); continue }
            if ring.availableWrite() < Int(output.frameCapacity) { usleep(3000); continue }
            var status: AVAudioConverterOutputStatus = .error
            var error: NSError?
            output.frameLength = 0
            status = converter.convert(to: output, error: &error) { _, inputStatus in
                if file.framePosition >= file.length {
                    if self.looping { file.framePosition = 0 } else { inputStatus.pointee = .endOfStream; return nil }
                }
                source.frameLength = 0
                do { try file.read(into: source, frameCount: chunk) } catch { inputStatus.pointee = .endOfStream; return nil }
                if source.frameLength == 0 { inputStatus.pointee = .endOfStream; return nil }
                inputStatus.pointee = .haveData
                return source
            }
            if output.frameLength > 0, let data = output.floatChannelData?[0] {
                ring.write(from: data, frameCount: Int(output.frameLength))
            }
            if status == .endOfStream || status == .error {
                atEnd = true
                vm_counter_store(endGenerationCounter, generation)
            }
        }
    }
}
