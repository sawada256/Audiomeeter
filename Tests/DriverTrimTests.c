#include <assert.h>
#include "../Drivers/BlackHoleCore.c"
static OSStatus setTrim(AudioObjectPropertyAddress* address, VMClientValue trim) {
    CFDataRef payload = CFDataCreate(NULL, (const UInt8*)&trim, sizeof(trim));
    OSStatus status = BlackHole_SetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Device, 1001, address, 0, NULL, sizeof(payload), &payload);
    CFRelease(payload); return status;
}
int main(void) {
    AudioObjectPropertyAddress custom = {kAudioObjectPropertyCustomPropertyInfoList, kAudioObjectPropertyScopeGlobal, 0};
    AudioServerPlugInCustomPropertyInfo info[3]; UInt32 infoSize = sizeof(info);
    assert(BlackHole_GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Device, 1001, &custom, 0, NULL, infoSize, &infoSize, info) == 0);
    assert(info[0].mPropertyDataType == kAudioServerPlugInCustomPropertyDataTypeCFPropertyList);
    assert(info[1].mPropertyDataType == kAudioServerPlugInCustomPropertyDataTypeCFPropertyList);

    AudioServerPlugInClientInfo client = {0};
    client.mClientID = 0; client.mProcessID = 1001;
    assert(BlackHole_AddDeviceClient(gAudioServerPlugInDriverRef, kObjectID_Device, &client) == 0);
    AudioObjectPropertyAddress address = {VM_CLIENT_TRIM, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    VMClientValue trim = {1001, 0.5f};
    assert(setTrim(&address, trim) == 0);
    AudioServerPlugInClientInfo mirror = client; mirror.mProcessID = 2002;
    assert(BlackHole_AddDeviceClient(gAudioServerPlugInDriverRef, kObjectID_Device2, &mirror) == 0);
    assert(BlackHole_AddDeviceClient(gAudioServerPlugInDriverRef, kObjectID_Device, &client) == 0);
    assert(BlackHole_RemoveDeviceClient(gAudioServerPlugInDriverRef, kObjectID_Device2, &mirror) == 0);
    assert(setTrim(&address, trim) == 0); // removing mirror ID 0 must preserve primary ID 0
    Float32 audio[8] = {0.8f, -0.8f, 0.4f, -0.4f, 0.2f, -0.2f, 0.1f, -0.1f};
    AudioServerPlugInIOCycleInfo cycle = {0};
    assert(BlackHole_DoIOOperation(gAudioServerPlugInDriverRef, kObjectID_Device, kObjectID_Stream_Output, 0, kAudioServerPlugInIOOperationProcessOutput, 4, &cycle, audio, NULL) == 0);
    assert(fabsf(audio[0] - 0.4f) < 0.00001f && fabsf(audio[1] + 0.4f) < 0.00001f);
    Boolean doesIO = false, inPlace = false;
    assert(BlackHole_WillDoIOOperation(gAudioServerPlugInDriverRef, kObjectID_Device, 0, kAudioServerPlugInIOOperationProcessOutput, &doesIO, &inPlace) == 0 && doesIO && inPlace);
    address.mSelector = VM_CLIENT_LIST;
    assert(BlackHole_HasProperty(gAudioServerPlugInDriverRef, kObjectID_Device, 1001, &address));
    CFDataRef payload = NULL; UInt32 size = sizeof(payload);
    assert(BlackHole_GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Device, 1001, &address, 0, NULL, size, &size, &payload) == 0);
    assert(size == sizeof(CFDataRef) && CFDataGetLength(payload) == sizeof(VMClientValue) * VM_CLIENT_COUNT);
    VMClientValue first; memcpy(&first, CFDataGetBytePtr(payload), sizeof(first));
    assert(first.pid == 1001 && first.gain == 0.5f); CFRelease(payload);
    address.mSelector = VM_CLIENT_TRIM;
    CFStringRef invalid = CFSTR("wrong type");
    assert(BlackHole_SetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Device, 1001, &address, 0, NULL, sizeof(invalid), &invalid) != 0);
    CFDataRef shortData = CFDataCreate(NULL, (const UInt8*)&trim, 1);
    assert(BlackHole_SetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Device, 1001, &address, 0, NULL, sizeof(shortData), &shortData) != 0);
    CFRelease(shortData);
    address.mSelector = VM_CLIENT_TRIM; trim.gain = NAN;
    assert(setTrim(&address, trim) != 0);
    assert(BlackHole_RemoveDeviceClient(gAudioServerPlugInDriverRef, kObjectID_Device, &client) == 0);
    trim.gain = 1;
    assert(setTrim(&address, trim) != 0);
    // HAL registers idle clients and mirror endpoints before actual output clients.
    for (UInt32 i=1; i<=100; ++i) {
        AudioServerPlugInClientInfo idle = {0}; idle.mClientID = i; idle.mProcessID = 4000+i;
        assert(BlackHole_AddDeviceClient(gAudioServerPlugInDriverRef, kObjectID_Device, &idle) == 0);
    }
    AudioServerPlugInClientInfo late = {0}; late.mClientID = 1000; late.mProcessID = 9001;
    assert(BlackHole_AddDeviceClient(gAudioServerPlugInDriverRef, kObjectID_Device, &late) == 0);
    trim.pid = 9001; trim.gain = 0.25f;
    assert(setTrim(&address, trim) == 0);
    audio[0] = 0.8f;
    assert(BlackHole_DoIOOperation(gAudioServerPlugInDriverRef, kObjectID_Device, kObjectID_Stream_Output, 1000, kAudioServerPlugInIOOperationProcessOutput, 4, &cycle, audio, NULL) == 0);
    assert(fabsf(audio[0] - 0.2f) < 0.00001f);
    address.mSelector = VM_CLIENT_LIST; payload = NULL; size = sizeof(payload);
    assert(BlackHole_GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Device, 1001, &address, 0, NULL, size, &size, &payload) == 0);
    memcpy(&first, CFDataGetBytePtr(payload), sizeof(first));
    assert(first.pid == 9001 && first.gain == 0.25f); CFRelease(payload);
    puts("Driver trim tests passed: client ID zero, pre-mix gain, active list, invalid gain, disconnect");
    return 0;
}
