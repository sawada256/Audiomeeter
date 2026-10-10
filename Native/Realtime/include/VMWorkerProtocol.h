#pragma once
#include <stdint.h>
#define VMW_FRAMES 4096
#define VMW_PACKETS 4
#define VMW_MAX_LATENCY 262144
#define VMW_MAGIC UINT64_C(0x564d57524b303031)
// Atomic accesses use Clang __atomic builtins in both C and C++ (same ABI).
typedef struct {
    uint64_t sequence;
    uint32_t state; // 0 free, 1 submitted, 2 processing, 3 complete
    uint32_t reserved;
    float input[VMW_FRAMES*2];
    float side[VMW_FRAMES*2];
    float output[VMW_FRAMES*2];
} VMWorkerPacket;
typedef struct {
    uint64_t magic;
    uint32_t quantum, ready; // 0 loading, 1 ready, 2 failed
    uint32_t latency, sideChannels;
    uint64_t editorCommand, snapshotCommand, snapshotAck, editorAck;
    VMWorkerPacket packets[VMW_PACKETS];
} VMWorkerShared;
