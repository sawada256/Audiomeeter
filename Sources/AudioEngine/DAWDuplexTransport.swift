import Foundation
import CoreAudio

/// A driver-advertised private mixer endpoint keeps DAW playback and capture independent.
enum DAWDuplexTransport {
    static func endpoint(_ device: AudioDeviceID) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: 0x766d6470, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var raw: Unmanaged<CFTypeRef>?
        var size = UInt32(MemoryLayout.size(ofValue: raw))
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &raw) == noErr, let raw else { return nil }
        let object = raw.takeRetainedValue()
        guard CFGetTypeID(object) == CFStringGetTypeID() else { return nil }
        var uid = Unmanaged.passUnretained(object).toOpaque()
        address.mSelector = kAudioHardwarePropertyTranslateUIDToDevice
        var result: AudioDeviceID = 0; size = UInt32(MemoryLayout.size(ofValue: result))
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout.size(ofValue: uid)), &uid, &size, &result)
        return status == noErr && result != 0 ? result : nil
    }
}
