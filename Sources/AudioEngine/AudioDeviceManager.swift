import Foundation
import CoreAudio

/// Manages macOS CoreAudio device enumeration, properties, and plug & play listeners
public final class AudioDeviceManager {
    public static let shared = AudioDeviceManager()

    public private(set) var devices: [AudioDeviceInfo] = []
    public var onDevicesChanged: (([AudioDeviceInfo]) -> Void)?

    private var deviceListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var hardwareListenerBlock: AudioObjectPropertyListenerBlock?

    public init() {
        refreshDevices()
        setupPropertyListener()
    }

    deinit {
        removePropertyListener()
    }

    public func refreshDevices() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr, dataSize > 0 else {
            self.devices = []
            return
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else {
            self.devices = []
            return
        }

        let defaultInputID = getDefaultDevice(isInput: true)
        let defaultOutputID = getDefaultDevice(isInput: false)

        var newDevices: [AudioDeviceInfo] = []
        for id in deviceIDs {
            guard let info = queryDeviceInfo(id: id, defaultIn: defaultInputID, defaultOut: defaultOutputID) else {
                continue
            }
            newDevices.append(info)
        }

        self.devices = newDevices
        updateDeviceListeners()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onDevicesChanged?(self.devices)
        }
    }

    public func getInputDevices() -> [AudioDeviceInfo] {
        return devices.filter { $0.inChannels > 0 }
    }

    public func getOutputDevices() -> [AudioDeviceInfo] {
        return devices.filter { $0.outChannels > 0 }
    }

    public func findDevice(byUID uid: String) -> AudioDeviceInfo? {
        return devices.first { $0.uid == uid }
    }

    public func findDevice(byID id: AudioObjectID) -> AudioDeviceInfo? {
        return devices.first { $0.id == id }
    }

    public func getDeviceSampleRate(id: AudioObjectID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate: Float64 = 48000.0
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &sampleRate)
        return status == noErr ? Double(sampleRate) : 48000.0
    }

    public func getDeviceBufferSize(id: AudioObjectID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var frames: UInt32 = 256
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &frames)
        return status == noErr ? frames : 256
    }

    // MARK: macOS default output and device volume

    public func defaultOutputDeviceID() -> AudioObjectID { getDefaultDevice(isInput: false) }

    /// Same as choosing the output in Control Center / System Settings > Sound.
    public func setDefaultOutputDevice(id: AudioObjectID) throws {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value = id
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &value)
        guard status == noErr else { throw AudioConfigurationError.message(L10n.text("出力先を変更できませんでした (OSStatus {0})。", [String(status)])) }
    }

    /// The device's own output volume (the macOS volume slider for that device). It is applied
    /// by the device/driver to everything played through it, Audiomeeter's buses included.
    /// Elements: the main control when present, otherwise the preferred stereo channels.
    private func volumeElements(id: AudioObjectID, selector: AudioObjectPropertySelector) -> [UInt32] {
        func settable(_ element: UInt32) -> Bool {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var flag: DarwinBoolean = false
            return AudioObjectHasProperty(id, &address) && AudioObjectIsPropertySettable(id, &address, &flag) == noErr && flag.boolValue
        }
        if settable(kAudioObjectPropertyElementMain) { return [kAudioObjectPropertyElementMain] }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyPreferredChannelsForStereo, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var stereo: [UInt32] = [1, 2], size = UInt32(MemoryLayout<UInt32>.size * 2)
        _ = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &stereo)
        return Array(Set(stereo)).sorted().filter(settable)
    }
    /// 0...1, or nil when the device has no software volume control (common for audio interfaces).
    public func outputVolume(id: AudioObjectID) -> Float? {
        let elements = volumeElements(id: id, selector: kAudioDevicePropertyVolumeScalar)
        guard !elements.isEmpty else { return nil }
        let values: [Float] = elements.compactMap { element in
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var value: Float32 = 0, size = UInt32(MemoryLayout<Float32>.size)
            return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
        }
        return values.isEmpty ? nil : values.reduce(0, +) / Float(values.count)
    }
    @discardableResult
    public func setOutputVolume(id: AudioObjectID, _ volume: Float) -> Bool {
        var value = Float32(min(1, max(0, volume.isFinite ? volume : 0)))
        var ok = false
        for element in volumeElements(id: id, selector: kAudioDevicePropertyVolumeScalar) {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            ok = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr || ok
        }
        return ok
    }
    public func outputMuted(id: AudioObjectID) -> Bool? {
        guard let element = volumeElements(id: id, selector: kAudioDevicePropertyMute).first else { return nil }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
        var value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value != 0 : nil
    }
    public func setOutputMuted(id: AudioObjectID, _ muted: Bool) {
        var value: UInt32 = muted ? 1 : 0
        for element in volumeElements(id: id, selector: kAudioDevicePropertyMute) {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        }
    }

    /// Output-side device latency in frames: device + safety offset + one IO buffer.
    public func deviceLatency(id: AudioObjectID) -> Int {
        var total = 0
        for selector in [kAudioDevicePropertyLatency, kAudioDevicePropertySafetyOffset] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr { total += Int(value) }
        }
        return total + Int(getDeviceBufferSize(id: id))
    }

    public func setDeviceBufferSize(id: AudioObjectID, frames: UInt32) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var newFrames = frames
        let size = UInt32(MemoryLayout<UInt32>.size)
        guard frames >= 32, frames <= 4096 else { throw AudioConfigurationError.message("Buffer must be between 32 and 4096 frames.") }
        let status = AudioObjectSetPropertyData(id, &address, 0, nil, size, &newFrames)
        guard status == noErr else { throw AudioConfigurationError.message("Device rejected buffer size (OSStatus \(status)).") }
    }

    public func setDeviceSampleRate(id: AudioObjectID, rate: Double) throws {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value = rate
        let status = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Double>.size), &value)
        guard status == noErr else { throw AudioConfigurationError.message("Device rejected sample rate (OSStatus \(status)).") }
    }

    private func getDefaultDevice(isInput: Bool) -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: isInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    private func queryDeviceInfo(id: AudioObjectID, defaultIn: AudioObjectID, defaultOut: AudioObjectID) -> AudioDeviceInfo? {
        // Query Name
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nameCF: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<CFString?>.size)
        let nameStatus = AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &nameCF)
        guard nameStatus == noErr, let cf = nameCF else {
            return nil
        }
        let name = cf.takeRetainedValue() as String

        // Query UID
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uidCF: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<CFString?>.size)
        var uid = "\(id)"
        if AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, &uidCF) == noErr, let ucf = uidCF {
            uid = ucf.takeRetainedValue() as String
        }

        // Query Input Channels
        var inChannels = 0
        var inScope = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var inSize: UInt32 = 0
        if AudioObjectGetPropertyDataSize(id, &inScope, 0, nil, &inSize) == noErr && inSize > 0 {
            let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(inSize))
            if AudioObjectGetPropertyData(id, &inScope, 0, nil, &inSize, bufferList) == noErr {
                let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
                for buf in buffers {
                    inChannels += Int(buf.mNumberChannels)
                }
            }
            bufferList.deallocate()
        }

        // Query Output Channels
        var outChannels = 0
        var outScope = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var outSize: UInt32 = 0
        if AudioObjectGetPropertyDataSize(id, &outScope, 0, nil, &outSize) == noErr && outSize > 0 {
            let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(outSize))
            if AudioObjectGetPropertyData(id, &outScope, 0, nil, &outSize, bufferList) == noErr {
                let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
                for buf in buffers {
                    outChannels += Int(buf.mNumberChannels)
                }
            }
            bufferList.deallocate()
        }

        let sampleRate = getDeviceSampleRate(id: id)

        return AudioDeviceInfo(
            id: id,
            name: name,
            uid: uid,
            inChannels: inChannels,
            outChannels: outChannels,
            sampleRate: sampleRate,
            isDefaultInput: id == defaultIn,
            isDefaultOutput: id == defaultOut
        )
    }

    private func updateDeviceListeners() {
        for (id, address, block) in deviceListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(id, &address, .main, block)
        }
        deviceListeners.removeAll()
        for device in devices {
            for selector in [kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyBufferFrameSize] {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refreshDevices() }
                if AudioObjectAddPropertyListenerBlock(device.id, &address, .main, block) == noErr {
                    deviceListeners.append((device.id, address, block))
                }
            }
        }
    }

    private func setupPropertyListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        hardwareListenerBlock = { [weak self] _, _ in
            self?.refreshDevices()
        }

        if let block = hardwareListenerBlock {
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
        }
    }

    private func removePropertyListener() {
        for (id, address, block) in deviceListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(id, &address, .main, block)
        }
        deviceListeners.removeAll()
        if let block = hardwareListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
            hardwareListenerBlock = nil
        }
    }
}

public enum AudioConfigurationError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
