import Foundation
import CoreAudio
import VMNative

/// HAL custom properties only marshal CFStrings or property lists across processes.
/// Keep the fixed-size client wire records inside CFData (a property-list type).
enum AppTrimTransport {
    static func read(_ device: AudioDeviceID) throws -> [VMAppClient] {
        var address = AudioObjectPropertyAddress(mSelector: 0x766d636c, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        guard AudioObjectHasProperty(device, &address) else {
            throw AudioConfigurationError.message(L10n.text("選択したデバイスがアプリ別トリムを公開していません。更新ドライバの適用とCore Audioの再起動を確認してください。"))
        }
        var raw: Unmanaged<CFTypeRef>?
        var size = UInt32(MemoryLayout.size(ofValue: raw))
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &raw)
        guard status == noErr, let raw else {
            throw AudioConfigurationError.message(L10n.text("アプリ一覧の取得に失敗しました (OSStatus {0})。", [String(describing: status)]))
        }
        let object = raw.takeRetainedValue()
        guard CFGetTypeID(object) == CFDataGetTypeID() else {
            throw AudioConfigurationError.message(L10n.text("ドライバのアプリ一覧形式が対応していません。"))
        }
        let payload = unsafeBitCast(object, to: CFData.self)
        let length = CFDataGetLength(payload)
        let stride = MemoryLayout<VMAppClient>.stride
        guard length % stride == 0, length <= 64 * stride, let bytes = CFDataGetBytePtr(payload) else {
            throw AudioConfigurationError.message(L10n.text("ドライバのアプリ一覧データが不正です。"))
        }
        return (0..<(length / stride)).map { UnsafeRawPointer(bytes).loadUnaligned(fromByteOffset: $0 * stride, as: VMAppClient.self) }
    }

    static func set(_ device: AudioDeviceID, pid: Int32, gain: Float) -> OSStatus {
        guard gain.isFinite, gain >= 0, gain <= 2 else { return kAudioHardwareIllegalOperationError }
        var value = VMAppClient(pid: pid, gain: gain)
        let data = withUnsafeBytes(of: &value) { CFDataCreate(nil, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)! }
        var raw = Unmanaged.passUnretained(data).toOpaque()
        var address = AudioObjectPropertyAddress(mSelector: 0x766d7472, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout.size(ofValue: raw)), &raw)
    }
}
