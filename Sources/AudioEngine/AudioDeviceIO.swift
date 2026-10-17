import Foundation
import CoreAudio
import AudioToolbox

/// Encapsulates a CoreAudio real-time input capture stream
public final class AudioInputIO {
    public let deviceID: AudioObjectID
    public let channelOffset: Int
    public let leftChannel: Int?
    public let rightChannel: Int?
    private var ioProcID: AudioDeviceIOProcID?
    private var isRunning: Bool = false
    public private(set) var lastError: OSStatus?
    private let ringBuffer: StereoRingBuffer
    private let resampler: AdaptiveResampler
    private var tempInterleaved: UnsafeMutablePointer<Float>
    private let tempCapacity: Int = 8192
    private var scratchResampled: UnsafeMutablePointer<Float>
    let deviceSampleRate: Double
    let deviceBufferSize: UInt32
    private let engineSampleRate: Double
    var correctionPPM: Double { resampler.correctionPPM }

    public init(deviceID: AudioObjectID, engineRate: Double, ringBuffer: StereoRingBuffer, channelOffset: Int = 0, leftChannel: Int? = nil, rightChannel: Int? = nil, engineFrames: UInt32 = 256) {
        self.deviceID = deviceID
        self.channelOffset = channelOffset
        self.leftChannel = leftChannel; self.rightChannel = rightChannel
        self.engineSampleRate = engineRate
        self.ringBuffer = ringBuffer

        self.deviceBufferSize = AudioDeviceManager.shared.getDeviceBufferSize(id: deviceID)
        let devRate = AudioDeviceManager.shared.getDeviceSampleRate(id: deviceID)
        self.deviceSampleRate = devRate > 0 ? devRate : engineRate
        self.resampler = AdaptiveResampler(sourceRate: self.deviceSampleRate, targetRate: engineRate, targetFill: min(0.45, Float(max(Double(engineFrames), Double(deviceBufferSize) * engineRate / self.deviceSampleRate) * 3 / 16384)))

        self.tempInterleaved = UnsafeMutablePointer<Float>.allocate(capacity: tempCapacity * 2)
        self.tempInterleaved.initialize(repeating: 0.0, count: tempCapacity * 2)

        self.scratchResampled = UnsafeMutablePointer<Float>.allocate(capacity: tempCapacity * 2)
        self.scratchResampled.initialize(repeating: 0.0, count: tempCapacity * 2)
    }

    deinit {
        stop()
        tempInterleaved.deallocate()
        scratchResampled.deallocate()
    }

    public func start() {
        guard !isRunning else { return }
        lastError = nil

        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, deviceID, nil) { [weak self] inNow, inInputData, inInputTime, outOutputData, outOutputTime in
            guard let self = self else { return }
            self.processInput(inputData: inInputData)
        }

        guard status == noErr, let validProc = proc else {
            lastError = status
            print("Failed to create input IOProc for device \(deviceID): status \(status)")
            return
        }
        self.ioProcID = validProc

        let startStatus = AudioDeviceStart(deviceID, validProc)
        if startStatus == noErr {
            isRunning = true
        } else {
            AudioDeviceDestroyIOProcID(deviceID, validProc)
            ioProcID = nil
            lastError = startStatus
            print("Failed to start input device \(deviceID): status \(startStatus)")
        }
    }

    public func stop() {
        guard isRunning, let proc = ioProcID else { return }
        AudioDeviceStop(deviceID, proc)
        AudioDeviceDestroyIOProcID(deviceID, proc)
        ioProcID = nil
        isRunning = false
    }

    private func processInput(inputData: UnsafePointer<AudioBufferList>) {
        let frameCount = StereoAudioBufferIO.read(inputData, into: tempInterleaved, capacity: tempCapacity, channelOffset: channelOffset, leftChannel: leftChannel, rightChannel: rightChannel)

        guard frameCount > 0 else { return }

        // Every independently clocked device needs drift compensation, even when
        // both advertise the same nominal sample rate.
        resampler.updateDrift(currentFillRatio: ringBuffer.fillRatio())
        let targetFrames = min(resampler.outputFrameCount(forSourceFrames: frameCount), tempCapacity)
        let written = resampler.resample(
            source: tempInterleaved,
            sourceFrames: frameCount,
            destination: scratchResampled,
            targetFrames: targetFrames
        )
        ringBuffer.write(from: scratchResampled, frameCount: written)
    }
}

/// Encapsulates a CoreAudio real-time output playback stream (for secondary buses A2, A3, B1, B2)
public final class AudioOutputIO {
    public let deviceID: AudioObjectID
    public let channelOffset: Int
    public let leftChannel: Int?
    public let rightChannel: Int?
    private var ioProcID: AudioDeviceIOProcID?
    private var isRunning: Bool = false
    public private(set) var lastError: OSStatus?
    private let ringBuffer: StereoRingBuffer
    private let resampler: AdaptiveResampler
    private var tempInterleaved: UnsafeMutablePointer<Float>
    private let tempCapacity: Int = 8192
    private var scratchResampled: UnsafeMutablePointer<Float>
    let deviceSampleRate: Double
    let deviceBufferSize: UInt32
    private let engineSampleRate: Double
    var correctionPPM: Double { resampler.correctionPPM }

    public init(deviceID: AudioObjectID, engineRate: Double, ringBuffer: StereoRingBuffer, channelOffset: Int = 0, leftChannel: Int? = nil, rightChannel: Int? = nil, engineFrames: UInt32 = 256) {
        self.deviceID = deviceID
        self.channelOffset = channelOffset
        self.leftChannel = leftChannel; self.rightChannel = rightChannel
        self.engineSampleRate = engineRate
        self.ringBuffer = ringBuffer

        self.deviceBufferSize = AudioDeviceManager.shared.getDeviceBufferSize(id: deviceID)
        let devRate = AudioDeviceManager.shared.getDeviceSampleRate(id: deviceID)
        self.deviceSampleRate = devRate > 0 ? devRate : engineRate
        self.resampler = AdaptiveResampler(sourceRate: engineRate, targetRate: self.deviceSampleRate, targetFill: min(0.65, Float(max(Double(engineFrames), Double(deviceBufferSize) * engineRate / self.deviceSampleRate) * 3 / 16384)))

        self.tempInterleaved = UnsafeMutablePointer<Float>.allocate(capacity: tempCapacity * 2)
        self.tempInterleaved.initialize(repeating: 0.0, count: tempCapacity * 2)

        self.scratchResampled = UnsafeMutablePointer<Float>.allocate(capacity: tempCapacity * 2)
        self.scratchResampled.initialize(repeating: 0.0, count: tempCapacity * 2)
    }

    deinit {
        stop()
        tempInterleaved.deallocate()
        scratchResampled.deallocate()
    }

    public func start() {
        guard !isRunning else { return }
        lastError = nil

        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, deviceID, nil) { [weak self] inNow, inInputData, inInputTime, outOutputData, outOutputTime in
            guard let self = self else { return }
            self.processOutput(outputData: outOutputData)
        }

        guard status == noErr, let validProc = proc else {
            lastError = status
            print("Failed to create output IOProc for device \(deviceID): status \(status)")
            return
        }
        self.ioProcID = validProc

        let startStatus = AudioDeviceStart(deviceID, validProc)
        if startStatus == noErr {
            isRunning = true
        } else {
            AudioDeviceDestroyIOProcID(deviceID, validProc)
            ioProcID = nil
            lastError = startStatus
            print("Failed to start output device \(deviceID): status \(startStatus)")
        }
    }

    public func stop() {
        guard isRunning, let proc = ioProcID else { return }
        AudioDeviceStop(deviceID, proc)
        AudioDeviceDestroyIOProcID(deviceID, proc)
        ioProcID = nil
        isRunning = false
    }

    private func processOutput(outputData: UnsafeMutablePointer<AudioBufferList>) {
        let reqFrames = StereoAudioBufferIO.frameCount(outputData)
        let framesToDeliver = min(reqFrames, tempCapacity)
        guard framesToDeliver > 0 else { StereoAudioBufferIO.clear(outputData); return }

        // Secondary outputs have clocks independent from A1, including devices
        // with the same advertised rate. Always run the elastic conversion path.
        resampler.updateDrift(currentFillRatio: ringBuffer.fillRatio())
        let neededFromEngine = min(resampler.inputFrameCount(forTargetFrames: framesToDeliver), tempCapacity)
        ringBuffer.readForPlayback(into: tempInterleaved, frameCount: neededFromEngine)
        resampler.resample(
            source: tempInterleaved,
            sourceFrames: neededFromEngine,
            destination: scratchResampled,
            targetFrames: framesToDeliver
        )

        StereoAudioBufferIO.write(scratchResampled, frames: framesToDeliver, to: outputData, channelOffset: channelOffset, leftChannel: leftChannel, rightChannel: rightChannel)
    }
}
