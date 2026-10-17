#include "VMNative.h"
#include "VMWorkerProtocol.h"
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <semaphore.h>
#include <stdatomic.h>
#include <math.h>

typedef struct {
    VMWorkerShared* shared;
    sem_t* wake;
    int fd;
    uint32_t quantum, offset, wet, fault, misses, missLimit;
    uint64_t sequence, dryPosition;
    float input[VMW_FRAMES*2], side[VMW_FRAMES*2], output[VMW_FRAMES*2];
    float* dry;
    _Atomic uint64_t late;
} VMWorkerProxy;
void* vmw_open(const char* path, const char* semaphore, int quantum, double rate) {
    if (quantum < 1 || quantum > VMW_FRAMES) return NULL;
    VMWorkerProxy* p = calloc(1, sizeof(*p)); if (!p) return NULL;
    p->fd = open(path, O_RDWR|O_CREAT|O_EXCL, 0600);
    if (p->fd < 0 || ftruncate(p->fd, sizeof(VMWorkerShared))) { if (p->fd>=0) close(p->fd); free(p); return NULL; }
    p->shared = mmap(NULL, sizeof(VMWorkerShared), PROT_READ|PROT_WRITE, MAP_SHARED, p->fd, 0);
    if (p->shared == MAP_FAILED) { close(p->fd); free(p); return NULL; }
    memset(p->shared,0,sizeof(VMWorkerShared));
    p->shared->magic=VMW_MAGIC; p->shared->quantum=quantum;
    (void)mlock(p->shared,sizeof(VMWorkerShared));
    p->wake=sem_open(semaphore,O_CREAT|O_EXCL,0600,0);
    if (p->wake==SEM_FAILED) { munmap(p->shared,sizeof(VMWorkerShared)); close(p->fd); free(p); return NULL; }
    p->quantum=quantum; p->missLimit=(uint32_t)fmax(8,ceil(rate*.25/quantum));
    p->dry=calloc((VMW_MAX_LATENCY+VMW_FRAMES+1)*2,sizeof(float));
    if (!p->dry) { sem_close(p->wake); munmap(p->shared,sizeof(VMWorkerShared));close(p->fd);free(p);return NULL; }
    return p;
}
void vmw_close(void* handle) {
    VMWorkerProxy* p=handle; if(!p)return;
    sem_close(p->wake); munlock(p->shared,sizeof(VMWorkerShared));munmap(p->shared,sizeof(VMWorkerShared));close(p->fd);free(p->dry);free(p);
}
int vmw_ready(void* handle) { VMWorkerProxy* p=handle;return p ? (int)__atomic_load_n(&p->shared->ready,__ATOMIC_ACQUIRE) : 2; }
int vmw_fault(void* handle) { VMWorkerProxy* p=handle;return p ? (int)__atomic_load_n(&p->fault,__ATOMIC_ACQUIRE) : 1; }
void vmw_set_fault(void* handle,int fault) { VMWorkerProxy* p=handle;if(p)__atomic_store_n(&p->fault,(uint32_t)fault,__ATOMIC_RELEASE); }
int vmw_latency(void* handle) { VMWorkerProxy* p=handle;return p ? p->quantum+(int)__atomic_load_n(&p->shared->latency,__ATOMIC_ACQUIRE) : 0; }
int vmw_side_channels(void* handle) { VMWorkerProxy* p=handle;return p ? (int)__atomic_load_n(&p->shared->sideChannels,__ATOMIC_ACQUIRE) : 0; }
uint64_t vmw_late(void* handle) { VMWorkerProxy* p=handle;return p ? atomic_load(&p->late) : 0; }
uint64_t vmw_editor(void* handle) { VMWorkerProxy* p=handle;return p ? __atomic_add_fetch(&p->shared->editorCommand,1,__ATOMIC_RELEASE) : 0; }
uint64_t vmw_editor_ack(void* handle) { VMWorkerProxy* p=handle;return p ? __atomic_load_n(&p->shared->editorAck,__ATOMIC_ACQUIRE) : 0; }
uint64_t vmw_snapshot(void* handle) { VMWorkerProxy* p=handle;return p ? __atomic_add_fetch(&p->shared->snapshotCommand,1,__ATOMIC_RELEASE) : 0; }
uint64_t vmw_snapshot_ack(void* handle) { VMWorkerProxy* p=handle;return p ? __atomic_load_n(&p->shared->snapshotAck,__ATOMIC_ACQUIRE) : 0; }
static void vmw_restart(VMWorkerProxy* p,uint64_t clearFrames) {
    const uint64_t dryCapacity=VMW_MAX_LATENCY+VMW_FRAMES+1;
    if(clearFrames>dryCapacity)clearFrames=dryCapacity;
    p->sequence=((p->sequence+VMW_PACKETS-1)/VMW_PACKETS)*VMW_PACKETS+VMW_PACKETS;
    p->offset=0;p->wet=0;p->dryPosition=0;p->misses=0;
    // After restart the first `delay` reads come from the end of the dry ring.
    memset(p->dry+(dryCapacity-clearFrames)*2,0,clearFrames*2*sizeof(float));
    for(int i=0;i<VMW_PACKETS;++i) {
        uint32_t state=__atomic_load_n(&p->shared->packets[i].state,__ATOMIC_ACQUIRE);
        if(state==1||state==3)__atomic_compare_exchange_n(&p->shared->packets[i].state,&state,0,0,__ATOMIC_ACQ_REL,__ATOMIC_ACQUIRE);
    }
}
void vmw_reset(void* handle) {
    VMWorkerProxy* p=handle;if(!p)return;
    vmw_restart(p,VMW_MAX_LATENCY+VMW_FRAMES+1);
}
// Render-thread variant: clears only the dry span that can be read before it is rewritten.
void vmw_resync(void* handle) {
    VMWorkerProxy* p=handle;if(!p)return;
    uint32_t intrinsic=__atomic_load_n(&p->shared->latency,__ATOMIC_ACQUIRE);
    if(intrinsic>VMW_MAX_LATENCY)intrinsic=VMW_MAX_LATENCY;
    vmw_restart(p,(uint64_t)p->quantum+intrinsic);
}
// Nonblocking RT transport. Late/crashed workers produce a latency-matched dry signal.
void vmw_process(void* handle,float* audio,const float* side,int frames) {
    VMWorkerProxy* p=handle;if(!p||frames<=0)return;
    const uint64_t dryCapacity=VMW_MAX_LATENCY+VMW_FRAMES+1;
    uint32_t intrinsic=__atomic_load_n(&p->shared->latency,__ATOMIC_ACQUIRE);
    if(intrinsic>VMW_MAX_LATENCY) { vmw_set_fault(p,4);intrinsic=VMW_MAX_LATENCY; }
    uint64_t delay=p->quantum+intrinsic;
    for(int frame=0;frame<frames;++frame) {
        if(p->offset==0) {
            p->wet=0;
            if(p->dryPosition>=p->quantum) {
                uint64_t expected=p->sequence-1;
                VMWorkerPacket* packet=&p->shared->packets[expected%VMW_PACKETS];
                if(!vmw_fault(p)&&__atomic_load_n(&packet->state,__ATOMIC_ACQUIRE)==3&&packet->sequence==expected) {
                    memcpy(p->output,packet->output,p->quantum*2*sizeof(float));
                    __atomic_store_n(&packet->state,0,__ATOMIC_RELEASE);p->wet=1;p->misses=0;
                } else if(vmw_ready(p)==1&&!vmw_fault(p)) {
                    atomic_fetch_add(&p->late,1);
                    if(++p->misses>=p->missLimit) vmw_set_fault(p,3);
                }
            }
        }
        uint32_t o=p->offset*2;
        uint64_t write=(p->dryPosition%dryCapacity)*2;
        uint64_t read=((p->dryPosition+dryCapacity-delay)%dryCapacity)*2;
        for(int channel=0;channel<2;++channel) {
            float value=audio[frame*2+channel];
            p->input[o+channel]=isfinite(value)?value:0;
            p->side[o+channel]=side?side[frame*2+channel]:0;
            p->dry[write+channel]=p->input[o+channel];
            float result=p->wet?p->output[o+channel]:p->dry[read+channel];
            audio[frame*2+channel]=isfinite(result)?result:0;
        }
        ++p->dryPosition;
        if(++p->offset==p->quantum) {
            VMWorkerPacket* packet=&p->shared->packets[p->sequence%VMW_PACKETS];
            uint32_t state=__atomic_load_n(&packet->state,__ATOMIC_ACQUIRE);
            if(state==3) { __atomic_store_n(&packet->state,0,__ATOMIC_RELEASE);state=0; }
            if(state==0&&vmw_ready(p)==1&&!vmw_fault(p)) {
                packet->sequence=p->sequence;
                memcpy(packet->input,p->input,p->quantum*2*sizeof(float));
                memcpy(packet->side,p->side,p->quantum*2*sizeof(float));
                __atomic_store_n(&packet->state,1,__ATOMIC_RELEASE);sem_post(p->wake);
            }
            ++p->sequence;p->offset=0;
        }
    }
}

void vmw_seed_latency(void* handle,int latency) { VMWorkerProxy* p=handle;if(p)__atomic_store_n(&p->shared->latency,(uint32_t)fmax(0,fmin(VMW_MAX_LATENCY,latency)),__ATOMIC_RELEASE); }

// Soft bypass keeps the worker running so latency and plugin state stay continuous.
void vmw_set_soft_bypass(void* handle,int enabled) { VMWorkerProxy* p=handle;if(p)__atomic_store_n(&p->shared->bypass,(uint32_t)(enabled?1:0),__ATOMIC_RELEASE); }
int vmw_has_bypass_parameter(void* handle) { VMWorkerProxy* p=handle;return p ? (int)__atomic_load_n(&p->shared->hasBypassParameter,__ATOMIC_ACQUIRE) : 0; }
uint32_t vmw_render_micros(void* handle) { VMWorkerProxy* p=handle;return p ? __atomic_load_n(&p->shared->renderMicros,__ATOMIC_ACQUIRE) : 0; }
uint32_t vmw_touched(void* handle,uint32_t* serial) {
    VMWorkerProxy* p=handle;if(!p){ if(serial)*serial=0; return 0; }
    if(serial)*serial=__atomic_load_n(&p->shared->touchedSerial,__ATOMIC_ACQUIRE);
    return __atomic_load_n(&p->shared->touchedParameter,__ATOMIC_ACQUIRE);
}
// Single producer (the CoreMIDI input thread). Returns 0 when the ring is full.
int vmw_midi_push(void* handle,uint32_t message) {
    VMWorkerProxy* p=handle;if(!p||__atomic_load_n(&p->shared->ready,__ATOMIC_ACQUIRE)!=1)return 0;
    uint32_t write=__atomic_load_n(&p->shared->midiWrite,__ATOMIC_RELAXED);
    uint32_t read=__atomic_load_n(&p->shared->midiRead,__ATOMIC_ACQUIRE);
    if(write-read>=VMW_MIDI_EVENTS)return 0;
    p->shared->midi[write%VMW_MIDI_EVENTS]=message;
    __atomic_store_n(&p->shared->midiWrite,write+1,__ATOMIC_RELEASE);
    return 1;
}
// Single producer (the host main thread). Returns 0 when the ring is full.
int vmw_parameter_push(void* handle,uint32_t index,float value) {
    VMWorkerProxy* p=handle;if(!p||!isfinite(value))return 0;
    uint32_t write=__atomic_load_n(&p->shared->parameterWrite,__ATOMIC_RELAXED);
    uint32_t read=__atomic_load_n(&p->shared->parameterRead,__ATOMIC_ACQUIRE);
    if(write-read>=VMW_PARAM_EVENTS)return 0;
    VMWorkerParameter* slot=&p->shared->parameters[write%VMW_PARAM_EVENTS];
    slot->index=index; slot->value=value<0?0:value>1?1:value;
    __atomic_store_n(&p->shared->parameterWrite,write+1,__ATOMIC_RELEASE);
    return 1;
}
