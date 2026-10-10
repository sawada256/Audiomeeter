#include <juce_audio_utils/juce_audio_utils.h>
#include "../Realtime/include/VMWorkerProtocol.h"
#include <fcntl.h>
#include <sys/mman.h>
#include <semaphore.h>
#include <unistd.h>
#include <atomic>
#include <sys/event.h>
#include <pthread.h>
#include <thread>
using namespace juce;
extern "C" {
void* vm_juce_create_named(const char*,const char*,double,int,char*,int);
void vm_juce_destroy(void*);
void vm_juce_process_side(void*,float*,const float*,int);
void vm_juce_editor(void*);
void vm_juce_hide_editor(void*);
void vm_return_focus_to_parent(int);
const char* vm_juce_name(void*);
const char* vm_juce_state(void*);
void vm_juce_restore(void*,const char*);
int vm_juce_latency(void*);
int vm_juce_side_channels(void*);
int vm_juce_editor_visible(void*);
}
class PluginWorker final : public JUCEApplication, private Timer {
    void* plugin=nullptr;
    VMWorkerShared* shared=nullptr;
    sem_t* wake=SEM_FAILED;
    int fd=-1;
    File metadata;
    std::thread audio;
    std::atomic<bool> quitting{false};
    uint64_t editorSeen=0, snapshotSeen=0;
    int snapshots=0;
    bool editorWasVisible=false;
public:
    const String getApplicationName() override { return "Voicemeeter Plugin"; }
    const String getApplicationVersion() override { return "1.2.0"; }
    bool moreThanOneInstanceAllowed() override { return true; }
    void initialise(const String& arguments) override {
        StringArray args; args.addTokens(arguments,true); args.trim();
        if(args.size()!=1) { quit();return; }
        auto config=JSON::parse(File(args[0].unquoted()));
        metadata=File(config["metadata"].toString());
        const int parent=(int)config["parentPID"];
        std::thread([parent] {
            int queue=kqueue(); struct kevent event;
            EV_SET(&event,parent,EVFILT_PROC,EV_ADD|EV_ENABLE,NOTE_EXIT,0,nullptr);
            if(queue>=0 && kevent(queue,&event,1,nullptr,0,nullptr)==0) {
                if(getppid()!=parent) _exit(0);
                if(kevent(queue,nullptr,0,&event,1,nullptr)>0) _exit(0);
            }
            if(queue>=0)close(queue);
        }).detach();
        fd=open(config["shared"].toString().toRawUTF8(),O_RDWR);
        if(fd<0) { quit();return; }
        shared=static_cast<VMWorkerShared*>(mmap(nullptr,sizeof(VMWorkerShared),PROT_READ|PROT_WRITE,MAP_SHARED,fd,0));
        if(shared==MAP_FAILED || shared->magic!=VMW_MAGIC || shared->quantum>VMW_FRAMES) { shared=nullptr;quit();return; }
        wake=sem_open(config["semaphore"].toString().toRawUTF8(),0);
        if(wake==SEM_FAILED) { quit();return; }
        char error[1024]={0};
        plugin=vm_juce_create_named(config["path"].toString().toRawUTF8(),config["identifier"].toString().toRawUTF8(),(double)config["rate"],shared->quantum,error,sizeof(error));
        if(!plugin) {
            auto* result=new DynamicObject();result->setProperty("error",String::fromUTF8(error));
            metadata.replaceWithText(JSON::toString(var(result)));
            __atomic_store_n(&shared->ready,2,__ATOMIC_RELEASE); quit();return;
        }
        auto state=config["state"].toString();if(state.isNotEmpty())vm_juce_restore(plugin,state.toRawUTF8());
        int latency=vm_juce_latency(plugin);
        if(latency<0||latency>VMW_MAX_LATENCY) { __atomic_store_n(&shared->ready,2,__ATOMIC_RELEASE);quit();return; }
        __atomic_store_n(&shared->latency,(uint32_t)latency,__ATOMIC_RELEASE);
        __atomic_store_n(&shared->sideChannels,(uint32_t)vm_juce_side_channels(plugin),__ATOMIC_RELEASE);
        saveState();
        audio=std::thread([this] { render(); });
        __atomic_store_n(&shared->ready,1,__ATOMIC_RELEASE);
        startTimer(100);
    }
    void render() {
        pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
        while(!quitting.load()) {
            if(sem_wait(wake)!=0)continue;
            if(quitting.load())break;
            VMWorkerPacket* next=nullptr;
            for(auto& packet:shared->packets) {
                if(__atomic_load_n(&packet.state,__ATOMIC_ACQUIRE)==1 && (!next||packet.sequence<next->sequence))next=&packet;
            }
            if(!next)continue;
            uint32_t submitted=1;
            if(!__atomic_compare_exchange_n(&next->state,&submitted,2,false,__ATOMIC_ACQ_REL,__ATOMIC_ACQUIRE))continue;
            memcpy(next->output,next->input,shared->quantum*2*sizeof(float));
            vm_juce_process_side(plugin,next->output,next->side,shared->quantum);
            int latency=vm_juce_latency(plugin);
            __atomic_store_n(&shared->latency,(uint32_t)jmax(0,latency),__ATOMIC_RELEASE);
            __atomic_store_n(&next->state,3,__ATOMIC_RELEASE);
        }
    }
    void saveState() {
        auto* result=new DynamicObject();
        result->setProperty("name",String::fromUTF8(vm_juce_name(plugin)));
        result->setProperty("state",String::fromUTF8(vm_juce_state(plugin)));
        metadata.replaceWithText(JSON::toString(var(result)));
    }
    void timerCallback() override {
        auto editor=__atomic_load_n(&shared->editorCommand,__ATOMIC_ACQUIRE);
        if(editor!=editorSeen) { Process::makeForegroundProcess();vm_juce_editor(plugin); editorSeen=editor; __atomic_store_n(&shared->editorAck,editor,__ATOMIC_RELEASE); }
        auto snapshot=__atomic_load_n(&shared->snapshotCommand,__ATOMIC_ACQUIRE);
        const bool visible=vm_juce_editor_visible(plugin);
        if(editorWasVisible && !visible) vm_return_focus_to_parent((int)getppid());
        if(snapshot!=snapshotSeen || (visible && ++snapshots>=20) || (editorWasVisible && !visible)) {
            snapshots=0;saveState();snapshotSeen=snapshot;
            __atomic_store_n(&shared->snapshotAck,snapshot,__ATOMIC_RELEASE);
        }
        editorWasVisible=visible;
    }
    void shutdown() override {
        stopTimer();quitting=true;
        if(wake!=SEM_FAILED)sem_post(wake);
        if(audio.joinable())audio.join();
        if(plugin)vm_juce_destroy(plugin);
        if(wake!=SEM_FAILED)sem_close(wake);
        if(shared)munmap(shared,sizeof(VMWorkerShared));
        if(fd>=0)close(fd);
    }
    void systemRequestedQuit() override { if(plugin)vm_juce_hide_editor(plugin); }
};
START_JUCE_APPLICATION(PluginWorker)
