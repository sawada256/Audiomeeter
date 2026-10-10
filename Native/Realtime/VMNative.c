#include "VMNative.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <dlfcn.h>
void* vm_counter_create(void) { return calloc(1, sizeof(_Atomic uint64_t)); }
void vm_counter_destroy(void* p) { free(p); }
uint64_t vm_counter_load(void* p) { return atomic_load_explicit((_Atomic uint64_t*)p, memory_order_acquire); }
void vm_counter_store(void* p, uint64_t v) { atomic_store_explicit((_Atomic uint64_t*)p, v, memory_order_release); }
static void* host;
static const char* (*scan_fn)(const char*);
static void* (*create_named_fn)(const char*, const char*, double, int, char*, int);
static void* (*create_fn)(const char*, double, int, char*, int);
static void (*destroy_fn)(void*), (*prepare_fn)(void*, double, int), (*process_fn)(void*, float*, int), (*editor_fn)(void*), (*restore_fn)(void*, const char*);
static int (*latency_fn)(void*);
static const char* (*name_fn)(void*);
static const char* (*state_fn)(void*);
int vm_host_load(const char* path) {
    if (host) return 1;
    void* candidate = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!candidate) return 0;
#define LOAD(fn, symbol) fn = dlsym(candidate, symbol); if (!fn) { dlclose(candidate); return 0; }
    LOAD(scan_fn, "vm_juce_scan") LOAD(create_named_fn, "vm_juce_create_named")
    LOAD(create_fn, "vm_juce_create") LOAD(destroy_fn, "vm_juce_destroy")
    LOAD(prepare_fn, "vm_juce_prepare") LOAD(process_fn, "vm_juce_process")
    LOAD(latency_fn, "vm_juce_latency") LOAD(editor_fn, "vm_juce_editor")
    LOAD(name_fn, "vm_juce_name") LOAD(state_fn, "vm_juce_state") LOAD(restore_fn, "vm_juce_restore")
    host = candidate;
    return 1;
}
void* vm_plugin_create(const char* p, double r, int b, char* e, int n) { return host ? create_fn(p,r,b,e,n) : NULL; }
void vm_plugin_destroy(void* p) { if (host && p) destroy_fn(p); }
void vm_plugin_prepare(void* p, double r, int b) { if (host && p) prepare_fn(p,r,b); }
void vm_plugin_process(void* p, float* a, int n) { if (host && p) process_fn(p,a,n); }
int vm_plugin_latency(void* p) { return host && p ? latency_fn(p) : 0; }
void vm_plugin_editor(void* p) { if (host && p) editor_fn(p); }
const char* vm_plugin_name(void* p) { return host && p ? name_fn(p) : "Unavailable"; }
const char* vm_plugin_state(void* p) { return host && p ? state_fn(p) : ""; }
void vm_plugin_restore(void* p, const char* s) { if (host && p) restore_fn(p,s); }

const char* vm_plugin_scan(const char* p) { return host ? scan_fn(p) : "[]"; }
void* vm_plugin_create_named(const char* p, const char* id, double r, int b, char* e, int n) { return host ? create_named_fn(p,id,r,b,e,n) : NULL; }
