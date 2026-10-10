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
        }
    }
}

/// Real-time safe Cassette Tape Recorder & Player Engine
public final class AudioRecorderPlayer: ObservableObject {
    // MARK: - Published State for UI
    @Published public var isRecording: Bool = false
    @Published public var isPlaying: Bool = false { didSet { vm_counter_store(playCounter, isPlaying ? 1 : 0) } }
    @Published public var isPaused: Bool = false
    @Published public var isLooping: Bool = false { didSet { vm_counter_store(loopCounter, isLooping ? 1 : 0) } }
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
    private var audioFileBuffer: [Float] = []
    private var playbackReadIndex: Int = 0
    private var playbackSampleRate: Double = 48000.0
    private var playbackLock = os_unfair_lock()

    public init() {
        // 2 second ring buffer at 48kHz stereo (96,000 frames)
        self.recordingRingBuffer = StereoRingBuffer(capacityFrames: 96000)
        vm_counter_store(sourceCounter, UInt64(RecordingSource.busB1.rawValue))
        vm_counter_store(routeCounter, 1)
    }

    deinit {
        stopRecording()
        stopPlayback()
        renderedPlayback.deallocate()
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
        if isRecordingWorkerRunning { _ = recordingRingBuffer.write(from: buffer, frameCount: frames) }
    }

    private let renderedPlayback = UnsafeMutablePointer<Float>.allocate(capacity: 4096 * 2)
    private var playbackPosition: Double = 0
    private var renderedRouteMask: UInt64 = 0
    private var playbackEnded = false

    /// Render once per master cycle so every routed bus receives identical samples.
    public func renderPlayback(frames: Int, engineRate: Double) {
        memset(renderedPlayback, 0, frames * 8)
        renderedRouteMask = 0
        guard os_unfair_lock_trylock(&playbackLock) else { return }
        defer { os_unfair_lock_unlock(&playbackLock) }
        guard vm_counter_load(playCounter) != 0, !audioFileBuffer.isEmpty else { return }
        renderedRouteMask = vm_counter_load(routeCounter)
        let looping = vm_counter_load(loopCounter) != 0
        let totalFrames = audioFileBuffer.count / 2
        let step = playbackSampleRate / engineRate
        for i in 0..<frames {
            if playbackPosition >= Double(totalFrames) {
                if looping { playbackPosition.formTruncatingRemainder(dividingBy: Double(totalFrames)) }
                else { playbackEnded = true; break }
            }
            let first = Int(playbackPosition)
            let next = first + 1 < totalFrames ? first + 1 : (looping ? 0 : first)
            let fraction = Float(playbackPosition - Double(first))
            for channel in 0..<2 {
                let a = audioFileBuffer[first * 2 + channel]
                renderedPlayback[i * 2 + channel] = a + fraction * (audioFileBuffer[next * 2 + channel] - a)
            }
            playbackPosition += step
        }
        playbackReadIndex = min(totalFrames, Int(playbackPosition)) * 2
    }

    public func mixRenderedPlayback(bus: BusID, buffer: UnsafeMutablePointer<Float>, frames: Int) {
        guard renderedRouteMask & (1 << bus.rawValue) != 0 else { return }
        for i in 0..<(frames * 2) { buffer[i] += renderedPlayback[i] }
    }

    // MARK: - Recorder Controls

    public func startRecording(sampleRate: Double = 48000.0) -> URL? {
        guard !isRecording else { return nil }

        self.recordingSampleRate = sampleRate
        let fileManager = FileManager.default
        let musicDir = fileManager.urls(for: .musicDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let recordingsDir = musicDir.appendingPathComponent("VoicemeeterRecordings", isDirectory: true)

        try? fileManager.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = formatter.string(from: Date())
        let ext = recordingFormat.fileExtension
        let fileURL = recordingsDir.appendingPathComponent("VM_REC_\(dateString).\(ext)")

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
        thread.name = "VoicemeeterRecordingWorker"
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
                    ExtAudioFileWrite(audioFile, frames, &bufferList)
                }
            }
        }
    }

    // MARK: - Player Controls

    public func loadAudioFile(url: URL) -> Bool {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let frameCount = UInt32(file.length)

            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                return false
            }
            try file.read(into: pcmBuffer)

            os_unfair_lock_lock(&playbackLock)
            let channels = Int(format.channelCount)
            let frames = Int(pcmBuffer.frameLength)
            var interleaved = [Float](repeating: 0, count: frames * 2)

            if channels >= 2, let left = pcmBuffer.floatChannelData?[0], let right = pcmBuffer.floatChannelData?[1] {
                for i in 0..<frames {
                    interleaved[i * 2] = left[i]
                    interleaved[i * 2 + 1] = right[i]
                }
            } else if channels == 1, let mono = pcmBuffer.floatChannelData?[0] {
                for i in 0..<frames {
                    interleaved[i * 2] = mono[i]
                    interleaved[i * 2 + 1] = mono[i]
                }
            }

            self.audioFileBuffer = interleaved
            self.playbackReadIndex = 0
            self.playbackPosition = 0
            self.playbackEnded = false
            self.playbackSampleRate = format.sampleRate
            self.totalDuration = Double(frames) / format.sampleRate
            self.currentFileName = url.lastPathComponent
            self.currentTime = 0.0
            os_unfair_lock_unlock(&playbackLock)

            return true
        } catch {
            print("Failed to load audio file: \(error)")
            return false
        }
    }

    public func play() {
        guard !audioFileBuffer.isEmpty else { return }
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
        os_unfair_lock_lock(&playbackLock)
        playbackReadIndex = 0
        playbackPosition = 0
        playbackEnded = false
        currentTime = 0.0
        os_unfair_lock_unlock(&playbackLock)
    }

    public func seek(progress: Double) {
        os_unfair_lock_lock(&playbackLock)
        let totalFrames = audioFileBuffer.count / 2
        let targetFrame = Int(progress * Double(totalFrames))
        playbackReadIndex = max(0, min(max(0, totalFrames - 1), targetFrame)) * 2
        playbackPosition = Double(playbackReadIndex / 2)
        playbackEnded = false
        currentTime = Double(targetFrame) / (playbackSampleRate > 0 ? playbackSampleRate : 48000.0)
        os_unfair_lock_unlock(&playbackLock)
    }

    public func updatePlaybackTime() {
        if isPlaying && totalDuration > 0 {
            os_unfair_lock_lock(&playbackLock)
            if playbackEnded { isPlaying = false; playbackEnded = false }
            let currentFrame = playbackReadIndex / 2
            let rate = playbackSampleRate > 0 ? playbackSampleRate : 48000.0
            self.currentTime = Double(currentFrame) / rate
            os_unfair_lock_unlock(&playbackLock)
        }
        if isRecording, let start = recordingStartTime {
            self.recordedDuration = Date().timeIntervalSince(start)
        }
    }
}
