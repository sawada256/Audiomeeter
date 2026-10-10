import Foundation
import CoreAudio
import VMNative

@main
struct AppTrimHALTests {
    static func main() throws {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        var size: UInt32 = 0
        precondition(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr)
        var ids = [AudioDeviceID](repeating: 0, count: Int(size)/4)
        precondition(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr)
        var tested = 0
        for id in ids {
            var uid: Unmanaged<CFString>?
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
            var n = UInt32(MemoryLayout.size(ofValue: uid))
            guard AudioObjectGetPropertyData(id, &a, 0, nil, &n, &uid) == noErr, let uid else { continue }
            let text = uid.takeRetainedValue() as String
            guard ["Voicemeeter_UID", "VoicemeeterAUX_UID"].contains(text) else { continue }
            _ = try AppTrimTransport.read(id)
            let outputBytes = vm_counter_create()!
            defer { vm_counter_destroy(outputBytes) }
            let callbacks = vm_counter_create()!
            defer { vm_counter_destroy(callbacks) }
            var io: AudioDeviceIOProcID?
            let status = AudioDeviceCreateIOProcIDWithBlock(&io, id, nil) { _, _, _, output, _ in
                vm_counter_store(callbacks, vm_counter_load(callbacks) + 1)
                vm_counter_store(outputBytes, UInt64(UnsafeMutableAudioBufferListPointer(output).reduce(0) { $0 + ($1.mData != nil ? Int($1.mDataByteSize) : 0) }))
                for buffer in UnsafeMutableAudioBufferListPointer(output) {
                    if let data = buffer.mData {
                        // HAL may skip per-client processing for an exactly silent stream
                        // when another app is already playing on the same device.
                        let samples = data.assumingMemoryBound(to: Float.self)
                        for i in 0..<(Int(buffer.mDataByteSize)/MemoryLayout<Float>.stride) {
                            samples[i] = i % 2 == 0 ? 0.000001 : -0.000001
                        }
                    }
                }
            }
            precondition(status == noErr && io != nil, "Cannot create HAL test client: \(status)")
            defer { AudioDeviceStop(id, io!); AudioDeviceDestroyIOProcID(id, io!) }
            precondition(AudioDeviceStart(id, io!) == noErr)
            let pid = ProcessInfo.processInfo.processIdentifier
            let deadline = Date().addingTimeInterval(3)
            var listed = false
            while Date() < deadline {
                if try AppTrimTransport.read(id).contains(where: { $0.pid == pid }) { listed = true; break }
                Thread.sleep(forTimeInterval: 0.05)
            }
            print("Device \(text): callbacks=\(vm_counter_load(callbacks)), outputBytes=\(vm_counter_load(outputBytes)), PID=\(pid), listed=\(listed), clients=\(try AppTrimTransport.read(id).map { $0.pid }.filter { $0 > 0 })"); fflush(stdout)
            if !listed {
                var diagnosticAddress = AudioObjectPropertyAddress(mSelector: 0x766d6364, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
                var diagnostic: Unmanaged<CFTypeRef>?
                var diagnosticSize = UInt32(MemoryLayout.size(ofValue: diagnostic))
                if AudioObjectGetPropertyData(id, &diagnosticAddress, 0, nil, &diagnosticSize, &diagnostic) == noErr, let diagnostic {
                    print("Driver client diagnostics: \(diagnostic.takeRetainedValue())"); fflush(stdout)
                }
            }
            precondition(listed, "Actual output client missing from HAL list")
            precondition(AppTrimTransport.set(id, pid: pid, gain: 0.25) == noErr)
            let after = try AppTrimTransport.read(id)
            precondition(after.contains { $0.pid == pid && abs($0.gain - 0.25) < 0.001 })
            precondition(AppTrimTransport.set(id, pid: pid, gain: 1) == noErr)
            print("HAL boundary passed: \(text), active output PID, CFData list, trim set/readback/reset")
            if CommandLine.arguments.contains("--hold") && text == "VoicemeeterAUX_UID" {
                print("Holding a near-silent AUX client for UI verification"); fflush(stdout)
                Thread.sleep(forTimeInterval: 30)
            }
            tested += 1
        }
        precondition(tested == 2, "VAIO/AUX devices must be installed")
    }
}

// Keep this standalone HAL integration test independent of device-manager setup.
enum AudioConfigurationError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case let .message(text): return text } }
}
