#pragma once
#include <stdint.h>
#define VMW_FRAMES 4096
#define VMW_PACKETS 4
#define VMW_MAX_LATENCY 262144
#define VMW_MIDI_EVENTS 512
#define VMW_PARAM_EVENTS 256
#define VMW_MAGIC UINT64_C(0x564d57524b303032)
// Atomic accesses use Clang __atomic builtins in both C and C++ (same ABI).
typedef struct {
    uint64_t sequence;
    uint32_t state; // 0 free, 1 submitted, 2 processing, 3 complete
    uint32_t reserved;
    float input[VMW_FRAMES*2];
    float side[VMW_FRAMES*2];
    float output[VMW_FRAMES*2];
} VMWorkerPacket;
typedef struct { uint32_t index; float value; } VMWorkerParameter;
typedef struct {
    uint64_t magic;
    uint32_t quantum, ready; // 0 loading, 1 ready, 2 failed
    uint32_t latency, sideChannels;
    uint64_t editorCommand, snapshotCommand, snapshotAck, editorAck;
    uint32_t bypass;             // host -> worker: 1 = latency-preserving (soft) bypass
    uint32_t hasBypassParameter; // worker -> host: plugin exposes a VST3 bypass parameter
    uint32_t renderMicros;       // worker -> host: last processing time
    uint32_t touchedSerial;      // worker -> host: increments when the plugin UI changes a parameter
    uint32_t touchedParameter;
    uint32_t midiWrite, midiRead; // SPSC: host MIDI thread -> worker render thread
    uint32_t midi[VMW_MIDI_EVENTS]; // status | data1 << 8 | data2 << 16
    uint32_t parameterWrite, parameterRead; // SPSC: host main thread -> worker render thread
    VMWorkerParameter parameters[VMW_PARAM_EVENTS];
    VMWorkerPacket packets[VMW_PACKETS];
} VMWorkerShared;
