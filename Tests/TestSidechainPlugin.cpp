#include <juce_audio_utils/juce_audio_utils.h>
#include <unistd.h>
class TestSide final : public juce::AudioProcessor {
    float delay[2][37]={}; int position=0;
public:
    TestSide() : AudioProcessor(BusesProperties().withInput("Input", juce::AudioChannelSet::stereo(), true).withInput("Required Sidechain", juce::AudioChannelSet::stereo(), true).withOutput("Output", juce::AudioChannelSet::stereo(), true)) { setLatencySamples(37); }
    const juce::String getName() const override { return "Audiomeeter Test Sidechain"; }
    void prepareToPlay(double,int) override { memset(delay,0,sizeof(delay));position=0; }
    void releaseResources() override {}
    bool isBusesLayoutSupported(const BusesLayout& layout) const override { return layout.inputBuses.size()==2 && layout.inputBuses[1]==juce::AudioChannelSet::stereo() && layout.getMainInputChannelSet()==juce::AudioChannelSet::stereo() && layout.getMainOutputChannelSet()==juce::AudioChannelSet::stereo(); }
    void processBlock(juce::AudioBuffer<float>& buffer,juce::MidiBuffer&) override {
        if(buffer.getSample(0,0)>1000)abort();
        if(buffer.getSample(0,0)<-1000)usleep(10000000);
        auto side=getBusBuffer(buffer,true,1);
        for(int i=0;i<buffer.getNumSamples();++i) {
            for(int c=0;c<2;++c) { float value=buffer.getSample(c,i)*.5f+side.getSample(c,i)*.25f;buffer.setSample(c,i,delay[c][position]);delay[c][position]=value; }
            position=(position+1)%37;
        }
    }
    bool hasEditor() const override { return false; }
    juce::AudioProcessorEditor* createEditor() override { return nullptr; }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return 0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int,const juce::String&) override {}
    void getStateInformation(juce::MemoryBlock&) override {}
    void setStateInformation(const void*,int) override {}
};
juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter() { return new TestSide; }
