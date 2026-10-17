import Foundation
import VMNative
import CoreAudio
import AudioToolbox
import AVFoundation

public enum RecordingSource: Int, CaseIterable, Identifiable, Codable {
    case busA1 = 0
    case busA2 = 1
    case busA3 = 2
    case busB1 = 3
    case busB2 = 4
    case strip1 = 5
    case strip2 = 6
    case strip3 = 7
    case stripVAIO = 8
    case stripAUX = 9
    case strip4 = 10
    case strip5 = 11
    case busA4 = 12
    case busA5 = 13

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .busA1: return "Master A1"
        case .busA2: return "Master A2"
        case .busA3: return "Master A3"
        case .busB1: return "Virtual Out B1"
        case .busB2: return "Virtual Out B2"
        case .strip1: return "Hardware In 1"
        case .strip2: return "Hardware In 2"
        case .strip3: return "Hardware In 3"
        case .stripVAIO: return "VAIO (PC Audio)"
        case .stripAUX: return "AUX (Comms)"
        case .strip4: return "Hardware In 4"
        case .strip5: return "Hardware In 5"
        case .busA4: return "Master A4"
        case .busA5: return "Master A5"
        }
    }
    var target: InsertTarget {
        switch self {
        case .busA1: return .bus(.A1)
        case .busA2: return .bus(.A2)
        case .busA3: return .bus(.A3)
        case .busA4: return .bus(.A4)
        case .busA5: return .bus(.A5)
        case .busB1: return .bus(.B1)
        case .busB2: return .bus(.B2)
        case .strip1: return .strip(.hardware1)
        case .strip2: return .strip(.hardware2)
        case .strip3: return .strip(.hardware3)
        case .strip4: return .strip(.hardware4)
        case .strip5: return .strip(.hardware5)
        case .stripVAIO: return .strip(.virtualVAIO)
        case .stripAUX: return .strip(.virtualAUX)
        }
    }
}

/// Real-time safe Cassette Tape Recorder & Player Engine
public final class AudioRecorderPlayer: ObservableObject {
    // MARK: - Published State for UI
    @Published public var isRecording: Bool = false
    @Published public private(set) var isFinalizingRecording = false
    @Published public private(set) var recordingError: String?
    private let recordingErrorCounter = vm_counter_create()!
    @Published public var isPlaying: Bool = false { didSet { vm_counter_store(playCounter, isPlaying ? 1 : 0) } }
    @Published public var isPaused: Bool = false
    @Published public var isLooping: Bool = false { didSet { vm_counter_store(loopCounter, isLooping ? 1 : 0); streamer?.looping = isLooping } }
    @Published public var currentTime: TimeInterval = 0.0
    @Published public var totalDuration: TimeInterval = 0.0
    @Published public var recordedDuration: TimeInterval = 0.0
    @Published public var currentFileName: String = "No File Loaded"
    @Published public var recordingSource: RecordingSource = .busB1 { didSet { vm_counter_store(sourceCounter, UInt64(recordingSource.rawValue)) } }
    @Published public var recordingFormat: RecorderFormat = .wav24
    @Published public var playbackRouting: [BusID: Bool] = [
        .A1: true, .A2: false, .A3: false, .B1: false, .B2: false
    ] { didSet {
        var mask: UInt64 = 0
        for bus in BusID.allCases where playbackRouting[bus] == true { mask |= 1 << bus.rawValue }
        vm_counter_store(routeCounter, mask)
    } }
    private let playCounter = vm_counter_create()!
    private let loopCounter = vm_counter_create()!
    private let sourceCounter = vm_counter_create()!
    private let routeCounter = vm_counter_create()!
    public var recordingActive: Bool { isRecordingWorkerRunning }
    public var realtimeRecordingSource: RecordingSource { RecordingSource(rawValue: Int(vm_counter_load(sourceCounter))) ?? .busB1 }

    // MARK: - Internal Recording Resources
    private let recordingRingBuffer: StereoRingBuffer
    private var extAudioFile: ExtAudioFileRef?
    private var recordingThread: Thread?
    private let workerCounter = vm_counter_create()!
    private var isRecordingWorkerRunning: Bool {
        get { vm_counter_load(workerCounter) != 0 }
        set { vm_counter_store(workerCounter, newValue ? 1 : 0) }
    }
    private let recordingFinished = DispatchSemaphore(value: 0)
    private var recordingLock = os_unfair_lock()
    private var recordingStartTime: Date?
    @Published public private(set) var currentRecordingURL: URL?
    private var recordingSampleRate: Double = 48000.0

    // MARK: - Internal Playback Resources
    // Swapped under playbackLock; the render callback only trylocks it.
    private var streamer: PlaybackStreamer?
    private var playbackSampleRate: Double = 48000.0
    private var playbackLock = os_unfair_lock()
    private var seenGeneration: UInt64 = .max // Render-callback only.
    private let playedFramesCounter = vm_counter_create()! // Engine frames since the last seek.
    private let engineRateBits = vm_counter_create()!
    private let playbackUnderrunCounter = vm_counter_create()!
    private let droppedRecordingCounter = vm_counter_create()!
    private var seekBaseSeconds: TimeInterval = 0
    /// Frames lost because the recording ring was full (disk writer too slow).
    @Published public private(set) var recordingDroppedFrames: UInt64 = 0
    public var playbackUnderruns: UInt64 { vm_counter_load(playbackUnderrunCounter) }

    public init() {
        // 2 second ring buffer at 48kHz stereo (96,000 frames)
        self.recordingRingBuffer = StereoRingBuffer(capacityFrames: 96000)
        vm_counter_store(sourceCounter, UInt64(RecordingSource.busB1.rawValue))
        vm_counter_store(routeCounter, 1)
    }

    deinit {
        stopRecording()
        streamer?.stop()
        renderedPlayback.deallocate()
        for counter in [playedFramesCounter, engineRateBits, playbackUnderrunCounter, droppedRecordingCounter, endedCounter] { vm_counter_destroy(counter) }
        vm_counter_destroy(recordingErrorCounter)
        vm_counter_destroy(workerCounter)
        vm_counter_destroy(playCounter)
        vm_counter_destroy(loopCounter)
        vm_counter_destroy(sourceCounter)
        vm_counter_destroy(routeCounter)
    }

    // MARK: - Real-Time Master Cycle Hook

    /// Called on real-time audio thread: pushes samples to recorder if active
    @inline(__always)
    public func pushRecordingFrames(buffer: UnsafePointer<Float>, frames: Int) {
        guard os_unfair_lock_trylock(&recordingLock) else { return }
        defer { os_unfair_lock_unlock(&recordingLock) }
        if isRecordingWorkerRunning {
            let written = recordingRingBuffer.write(from: buffer, frameCount: frames)
            if written < frames { vm_counter_store(droppedRecordingCounter, vm_counter_load(droppedRecordingCounter) + UInt64(frames - written)) }
        }
    }

    private let renderedPlayback = UnsafeMutablePointer<Float>.allocate(capacity: 4096 * 2)
    private var renderedRouteMask: UInt64 = 0
    private let endedCounter = vm_counter_create()!

    /// Render once per master cycle so every routed bus receives identical samples.
    public func renderPlayback(frames: Int, engineRate: Double) {
        memset(renderedPlayback, 0, frames * 8)
        renderedRouteMask = 0
        guard os_unfair_lock_trylock(&playbackLock) else { return }
        defer { os_unfair_lock_unlock(&playbackLock) }
        guard let streamer else { return }
        streamer.setTargetRate(engineRate)
        vm_counter_store(engineRateBits, engineRate.bitPattern)
        // A seek published a new segment: drop exactly the audio written before it.
        let ready = streamer.ready
        if ready != seenGeneration {
            streamer.ring.skip(to: streamer.segmentStart)
            seenGeneration = ready; vm_counter_store(playedFramesCounter, 0)
        }
        guard vm_counter_load(playCounter) != 0, streamer.requested == ready else { return }
        renderedRouteMask = vm_counter_load(routeCounter)
        let got = streamer.ring.read(into: renderedPlayback, frameCount: frames)
        vm_counter_store(playedFramesCounter, vm_counter_load(playedFramesCounter) + UInt64(got))
        if got < frames {
            if streamer.reachedEnd && streamer.ring.availableRead() == 0 { vm_counter_store(endedCounter, 1) }
            else { vm_counter_store(playbackUnderrunCounter, vm_counter_load(playbackUnderrunCounter) + 1) }
        }
    }
    /// Test hook: waits until the reader thread has buffered `frames` engine frames.
    @discardableResult func waitForBufferedPlayback(frames: Int, timeout: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            os_unfair_lock_lock(&playbackLock)
            let ready = streamer.map { $0.requested == $0.ready && $0.ring.availableRead() >= frames } ?? false
            os_unfair_lock_unlock(&playbackLock)
            if ready { return true }
            usleep(2000)
        }
        return false
    }

    public func mixRenderedPlayback(bus: BusID, buffer: UnsafeMutablePointer<Float>, frames: Int) {
        guard renderedRouteMask & (1 << bus.rawValue) != 0 else { return }
        for i in 0..<(frames * 2) { buffer[i] += renderedPlayback[i] }
    }

    // MARK: - Recorder Controls

    public func startRecording(sampleRate: Double = 48000.0, directory: URL? = nil) -> URL? {
        guard !isRecording, !isFinalizingRecording else { return nil }
        recordingError = nil
        vm_counter_store(recordingErrorCounter, 0)
        vm_counter_store(droppedRecordingCounter, 0); recordingDroppedFrames = 0

        self.recordingSampleRate = sampleRate
        let fileManager = FileManager.default
        let musicDir = fileManager.urls(for: .musicDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let recordingsDir = directory ?? musicDir.appendingPathComponent("AudiomeeterRecordings", isDirectory: true)

        try? fileManager.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = formatter.string(from: Date())
        let ext = recordingFormat.fileExtension
        let fileURL = recordingsDir.appendingPathComponent("AM_REC_\(dateString)_\(UUID().uuidString).\(ext)")

        // Setup ExtAudioFile
        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        var fileFormat = AudioStreamBasicDescription()
        fileFormat.mSampleRate = sampleRate
        fileFormat.mChannelsPerFrame = 2

        if recordingFormat.isWAV {
            fileFormat.mFormatID = kAudioFormatLinearPCM
            switch recordingFormat {
            case .wav16:
                fileFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
                fileFormat.mBitsPerChannel = 16
                fileFormat.mBytesPerFrame = 4
                fileFormat.mBytesPerPacket = 4
            case .wav24:
                fileFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
                fileFormat.mBitsPerChannel = 24
                fileFormat.mBytesPerFrame = 6
                fileFormat.mBytesPerPacket = 6
            case .wavFloat32:
                fileFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
                fileFormat.mBitsPerChannel = 32
                fileFormat.mBytesPerFrame = 8
                fileFormat.mBytesPerPacket = 8
            default:
                break
            }
            fileFormat.mFramesPerPacket = 1
        } else {
            // AAC encoding
            fileFormat.mFormatID = kAudioFormatMPEG4AAC
            fileFormat.mFormatFlags = 0
            fileFormat.mFramesPerPacket = 1024
            fileFormat.mChannelsPerFrame = 2
            fileFormat.mBytesPerPacket = 0
            fileFormat.mBytesPerFrame = 0
            fileFormat.mBitsPerChannel = 0
        }

        let fileType: AudioFileTypeID = recordingFormat.isWAV ? kAudioFileWAVEType : kAudioFileM4AType

        var audioFile: ExtAudioFileRef?
        let status = ExtAudioFileCreateWithURL(
            fileURL as CFURL,
            fileType,
            &fileFormat,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &audioFile
        )

        guard status == noErr, let audioFile = audioFile else {
            print("Failed to create ExtAudioFile: \(status)")
            return nil
        }

        // Set client data format (our internal 32-bit Float stereo)
        let setFormatStatus = ExtAudioFileSetProperty(
            audioFile,
            kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &clientFormat
        )

        guard setFormatStatus == noErr else {
            ExtAudioFileDispose(audioFile)
            print("Failed to set client format: \(setFormatStatus)")
            return nil
        }

        // Initialize async disk writer
        self.extAudioFile = audioFile
        self.currentRecordingURL = fileURL
        os_unfair_lock_lock(&recordingLock)
        self.recordingRingBuffer.reset()
        self.recordingStartTime = Date()
        self.isRecording = true
        self.isRecordingWorkerRunning = true
        os_unfair_lock_unlock(&recordingLock)

        let thread = Thread { [weak self] in
            self?.recordingWorkerLoop()
        }
        thread.name = "AudiomeeterRecordingWorker"
        thread.qualityOfService = .userInitiated
        self.recordingThread = thread
        thread.start()

        return fileURL
    }

    public func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        os_unfair_lock_lock(&recordingLock)
        isRecordingWorkerRunning = false
        os_unfair_lock_unlock(&recordingLock)
        recordingFinished.wait()

        if let audioFile = extAudioFile {
            ExtAudioFileDispose(audioFile)
            self.extAudioFile = nil
        }
        self.recordingThread = nil
        self.recordingStartTime = nil
    }

    private func requestRecordingStop() {
        os_unfair_lock_lock(&recordingLock)
        isRecordingWorkerRunning = false
        os_unfair_lock_unlock(&recordingLock)
    }

    /// Drain and close the file off the UI thread. A new recording cannot start until done.
    @MainActor public func finishRecording() async {
        if isFinalizingRecording {
            while isFinalizingRecording { try? await Task.sleep(nanoseconds: 10_000_000) }
            return
        }
        guard isRecording else { return }
        isFinalizingRecording = true
        isRecording = false
        requestRecordingStop()
        let fileAddress = extAudioFile.map { UInt(bitPattern: $0) }
        let semaphore = recordingFinished
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                semaphore.wait()
                if let fileAddress, let file = ExtAudioFileRef(bitPattern: fileAddress) { ExtAudioFileDispose(file) }
                continuation.resume()
            }
        }
        extAudioFile = nil
        recordingThread = nil
        recordingStartTime = nil
        publishRecordingError()
        isFinalizingRecording = false
    }

    private func publishRecordingError() {
        let status = OSStatus(truncatingIfNeeded: vm_counter_load(recordingErrorCounter))
        if status != noErr { recordingError = L10n.text("録音の書き込みに失敗しました (OSStatus {0})。", [String(status)]) }
    }

    private func recordingWorkerLoop() {
        defer { recordingFinished.signal() }
        let chunkSize = 4096
        var chunk = [Float](repeating: 0, count: chunkSize)

        while isRecordingWorkerRunning || recordingRingBuffer.availableRead() > 0 {
            let available = recordingRingBuffer.availableRead()
            if available < 256 && isRecordingWorkerRunning {
                usleep(5000) // Sleep 5ms
                continue
            }

            let framesToRead = min(available, chunkSize / 2)
            if framesToRead <= 0 {
                if !isRecordingWorkerRunning { break }
                usleep(5000)
                continue
            }

            let framesRead = chunk.withUnsafeMutableBufferPointer { ptr in
                recordingRingBuffer.read(into: ptr.baseAddress!, frameCount: framesToRead)
            }

            if framesRead > 0, let audioFile = extAudioFile {
                let frames = UInt32(framesRead)
                chunk.withUnsafeMutableBytes { rawBytes in
                    var bufferList = AudioBufferList(
                        mNumberBuffers: 1,
                        mBuffers: AudioBuffer(
                            mNumberChannels: 2,
                            mDataByteSize: frames * 8,
                            mData: rawBytes.baseAddress
                        )
                    )
                    let status = ExtAudioFileWrite(audioFile, frames, &bufferList)
                    if status != noErr {
                        vm_counter_store(recordingErrorCounter, UInt64(bitPattern: Int64(status)))
                        isRecordingWorkerRunning = false
                    }
                }
            }
            if vm_counter_load(recordingErrorCounter) != 0 { break }
        }
    }

    // MARK: - Player Controls

    public func loadAudioFile(url: URL) -> Bool {
        do {
            let next = try PlaybackStreamer(url: url)
            next.looping = isLooping
            next.seek(toFileFrame: 0)
            os_unfair_lock_lock(&playbackLock)
            let previous = streamer
            streamer = next
            seenGeneration = .max
            os_unfair_lock_unlock(&playbackLock)
            previous?.stop() // Outside the lock; the callback no longer references it.
            vm_counter_store(endedCounter, 0); vm_counter_store(playedFramesCounter, 0)
            playbackSampleRate = next.fileRate
            seekBaseSeconds = 0
            totalDuration = next.duration
            currentFileName = url.lastPathComponent
            currentTime = 0.0
            return true
        } catch {
            print("Failed to load audio file: \(error)")
            return false
        }
    }

    public func play() {
        guard streamer != nil else { return }
        if vm_counter_load(endedCounter) != 0 { seek(progress: 0) }
        isPaused = false
        isPlaying = true
    }

    public func pause() {
        isPaused = true
        isPlaying = false
    }

    public func stopPlayback() {
        isPlaying = false
        isPaused = false
        seek(progress: 0)
    }

    public func seek(progress: Double) {
        guard let streamer else { return }
        let target = max(0, min(1, progress.isFinite ? progress : 0)) * streamer.duration
        streamer.seek(toFileFrame: Int64(target * streamer.fileRate))
        vm_counter_store(endedCounter, 0)
        seekBaseSeconds = target
        currentTime = target
    }

    public func updatePlaybackTime() {
        publishRecordingError()
        if isRecording, vm_counter_load(recordingErrorCounter) != 0 {
            Task { @MainActor in await self.finishRecording() }
        }
        let dropped = vm_counter_load(droppedRecordingCounter)
        if dropped != recordingDroppedFrames { recordingDroppedFrames = dropped }
        if isPlaying && totalDuration > 0 {
            if vm_counter_load(endedCounter) != 0 { isPlaying = false; currentTime = totalDuration; return }
            let rate = Double(bitPattern: vm_counter_load(engineRateBits))
            let elapsed = rate > 0 ? Double(vm_counter_load(playedFramesCounter)) / rate : 0
            let position = seekBaseSeconds + elapsed
            currentTime = isLooping ? position.truncatingRemainder(dividingBy: totalDuration) : min(totalDuration, position)
        }
        if isRecording, let start = recordingStartTime {
            self.recordedDuration = Date().timeIntervalSince(start)
        }
    }
}
