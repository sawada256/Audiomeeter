import Foundation
import CoreAudio
import VMNative
@main struct DAWDuplexHALTests {
    static func main() {
        let deviceUID = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Audiomeeter_UID"
        var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDevices,mScope:kAudioObjectPropertyScopeGlobal,mElement:0)
        var size:UInt32=0
        precondition(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size)==noErr)
        var ids=[AudioDeviceID](repeating:0,count:Int(size)/4)
        precondition(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size,&ids)==noErr)
        let primary=ids.first { id in
            var uid:Unmanaged<CFString>?;var n=UInt32(MemoryLayout.size(ofValue:uid))
            var a=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyDeviceUID,mScope:kAudioObjectPropertyScopeGlobal,mElement:0)
            return AudioObjectGetPropertyData(id,&a,0,nil,&n,&uid)==noErr && uid.map { $0.takeRetainedValue() as String == deviceUID } == true
        }!
        guard let mirror=DAWDuplexTransport.endpoint(primary) else { fatalError("Revised full-duplex endpoint missing") }
        print("Full-duplex primary \(primary), private mixer endpoint \(mirror)");fflush(stdout)
        var procs:[AudioDeviceIOProcID]=[]
        var counters:[UnsafeMutableRawPointer]=[]
        defer {
            for (i,proc) in procs.enumerated() { AudioDeviceStop(i==0 ? primary:mirror,proc);AudioDeviceDestroyIOProcID(i==0 ? primary:mirror,proc) }
            for value in counters { vm_counter_destroy(value) }
        }
        for (i,id) in [primary,mirror].enumerated() {
            let counter=vm_counter_create()!; counters.append(counter)
            let value:Float=i==0 ? 0.000001 : -0.000002
            var proc:AudioDeviceIOProcID?
            let status=AudioDeviceCreateIOProcIDWithBlock(&proc,id,nil) { _,input,_,output,_ in
                for buffer in UnsafeMutableAudioBufferListPointer(output) {
                    if let data=buffer.mData { let samples=data.assumingMemoryBound(to:Float.self)
                        for j in 0..<Int(buffer.mDataByteSize)/4 { samples[j]=j%2==0 ? value:-value }
                    }
                }
                let first=UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating:input)).first
                if let first, let raw=first.mData,first.mDataByteSize>0 {
                    let sample=raw.assumingMemoryBound(to:Float.self)[0]
                    vm_counter_store(counter,UInt64(sample.bitPattern))
                }
            }
            precondition(status==noErr && proc != nil,"Cannot open endpoint \(id), status \(status)")
            procs.append(proc!)
            precondition(AudioDeviceStart(id,proc!)==noErr)
        }
        Thread.sleep(forTimeInterval:1)
        let capture=Float(bitPattern:UInt32(vm_counter_load(counters[0])))
        let playback=Float(bitPattern:UInt32(vm_counter_load(counters[1])))
        print("DAW capture=\(capture), mixer receives playback=\(playback)");fflush(stdout)
        precondition(abs(capture + 0.000002)<0.0000001 && playback.isFinite && abs(playback-capture)>0.0000001,"Playback and capture must remain independent")
        print("Installed HAL full-duplex signal isolation passed")
    }
}
