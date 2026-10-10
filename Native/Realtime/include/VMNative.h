#pragma once
#include <stdint.h>
#include "VMWorkerProtocol.h"
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
void* vm_counter_create(void);
void vm_counter_destroy(void* counter);
uint64_t vm_counter_load(void* counter);
void vm_counter_store(void* counter, uint64_t value);
int vm_host_load(const char* path);
void* vm_plugin_create(const char* path, double rate, int block, char* error, int errorSize);
const char* vm_plugin_scan(const char* path);
void* vm_plugin_create_named(const char* path, const char* identifier, double rate, int block, char* error, int errorSize);
void vm_plugin_destroy(void* plugin);
void vm_plugin_prepare(void* plugin, double rate, int block);
void vm_plugin_process(void* plugin, float* interleaved, int frames);
int vm_plugin_latency(void* plugin);
void vm_plugin_editor(void* plugin);
const char* vm_plugin_name(void* plugin);
const char* vm_plugin_state(void* plugin);
void vm_plugin_restore(void* plugin, const char* state);
#ifdef __cplusplus
}
#endif
// Wire format shared with the HAL driver's vmcl/vmtr properties.
typedef struct { int32_t pid; float gain; } VMAppClient;
#ifdef __cplusplus
extern "C" {
#endif
void* vmw_open(const char* path,const char* semaphore,int quantum,double rate);
void vmw_close(void* handle);
int vmw_ready(void* handle);
int vmw_fault(void* handle);
void vmw_set_fault(void* handle,int fault);
int vmw_latency(void* handle);
int vmw_side_channels(void* handle);
uint64_t vmw_late(void* handle);
uint64_t vmw_editor(void* handle);
uint64_t vmw_editor_ack(void* handle);
uint64_t vmw_snapshot(void* handle);
uint64_t vmw_snapshot_ack(void* handle);
void vmw_seed_latency(void*, int);
void vmw_reset(void* handle);
void vmw_process(void* handle,float* audio,const float* side,int frames);
#ifdef __cplusplus
}
#endif
