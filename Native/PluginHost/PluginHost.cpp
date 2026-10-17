#include <juce_audio_utils/juce_audio_utils.h>
#include <cstring>
using namespace juce;
extern "C" void vm_configure_editor_clicks(void*,void*);
extern "C" void vm_release_editor_commands(void*);
namespace {
constexpr int capacity = 4096;
struct EditorContent final : Component, private ComponentListener {
    std::unique_ptr<AudioProcessorEditor> editor;
    bool layingOut=false;
    explicit EditorContent(AudioProcessorEditor* e) : editor(e) {
        addAndMakeVisible(*editor);
        setSize(editor->getWidth(),editor->getHeight());
        editor->addComponentListener(this);
    }
    ~EditorContent() override { editor->removeComponentListener(this); }
    void resized() override {
        const ScopedValueSetter<bool> guard(layingOut,true);
        editor->setBounds(0,0,getWidth(),jmax(1,getHeight()));
    }
    void componentMovedOrResized(Component&,bool,bool resizedEditor) override {
        if(resizedEditor && !layingOut) setSize(editor->getWidth(),editor->getHeight());
    }
};
struct EditorWindow final : DocumentWindow {
    explicit EditorWindow(AudioProcessorEditor* editor)
        : DocumentWindow("VST3 - " + editor->getAudioProcessor()->getName(), Colours::darkgrey, DocumentWindow::allButtons) {
        auto* content=new EditorContent(editor);
        setUsingNativeTitleBar(true); setContentOwned(content,true);
        centreWithSize(content->getWidth(),content->getHeight()); setVisible(true);
    }
    void closeButtonPressed() override { setVisible(false); }
    bool keyPressed(const KeyPress& key) override {
        if(key.getModifiers().isCommandDown() && (key.getKeyCode()=='w' || key.getKeyCode()=='W')) { setVisible(false);return true; }
        return DocumentWindow::keyPressed(key);
    }
};
struct TouchListener final : AudioProcessorListener {
    void (*callback)(void*, int) = nullptr;
    void* context = nullptr;
    void audioProcessorParameterChanged(AudioProcessor*, int index, float) override { if (callback) callback(context, index); }
    void audioProcessorChanged(AudioProcessor*, const ChangeDetails&) override {}
};
struct Plugin {
    std::unique_ptr<AudioPluginInstance> instance;
    std::unique_ptr<EditorWindow> editor;
    AudioBuffer<float> buffer;
    MidiBuffer midi;
    std::string name, state, parameters;
    AudioProcessorParameter* bypass = nullptr;
    bool bypassOn = false;
    // Dry history for latency-matched soft bypass of plugins without a bypass parameter.
    AudioBuffer<float> dry;
    int dryPosition = 0;
    TouchListener touch;
    explicit Plugin(std::unique_ptr<AudioPluginInstance> p) : instance(std::move(p)), name(instance->getName().toStdString()) {
        buffer.setSize(jmax(instance->getTotalNumInputChannels(), instance->getTotalNumOutputChannels()), capacity); midi.ensureSize(4096);
        bypass = instance->getBypassParameter();
        dry.setSize(2, jlimit(capacity + 1, 262144 + capacity + 1, instance->getLatencySamples() + capacity + 1)); dry.clear();
        instance->addListener(&touch);
    }
    ~Plugin() { instance->removeListener(&touch); vm_release_editor_commands(this); editor.reset(); instance->releaseResources(); }
};
}
extern "C" {
void* vm_juce_create_named(const char* path, const char* identifier, double rate, int block, char* error, int errorSize) {
    initialiseJuce_GUI();
    VST3PluginFormat format;
    OwnedArray<PluginDescription> types;
    format.findAllTypesForFile(types, String::fromUTF8(path));
    String message;
    for (auto* description : types) {
        if (description->isInstrument) continue;
        if (identifier && *identifier && description->createIdentifierString() != String::fromUTF8(identifier)) continue;
        auto instance = format.createInstanceFromDescription(*description, rate, block, message);
        if (!instance) continue;
        auto original = instance->getBusesLayout();
        if (original.inputBuses.isEmpty() || original.outputBuses.isEmpty()) continue;
        bool accepted = false;
        for (int mainChannels : {2, 1}) {
            auto layout = original;
            layout.inputBuses.getReference(0) = AudioChannelSet::canonicalChannelSet(mainChannels);
            layout.outputBuses.getReference(0) = AudioChannelSet::canonicalChannelSet(mainChannels);
            for (int bus=1; bus<layout.inputBuses.size(); ++bus) {
                auto channels = instance->getBus(true, bus)->getDefaultLayout();
                layout.inputBuses.getReference(bus) = channels.isDisabled() ? AudioChannelSet::stereo() : channels;
            }
            for (int bus=1; bus<layout.outputBuses.size(); ++bus) layout.outputBuses.getReference(bus) = AudioChannelSet::disabled();
            if (instance->setBusesLayout(layout)) { accepted = true; break; }
            layout = original;
            layout.inputBuses.getReference(0) = AudioChannelSet::canonicalChannelSet(mainChannels);
            layout.outputBuses.getReference(0) = AudioChannelSet::canonicalChannelSet(mainChannels);
            if (instance->setBusesLayout(layout)) { accepted = true; break; }
        }
        if (!accepted || instance->getMainBusNumInputChannels()>2 || instance->getMainBusNumOutputChannels()>2 || instance->getTotalNumInputChannels()>32 || instance->getTotalNumOutputChannels()>32) {
            message = "A mono/stereo main bus with up to 32 auxiliary channels is required."; continue;
        }
        instance->setRateAndBufferSizeDetails(rate, block);
        instance->prepareToPlay(rate, block);
        return new Plugin(std::move(instance));
    }
    if (message.isEmpty()) message = "No compatible ARM64 VST3 stereo effect found.";
    if (errorSize > 0) { std::strncpy(error, message.toRawUTF8(), (size_t)errorSize - 1); error[errorSize - 1] = 0; }
    return nullptr;
}
void* vm_juce_create(const char* path, double rate, int block, char* error, int errorSize) {
    return vm_juce_create_named(path, "", rate, block, error, errorSize);
}
const char* vm_juce_scan(const char* path) {
    initialiseJuce_GUI();
    static std::string result;
    VST3PluginFormat format;
    OwnedArray<PluginDescription> types;
    format.findAllTypesForFile(types, String::fromUTF8(path));
    Array<var> entries;
    for (auto* description : types) {
        if (description->isInstrument) continue;
        auto* item = new DynamicObject();
        item->setProperty("name", description->name);
        item->setProperty("manufacturer", description->manufacturerName);
        item->setProperty("category", description->category);
        item->setProperty("identifier", description->createIdentifierString());
        item->setProperty("path", String::fromUTF8(path));
        entries.add(var(item));
    }
    result = JSON::toString(var(entries), true).toStdString();
    return result.c_str();
}
void vm_juce_destroy(void* p) { delete static_cast<Plugin*>(p); }
void vm_juce_prepare(void* p, double rate, int block) {
    auto& plugin = *static_cast<Plugin*>(p);
    plugin.instance->releaseResources();
    plugin.instance->setRateAndBufferSizeDetails(rate, block);
    plugin.instance->prepareToPlay(rate, block);
}
void vm_juce_process_side(void* p, float* audio, const float* side, int frames) {
    if (frames <= 0 || frames > capacity) return;
    auto& plugin = *static_cast<Plugin*>(p);
    const ScopedLock lock(plugin.instance->getCallbackLock());
    plugin.buffer.clear();
    auto main = plugin.instance->getBusBuffer(plugin.buffer, true, 0);
    for (int i=0; i<frames; ++i) {
        if (main.getNumChannels()==1) main.setSample(0,i,(audio[i*2]+audio[i*2+1])*.5f);
        else { main.setSample(0,i,audio[i*2]); main.setSample(1,i,audio[i*2+1]); }
    }
    for (int bus=1; bus<plugin.instance->getBusCount(true); ++bus) {
        auto auxiliary = plugin.instance->getBusBuffer(plugin.buffer,true,bus);
        for (int channel=0; channel<auxiliary.getNumChannels(); ++channel)
            for (int i=0; i<frames; ++i)
                auxiliary.setSample(channel,i,side ? (auxiliary.getNumChannels()==1 ? (side[i*2]+side[i*2+1])*.5f : side[i*2+channel%2]) : 0);
    }
    AudioBuffer<float> block(plugin.buffer.getArrayOfWritePointers(),plugin.buffer.getNumChannels(),frames);
    plugin.midi.clear(); plugin.instance->processBlock(block,plugin.midi);
    auto output=plugin.instance->getBusBuffer(block,false,0);
    for (int i=0;i<frames;++i) { audio[i*2]=output.getSample(0,i);audio[i*2+1]=output.getSample(jmin(1,output.getNumChannels()-1),i); }
}
void vm_juce_process(void* p,float* audio,int frames) { vm_juce_process_side(p,audio,nullptr,frames); }
// Full render entry used by the worker: MIDI input and latency-preserving soft bypass.
void vm_juce_process_ex(void* p,float* audio,const float* side,int frames,const uint32_t* midi,int midiCount,int softBypass) {
    if (frames <= 0 || frames > capacity) return;
    auto& plugin = *static_cast<Plugin*>(p);
    const int dryFrames = plugin.dry.getNumSamples();
    const int delay = jlimit(0, dryFrames - frames - 1, plugin.instance->getLatencySamples());
    // Always record the input, so switching to bypass outputs a continuous delayed signal.
    for (int i = 0; i < frames; ++i) {
        const int at = (plugin.dryPosition + i) % dryFrames;
        plugin.dry.setSample(0, at, audio[i*2]); plugin.dry.setSample(1, at, audio[i*2+1]);
    }
    const bool bypassed = softBypass != 0;
    if (plugin.bypass != nullptr && bypassed != plugin.bypassOn) { plugin.bypass->setValue(bypassed ? 1.0f : 0.0f); plugin.bypassOn = bypassed; }
    if (bypassed && plugin.bypass == nullptr) {
        for (int i = 0; i < frames; ++i) {
            const int at = (plugin.dryPosition + i - delay + dryFrames) % dryFrames;
            audio[i*2] = plugin.dry.getSample(0, at); audio[i*2+1] = plugin.dry.getSample(1, at);
        }
        plugin.dryPosition = (plugin.dryPosition + frames) % dryFrames;
        return;
    }
    plugin.dryPosition = (plugin.dryPosition + frames) % dryFrames;
    const ScopedLock lock(plugin.instance->getCallbackLock());
    plugin.buffer.clear();
    auto main = plugin.instance->getBusBuffer(plugin.buffer, true, 0);
    for (int i=0; i<frames; ++i) {
        if (main.getNumChannels()==1) main.setSample(0,i,(audio[i*2]+audio[i*2+1])*.5f);
        else { main.setSample(0,i,audio[i*2]); main.setSample(1,i,audio[i*2+1]); }
    }
    for (int bus=1; bus<plugin.instance->getBusCount(true); ++bus) {
        auto auxiliary = plugin.instance->getBusBuffer(plugin.buffer,true,bus);
        for (int channel=0; channel<auxiliary.getNumChannels(); ++channel)
            for (int i=0; i<frames; ++i)
                auxiliary.setSample(channel,i,side ? (auxiliary.getNumChannels()==1 ? (side[i*2]+side[i*2+1])*.5f : side[i*2+channel%2]) : 0);
    }
    plugin.midi.clear();
    for (int i = 0; i < midiCount; ++i) {
        const uint8 bytes[3] = { (uint8)(midi[i] & 0xff), (uint8)((midi[i] >> 8) & 0x7f), (uint8)((midi[i] >> 16) & 0x7f) };
        const int kind = bytes[0] & 0xf0;
        if (kind < 0x80 || kind == 0xf0) continue;
        plugin.midi.addEvent(bytes, kind == 0xc0 || kind == 0xd0 ? 2 : 3, 0);
    }
    AudioBuffer<float> block(plugin.buffer.getArrayOfWritePointers(),plugin.buffer.getNumChannels(),frames);
    plugin.instance->processBlock(block,plugin.midi);
    auto output=plugin.instance->getBusBuffer(block,false,0);
    for (int i=0;i<frames;++i) { audio[i*2]=output.getSample(0,i);audio[i*2+1]=output.getSample(jmin(1,output.getNumChannels()-1),i); }
}
int vm_juce_has_bypass(void* p) { return static_cast<Plugin*>(p)->bypass != nullptr; }
// Render thread: JUCE's hosted VST3 parameters queue the change for the next process call.
void vm_juce_set_parameter(void* p,int index,float value) {
    auto& parameters = static_cast<Plugin*>(p)->instance->getParameters();
    if (index >= 0 && index < parameters.size()) parameters[index]->setValue(jlimit(0.0f, 1.0f, value));
}
const char* vm_juce_parameters(void* p) {
    auto& plugin = *static_cast<Plugin*>(p);
    Array<var> entries;
    auto& parameters = plugin.instance->getParameters();
    for (int i = 0; i < jmin(parameters.size(), 2048); ++i) {
        auto* item = new DynamicObject();
        item->setProperty("index", i);
        item->setProperty("name", parameters[i]->getName(64));
        item->setProperty("value", parameters[i]->getValue());
        item->setProperty("automatable", parameters[i]->isAutomatable());
        entries.add(var(item));
    }
    plugin.parameters = JSON::toString(var(entries), true).toStdString();
    return plugin.parameters.c_str();
}
void vm_juce_set_touch_callback(void* p,void (*callback)(void*,int),void* context) {
    auto& plugin = *static_cast<Plugin*>(p); plugin.touch.context = context; plugin.touch.callback = callback;
}
int vm_juce_side_channels(void* p) {
    auto& instance=*static_cast<Plugin*>(p)->instance;
    return instance.getTotalNumInputChannels()-instance.getMainBusNumInputChannels();
}
int vm_juce_latency(void* p) { return static_cast<Plugin*>(p)->instance->getLatencySamples(); }
void vm_juce_editor(void* p) {
    auto& plugin = *static_cast<Plugin*>(p);
    if (plugin.editor && !plugin.editor->isVisible()) plugin.editor.reset();
    if (!plugin.editor) {
        auto* editor = plugin.instance->createEditorIfNeeded();
        if (!editor) editor = new GenericAudioProcessorEditor(*plugin.instance);
        plugin.editor = std::make_unique<EditorWindow>(editor);
    }
    plugin.editor->setVisible(true); plugin.editor->toFront(true);
    if (auto* peer=plugin.editor->getPeer()) vm_configure_editor_clicks(peer->getNativeHandle(),p);
}
void vm_juce_hide_editor(void* p) { if(p) { auto& plugin=*static_cast<Plugin*>(p);if(plugin.editor)plugin.editor->setVisible(false); } }
int vm_juce_editor_visible(void* p) { auto& plugin=*static_cast<Plugin*>(p);return plugin.editor && plugin.editor->isVisible(); }
const char* vm_juce_name(void* p) { return static_cast<Plugin*>(p)->name.c_str(); }
const char* vm_juce_state(void* p) {
    auto& plugin = *static_cast<Plugin*>(p);
    // Like DAW hosts, read state on the message thread without the callback lock:
    // VST3 getState must be thread-safe, and holding the lock here stalled the
    // render thread for the whole serialization (large states caused dropouts/faults).
    MemoryBlock state; plugin.instance->getStateInformation(state);
    plugin.state = state.toBase64Encoding().toStdString(); return plugin.state.c_str();
}
void vm_juce_restore(void* p, const char* state) {
    const ScopedLock lock(static_cast<Plugin*>(p)->instance->getCallbackLock());
    MemoryBlock block;
    if (block.fromBase64Encoding(String::fromUTF8(state)) && block.getSize()>0)
        static_cast<Plugin*>(p)->instance->setStateInformation(block.getData(), (int)block.getSize());
}
}
