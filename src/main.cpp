#include <RED4ext/RED4ext.hpp>
#include <RED4ext/RTTITypes.hpp>
#include <RED4ext/Scripting/IScriptable.hpp>
#include <RED4ext/Scripting/Natives/Generated/Vector4.hpp>
#include <fmod.hpp>
#include <fmod_errors.h>
#include "SoundLoadData.hpp"

#define RADIOEXT_VERSION 0.1
#define CHANNELS 64

const RED4ext::Sdk* sdk;
RED4ext::PluginHandle handle;
FMOD::System* pSystem;
FMOD::Channel* pChannels[CHANNELS + 1]; // Channels, 0 is reserved for vehicle radio
SoundLoadData* loadData[CHANNELS + 1]; // For temporarily storing the data of a channel, while the sound loads

// General purpose functions
void GetRadioExtVersion(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4);
void GetNumChannels(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t a4);
void GetFolders(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, RED4ext::DynArray<RED4ext::CString>* aOut, int64_t a4);
void GetSongLength(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t a4);

// Audio playback functions
void Play(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4);
void Stop(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4);
void SetVolume(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4);
void SetListenerTransform(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4);
void SetChannelTransform(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4);
void Set3DFalloff(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4);
void Set3DMinMax(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4);

// Red4Ext Stuff
void registerGeneralFunctions(RED4ext::CRTTISystem* rtti);
void registerAudioFunctions(RED4ext::CRTTISystem* rtti);

// Native Class setup
struct RadioExt : RED4ext::IScriptable
{
    RED4ext::CClass* GetNativeType();
};

RED4ext::TTypedClass<RadioExt> cls("RadioExt");

RED4ext::CClass* RadioExt::GetNativeType()
{
    return &cls;
}

RED4EXT_C_EXPORT void RED4EXT_CALL RegisterTypes()
{
    RED4ext::CNamePool::Add("RadioExt");

    cls.flags = {.isNative = true};
    RED4ext::CRTTISystem::Get()->RegisterType(&cls);
}

RED4EXT_C_EXPORT void RED4EXT_CALL PostRegisterTypes()
{
    auto rtti = RED4ext::CRTTISystem::Get();
    auto scriptable = rtti->GetClass("IScriptable");
    cls.parent = scriptable;

    registerGeneralFunctions(rtti);
    registerAudioFunctions(rtti);
}

void logError(FMOD_RESULT result, const char* msg)
{
    if (result != FMOD_OK)
    {
        sdk->logger->ErrorF(handle, "%s: %s", msg, FMOD_ErrorString(result));
    }
}

void registerGeneralFunctions(RED4ext::CRTTISystem* rtti)
{
    auto getLength = RED4ext::CClassStaticFunction::Create(&cls, "GetSongLength", "GetSongLength", &GetSongLength, {.isNative = true, .isStatic = true});
    getLength->AddParam("String", "path");
    getLength->SetReturnType("Int32");

    auto getVersion = RED4ext::CClassStaticFunction::Create(&cls, "GetVersion", "GetVersion", &GetRadioExtVersion, {.isNative = true, .isStatic = true});
    getVersion->SetReturnType("Float");

    auto getChannels = RED4ext::CClassStaticFunction::Create(&cls, "GetNumChannels", "GetNumChannels", &GetNumChannels, { .isNative = true, .isStatic = true });
    getChannels->SetReturnType("Int32");

    auto getFolders = RED4ext::CClassStaticFunction::Create(&cls, "GetFolders", "GetFolders", &GetFolders, {.isNative = true, .isStatic = true});
    getFolders->AddParam("String", "path");
    getFolders->SetReturnType("array:String");

    cls.RegisterFunction(getLength);
    cls.RegisterFunction(getVersion);
    cls.RegisterFunction(getFolders);
    cls.RegisterFunction(getChannels);
}

void registerAudioFunctions(RED4ext::CRTTISystem* rtti)
{
    auto play = RED4ext::CClassStaticFunction::Create(&cls, "Play", "Play", &Play, {.isNative = true, .isStatic = true});
    play->AddParam("Int32", "channelID");
    play->AddParam("String", "path");
    play->AddParam("Int32", "startPos");
    play->AddParam("Float", "volume");
    play->AddParam("Float", "fade");

    auto setVolume = RED4ext::CClassStaticFunction::Create(&cls, "SetVolume", "SetVolume", &SetVolume, {.isNative = true, .isStatic = true});
    setVolume->AddParam("Int32", "channelID");
    setVolume->AddParam("Float", "volume");

    auto setFalloff = RED4ext::CClassStaticFunction::Create(&cls, "Set3DFalloff", "Set3DFalloff", &Set3DFalloff, { .isNative = true, .isStatic = true });
    setFalloff->AddParam("Float", "falloff");

    auto stop = RED4ext::CClassStaticFunction::Create(&cls, "Stop", "Stop", &Stop, {.isNative = true, .isStatic = true});
    stop->AddParam("Int32", "channelID");

    auto setListener = RED4ext::CClassStaticFunction::Create(&cls, "SetListener", "SetListener", &SetListenerTransform, { .isNative = true, .isStatic = true });
    setListener->AddParam("Vector4", "pos");
    setListener->AddParam("Vector4", "forward");
    setListener->AddParam("Vector4", "up");

    auto setChannelPos = RED4ext::CClassStaticFunction::Create(&cls, "SetChannelPos", "SetChannelPos", &SetChannelTransform, { .isNative = true, .isStatic = true });
    setChannelPos->AddParam("Int32", "channelID");
    setChannelPos->AddParam("Vector4", "pos");

    auto setMinMax = RED4ext::CClassStaticFunction::Create(&cls, "SetMinMax", "SetMinMax", &Set3DMinMax, { .isNative = true, .isStatic = true });
    setMinMax->AddParam("Float", "min");
    setMinMax->AddParam("Float", "max");

    cls.RegisterFunction(play);
    cls.RegisterFunction(setVolume);
    cls.RegisterFunction(setFalloff);
    cls.RegisterFunction(stop);
    cls.RegisterFunction(setListener);
    cls.RegisterFunction(setChannelPos);
    cls.RegisterFunction(setMinMax);
}

void setFadeIn(FMOD::System* pSystem, FMOD::Channel* pChannel, float duration) {
    logError(pChannel->setPaused(true), "setPaused(true)");

    unsigned long long dspclock;
    int rate;
    FMOD_RESULT result;

    logError(pChannel->getSystemObject(&pSystem), "getSystemObject");
    logError(pSystem->getSoftwareFormat(&rate, 0, 0), "getSoftwareFormat");
    logError(pChannel->getDSPClock(0, &dspclock), "getDSPClock");
    logError(pChannel->addFadePoint(dspclock, 0.0f), "addFadePoint");
    logError(pChannel->addFadePoint(dspclock + (rate * duration), 1.0f), "addFadePoint");
    logError(pChannel->setPaused(false), "setPaused(false)");
}

void GetSongLength(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);

    RED4ext::CString path;
    RED4ext::GetParameter(aFrame, &path);
    std::filesystem::path subDir = path.c_str();
    std::filesystem::path target = std::filesystem::current_path() / subDir;

    unsigned int length = 0;

    FMOD::Sound* sound;
    FMOD_RESULT error = pSystem->createSound(target.string().c_str(), FMOD_CREATESTREAM, nullptr, &sound);
    // Only log if there is an error, as this gets called for allll the songs
    if (error != FMOD_OK)
    {
        sdk->logger->ErrorF(handle, "FMOD::System::createSound: %s. Requested Path: %s", FMOD_ErrorString(error), target.string().c_str());
    }

    error = sound->getLength(&length, FMOD_TIMEUNIT_MS);
    if (error != FMOD_OK)
    {
        sdk->logger->ErrorF(handle, "FMOD::System::getLength: %s. Requested Path: %s", FMOD_ErrorString(error), target.string().c_str());
    }

    if (aOut)
    {
        auto type = RED4ext::CRTTISystem::Get()->GetType("Int32");
        type->Assign(aOut, &length);
    }

    aFrame->code++; // skip ParamEnd
}

void GetFolders(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, RED4ext::DynArray<RED4ext::CString>* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);

    RED4ext::CString path;
    RED4ext::GetParameter(aFrame, &path);

    std::filesystem::path subDir = path.c_str();
    std::filesystem::path target = std::filesystem::current_path() / subDir;
    sdk->logger->InfoF(handle, "GetFolders(%s)", target.string().c_str());

    RED4ext::DynArray<RED4ext::CString> folders;

    for (const auto& entry : std::filesystem::directory_iterator(target))
    {
        if (entry.is_directory())
        {
            folders.PushBack(entry.path().filename().string());
        }
    }

    if (aOut)
    {
        auto type = RED4ext::CRTTISystem::Get()->GetType("array:String");
        type->Assign(aOut, &folders);
    }

    aFrame->code++; // skip ParamEnd
}

void GetNumChannels(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);

    int32_t channels = CHANNELS;

    if (aOut)
    {
        auto type = RED4ext::CRTTISystem::Get()->GetType("Int32");
        type->Assign(aOut, &channels);
    }

    aFrame->code++; // skip ParamEnd
}

void GetRadioExtVersion(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);

    float version = RADIOEXT_VERSION;
    if (aOut)
    {
        auto type = RED4ext::CRTTISystem::Get()->GetType("Float");
        type->Assign(aOut, &version);
    }

    aFrame->code++; // skip ParamEnd
}

void Play(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);

    int32_t channelID;
    RED4ext::CString path;
    int32_t startPos;
    float volume;
    float fade;
    RED4ext::GetParameter(aFrame, &channelID);
    RED4ext::GetParameter(aFrame, &path);
    RED4ext::GetParameter(aFrame, &startPos);
    RED4ext::GetParameter(aFrame, &volume);
    RED4ext::GetParameter(aFrame, &fade);
    sdk->logger->InfoF(handle, "Play(%i, \"%s\", %i, %f, %f)", channelID, path.c_str(), startPos, volume, fade);

    FMOD_MODE mode = FMOD_3D;
    if (channelID == -1)
    {
        mode = FMOD_DEFAULT;
    }

    if (channelID == -1)
    {
        channelID = 0;
    }

    channelID = min(CHANNELS, channelID);

    sdk->logger->InfoF(handle, "FMOD::System::createSound: %s", FMOD_ErrorString(pSystem->createStream(path.c_str(), mode | FMOD_NONBLOCKING, nullptr, &loadData[channelID]->sound)));

    loadData[channelID]->fade = fade;
    loadData[channelID]->startPos = startPos;
    loadData[channelID]->volume = volume;
    loadData[channelID]->play = true; // Sound is loading, check if loading has finished

    aFrame->code++; // skip ParamEnd
}

void SetVolume(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);

    int32_t channelID;
    float volume;
    RED4ext::GetParameter(aFrame, &channelID);
    RED4ext::GetParameter(aFrame, &volume);
    sdk->logger->InfoF(handle, "SetVolume(%i, %f)", channelID, volume);

    volume = max(0, volume);
    channelID = min(CHANNELS, channelID);

    if (channelID == -1)
    {
        channelID = 0;
    }

    if (pChannels[channelID])
    {
        sdk->logger->InfoF(handle, "FMOD::Channel::setVolume: %s", FMOD_ErrorString(pChannels[channelID]->setVolume(volume)));
    }

    aFrame->code++; // skip ParamEnd
}

void Set3DFalloff(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);

    float falloff;
    RED4ext::GetParameter(aFrame, &falloff);
    sdk->logger->InfoF(handle, "Set3DFalloff(%f)", falloff);

    sdk->logger->InfoF(handle, "FMOD::System::set3DSettings: %s", FMOD_ErrorString(pSystem->set3DSettings(1, 1, falloff)));

    aFrame->code++; // skip ParamEnd
}

void Set3DMinMax(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);

    float min;
    float max;
    RED4ext::GetParameter(aFrame, &min);
    RED4ext::GetParameter(aFrame, &max);

    for (int i = 0; i <= CHANNELS; i++)
    {
        if (pChannels[i])
        {
            logError(pChannels[i]->set3DMinMaxDistance(min, max), "Set3DMinMax");
        }
    }

    aFrame->code++; // skip ParamEnd
}

void Stop(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aFrame);

    int32_t channelID;
    RED4ext::GetParameter(aFrame, &channelID);

    channelID = min(CHANNELS, channelID);

    if (channelID == -1)
    {
        channelID = 0;
    }

    loadData[channelID]->play = false;

    if (pChannels[channelID])
    {
        pChannels[channelID]->stop();
        pChannels[channelID] = nullptr;
        sdk->logger->InfoF(handle, "Stopped channel %i", channelID);
    }

    aFrame->code++; // skip ParamEnd
}

void SetChannelTransform(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);

    int32_t channelID;
    RED4ext::Vector4 pos;
    RED4ext::GetParameter(aFrame, &channelID);
    RED4ext::GetParameter(aFrame, &pos);

    channelID = min(CHANNELS, channelID);

    if (channelID == -1)
    {
        channelID = 0;
    }

    FMOD_VECTOR posF;

    auto rtti = RED4ext::CRTTISystem::Get();
    auto v4Prop = rtti->GetClass("Vector4");

    auto xProp = v4Prop->GetProperty("X");
    auto yProp = v4Prop->GetProperty("Y");
    auto zProp = v4Prop->GetProperty("Z");

    posF.x = -xProp->GetValue<float>(&pos);
    posF.y = zProp->GetValue<float>(&pos);
    posF.z = yProp->GetValue<float>(&pos);

    if (pChannels[channelID])
    {
        logError(pChannels[channelID]->set3DAttributes(&posF, nullptr), "set3DListenerAttributes");
    }

    aFrame->code++; // skip ParamEnd
}

void SetListenerTransform(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);

    RED4ext::Vector4 pos;
    RED4ext::Vector4 forward;
    RED4ext::Vector4 up;
    RED4ext::GetParameter(aFrame, &pos);
    RED4ext::GetParameter(aFrame, &forward);
    RED4ext::GetParameter(aFrame, &up);

    FMOD_VECTOR posF;
    FMOD_VECTOR forwardF;
    FMOD_VECTOR upF;
    FMOD_VECTOR velF;
    velF.x = velF.y = velF.z = 0;

    auto rtti = RED4ext::CRTTISystem::Get();
    auto v4Prop = rtti->GetClass("Vector4");

    auto xProp = v4Prop->GetProperty("X");
    auto yProp = v4Prop->GetProperty("Y");
    auto zProp = v4Prop->GetProperty("Z");

    posF.x = -xProp->GetValue<float>(&pos);
    posF.y = zProp->GetValue<float>(&pos);
    posF.z = yProp->GetValue<float>(&pos);

    forwardF.x = -xProp->GetValue<float>(&forward);
    forwardF.y = zProp->GetValue<float>(&forward);
    forwardF.z = yProp->GetValue<float>(&forward);

    upF.x = -xProp->GetValue<float>(&up);
    upF.y = zProp->GetValue<float>(&up);
    upF.z = yProp->GetValue<float>(&up);

    logError(pSystem->set3DListenerAttributes(0, &posF, &velF, &forwardF, &upF), "set3DListenerAttributes");

    aFrame->code++; // skip ParamEnd
}

void checkSoundLoad()
{
    for (int i = 0; i <= CHANNELS; i++)
    {
        if (!loadData[i]->sound || !loadData[i]->play)
        {
            continue;
        }

        FMOD_OPENSTATE state;
        FMOD_RESULT result = loadData[i]->sound->getOpenState(&state, 0, 0, 0);

        if (result != FMOD_OK)
        {
            logError(result, "getOpenState");
            loadData[i]->play = false;
        }

        if (state == FMOD_OPENSTATE_READY)
        {
            loadData[i]->play = false;

            sdk->logger->InfoF(handle, "FMOD::Sound::setMode: %s", FMOD_ErrorString(loadData[i]->sound->setMode(FMOD_3D_INVERSETAPEREDROLLOFF)));
            logError(loadData[i]->sound->set3DMinMaxDistance(1, 10), "set3DMinMaxDistance");

            unsigned int lengthMs = 0;
            logError(loadData[i]->sound->getLength(&lengthMs, FMOD_TIMEUNIT_MS), "getLength");
            int32_t startPos = min(max(loadData[i]->startPos, 0), lengthMs);

            float volume = max(0, loadData[i]->volume);

            sdk->logger->InfoF(handle, "FMOD::System::playSound: %s", FMOD_ErrorString(pSystem->playSound(loadData[i]->sound, nullptr, false, &pChannels[i])));
            sdk->logger->InfoF(handle, "FMOD::Channel::setPosition: %s", FMOD_ErrorString(pChannels[i]->setPosition(startPos, FMOD_TIMEUNIT_MS)));
            sdk->logger->InfoF(handle, "FMOD::Channel::setVolume: %s", FMOD_ErrorString(pChannels[i]->setVolume(volume)));

            setFadeIn(pSystem, pChannels[i], loadData[i]->fade);
        } else if(state == FMOD_OPENSTATE_ERROR) {
            sdk->logger->ErrorF(handle, "Failed to load sound for channel %i", i);
            loadData[i]->play = false;
        }
    }
}

bool Running_OnEnter(RED4ext::CGameApplication* aApp)
{
    return true;
}

bool Running_OnUpdate(RED4ext::CGameApplication* aApp)
{
    checkSoundLoad();
    pSystem->update();
    return false;
}

bool Running_OnExit(RED4ext::CGameApplication* aApp)
{
    for (int i = 0; i <= CHANNELS; i++)
    {
        if (pChannels[i])
        {
            pChannels[i]->stop();
        }
        delete loadData[i];
    }

    return true;
}

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::PluginHandle aHandle, RED4ext::EMainReason aReason, const RED4ext::Sdk* aSdk)
{
    switch (aReason)
    {
    case RED4ext::EMainReason::Load:
    {
        sdk = aSdk;
        handle = aHandle;

        sdk->logger->InfoF(handle, "FMOD::System_Create %s", FMOD_ErrorString(FMOD::System_Create(&pSystem)));
        sdk->logger->InfoF(handle, "FMOD::System::init %s", FMOD_ErrorString(pSystem->init(CHANNELS, FMOD_INIT_3D_RIGHTHANDED, nullptr)));
        sdk->logger->InfoF(handle, "FMOD::System::set3DSettings %s", FMOD_ErrorString(pSystem->set3DSettings(1, 1, 0.325)));

        for (int i = 0; i <= CHANNELS; i++)
        {
            loadData[i] = new SoundLoadData;
            loadData[i]->play = false;
        }

        RED4ext::GameState updateState;
        updateState.OnEnter = &Running_OnEnter;
        updateState.OnUpdate = &Running_OnUpdate;
        updateState.OnExit = &Running_OnExit;
        aSdk->gameStates->Add(aHandle, RED4ext::EGameStateType::Running, &updateState);

        RED4ext::RTTIRegistrator::Add(RegisterTypes, PostRegisterTypes);

        break;
    }
    case RED4ext::EMainReason::Unload:
    {
        pSystem->close();
        pSystem->release();
        break;
    }
    }

    return true;
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::PluginInfo* aInfo)
{
    aInfo->name = L"RadioExt";
    aInfo->author = L"keanuWheeze";
    aInfo->version = RED4EXT_SEMVER(1, 0, 0);
    aInfo->runtime = RED4EXT_RUNTIME_LATEST;
    aInfo->sdk = RED4EXT_SDK_LATEST;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_LATEST;
}
