#include <assert.h>
#define VM_DAW_DUPLEX 1
#include "../Drivers/BlackHoleCore.c"
int main(void) {
    AudioObjectPropertyAddress address={VM_DUPLEX_UID,kAudioObjectPropertyScopeGlobal,0};
    assert(BlackHole_HasProperty(gAudioServerPlugInDriverRef,kObjectID_Device,0,&address));
    CFStringRef uid=NULL;UInt32 size=sizeof(uid);
    assert(!BlackHole_GetPropertyData(gAudioServerPlugInDriverRef,kObjectID_Device,0,&address,0,NULL,size,&size,&uid));
    assert(CFEqual(uid,get_device2_uid()));CFRelease(uid);
    assert(!BlackHole_StartIO(gAudioServerPlugInDriverRef,kObjectID_Device,0));
    assert(!BlackHole_StartIO(gAudioServerPlugInDriverRef,kObjectID_Device2,0));
    for(int test=0;test<2;++test) {
        AudioServerPlugInIOCycleInfo cycle={0};cycle.mOutputTime.mSampleTime=cycle.mInputTime.mSampleTime=test?65534:512;
        float playback[8]={.1f,-.1f,.2f,-.2f,.3f,-.3f,.4f,-.4f};
        float capture[8]={.7f,-.7f,.6f,-.6f,.5f,-.5f,.8f,-.8f},actual[8];
        assert(!BlackHole_DoIOOperation(gAudioServerPlugInDriverRef,kObjectID_Device,kObjectID_Stream_Output,0,kAudioServerPlugInIOOperationWriteMix,4,&cycle,playback,NULL));
        assert(!BlackHole_DoIOOperation(gAudioServerPlugInDriverRef,kObjectID_Device2,kObjectID_Stream_Output,0,kAudioServerPlugInIOOperationWriteMix,4,&cycle,capture,NULL));
        assert(!BlackHole_DoIOOperation(gAudioServerPlugInDriverRef,kObjectID_Device,kObjectID_Stream_Input,0,kAudioServerPlugInIOOperationReadInput,4,&cycle,actual,NULL));
        assert(!memcmp(actual,capture,sizeof(actual)));
        assert(!BlackHole_DoIOOperation(gAudioServerPlugInDriverRef,kObjectID_Device2,kObjectID_Stream_Input,0,kAudioServerPlugInIOOperationReadInput,4,&cycle,actual,NULL));
        assert(!memcmp(actual,playback,sizeof(actual)));
    }
    assert(!BlackHole_StopIO(gAudioServerPlugInDriverRef,kObjectID_Device,0));
    assert(!BlackHole_StopIO(gAudioServerPlugInDriverRef,kObjectID_Device2,0));
    assert(!gRingBuffer&&!gReturnRingBuffer);
    puts("Full-duplex playback/capture independence and ring wrap passed");
}
