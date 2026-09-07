#include <RED4ext/RED4ext.hpp>
#include <RED4ext/RTTITypes.hpp>
#include <RED4ext/Scripting/IScriptable.hpp>
#include <RED4ext/Scripting/Natives/Generated/Vector4.hpp>
#include <fmod.hpp>
#include <fmod_errors.h>
#include <string>
#include <unordered_map>
#include <vector>
#include "SoundLoadData.hpp"

constexpr RED4ext::v1::SemVer radioExtVersion{2, 3, 0, {}};
constexpr int32_t channelCount = 64;
constexpr uint32_t maxLoadAttempts = 3;

const RED4ext::v1::Sdk* sdk;
RED4ext::v1::PluginHandle handle;
std::filesystem::path gameBinDir;
FMOD::System* pSystem = nullptr;
FMOD::Channel* pChannels[channelCount + 1]{}; // Channels, 0 is reserved for vehicle radio
SoundLoadData* loadData[channelCount + 1]{}; // For temporarily storing the data of a channel, while the sound loads
bool systemInitialized = false;
std::unordered_map<std::string, uint32_t> failedConnections;

// General purpose functions
void GetRadioExtVersion(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut,
                        int64_t a4);
void GetNumChannels(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t a4);
void GetFolders(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, RED4ext::DynArray<RED4ext::CString>* aOut, int64_t a4);
void GetSongLength(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t a4);

// Audio playback functions
void Play(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4);
void Stop(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4);
void SetVolume(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4);
void SetListenerTransform(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4);
void SetChannelTransform(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4);
void Set3DFalloff(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4);
void Set3DMinMax(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4);

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

void RegisterTypes()
{
    RED4ext::CNamePool::Add("RadioExt");

    cls.flags = {.isNative = true};
    RED4ext::CRTTISystem::Get()->RegisterType(&cls);
}

void PostRegisterTypes()
{
    auto rtti = RED4ext::CRTTISystem::Get();
    auto scriptable = rtti->GetClass("IScriptable");
    cls.parent = scriptable;

    registerGeneralFunctions(rtti);
    registerAudioFunctions(rtti);
}

std::filesystem::path pathFromUtf8(const char* path)
{
    const auto begin = reinterpret_cast<const char8_t*>(path);
    return std::filesystem::path(std::u8string(begin, begin + std::char_traits<char>::length(path)));
}

std::string pathToUtf8(const std::filesystem::path& path)
{
    const std::u8string utf8 = path.u8string();
    return {reinterpret_cast<const char*>(utf8.data()), utf8.size()};
}

// Provided by WSSDude / Andrej Redeky
std::filesystem::path getGameBinDir()
{
    constexpr DWORD maxPathLength = 32768; // Maximum extended-length path plus the null terminator
    std::vector<wchar_t> exePathBuf(maxPathLength);
    const DWORD length = GetModuleFileNameW(nullptr, exePathBuf.data(), maxPathLength);
    if (length == 0 || length >= maxPathLength)
    {
        return {};
    }

    return std::filesystem::path(exePathBuf.data(), exePathBuf.data() + length).parent_path();
}

void logError(FMOD_RESULT result, const char* msg)
{
    if (result != FMOD_OK)
    {
        sdk->logger->ErrorF(handle, "%s: %s", msg, FMOD_ErrorString(result));
    }
}

bool normalizeChannelID(int32_t& channelID)
{
    if (channelID == -1)
    {
        channelID = 0;
        return true;
    }

    if (channelID < 0 || channelID > channelCount)
    {
        sdk->logger->ErrorF(handle, "Invalid channel ID: %i", channelID);
        return false;
    }

    return true;
}

void stopAndReleaseChannel(int32_t channelID)
{
    if (loadData[channelID])
    {
        loadData[channelID]->play = false;
    }

    if (pChannels[channelID])
    {
        logError(pChannels[channelID]->stop(), "FMOD::Channel::stop");
        pChannels[channelID] = nullptr;
    }

    if (loadData[channelID] && loadData[channelID]->sound)
    {
        logError(loadData[channelID]->sound->release(), "FMOD::Sound::release");
        loadData[channelID]->sound = nullptr;
    }
}

void releaseChannelData()
{
    for (int i = 0; i <= channelCount; i++)
    {
        stopAndReleaseChannel(i);
        delete loadData[i];
        loadData[i] = nullptr;
    }
}

void registerGeneralFunctions(RED4ext::CRTTISystem* rtti)
{
    auto getLength = RED4ext::CClassStaticFunction::Create(&cls, "GetSongLength", "GetSongLength", &GetSongLength, {.isNative = true, .isStatic = true});
    getLength->AddParam("String", "path");
    getLength->SetReturnType("Int32");

    auto getVersion = RED4ext::CClassStaticFunction::Create(&cls, "GetVersion", "GetVersion", &GetRadioExtVersion, {.isNative = true, .isStatic = true});
    getVersion->SetReturnType("String");

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
    play->AddParam("Int32", "startPos"); // -1 indicates stream
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

void setFadeIn(FMOD::Channel* pChannel, float duration) {
    logError(pChannel->setPaused(true), "setPaused(true)");

    FMOD::System* channelSystem = nullptr;
    FMOD_RESULT result = pChannel->getSystemObject(&channelSystem);
    logError(result, "getSystemObject");
    if (result != FMOD_OK || !channelSystem)
    {
        logError(pChannel->setPaused(false), "setPaused(false)");
        return;
    }

    int rate = 0;
    result = channelSystem->getSoftwareFormat(&rate, nullptr, nullptr);
    logError(result, "getSoftwareFormat");
    if (result != FMOD_OK)
    {
        logError(pChannel->setPaused(false), "setPaused(false)");
        return;
    }

    unsigned long long dspclock = 0;
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
    std::filesystem::path subDir = pathFromUtf8(path.c_str());
    std::filesystem::path target = gameBinDir / subDir;
    const std::string targetUtf8 = pathToUtf8(target);

    unsigned int length = 0;

    FMOD::Sound* sound = nullptr;
    FMOD_RESULT error = pSystem->createSound(targetUtf8.c_str(), FMOD_CREATESTREAM, nullptr, &sound);
    // Only log if there is an error, as this gets called for allll the songs
    if (error != FMOD_OK)
    {
        sdk->logger->ErrorF(handle, "FMOD::System::createSound: %s. Requested Path: %s", FMOD_ErrorString(error), targetUtf8.c_str());

        if (aOut)
        {
            auto type = RED4ext::CRTTISystem::Get()->GetType("Int32");
            type->Assign(aOut, &length);
        }

        aFrame->code++; // skip ParamEnd
        return;
    }

    error = sound->getLength(&length, FMOD_TIMEUNIT_MS);
    if (error != FMOD_OK)
    {
        sdk->logger->ErrorF(handle, "FMOD::System::getLength: %s. Requested Path: %s", FMOD_ErrorString(error), targetUtf8.c_str());
    }

    logError(sound->release(), "FMOD::Sound::release");

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

    std::filesystem::path subDir = pathFromUtf8(path.c_str());
    std::filesystem::path target = gameBinDir / subDir;
    const std::string targetUtf8 = pathToUtf8(target);
    sdk->logger->DebugF(handle, "GetFolders(%s)", targetUtf8.c_str());

    RED4ext::DynArray<RED4ext::CString> folders;

    try
    {
        for (const auto& entry : std::filesystem::directory_iterator(target))
        {
            if (entry.is_directory())
            {
                folders.PushBack(pathToUtf8(entry.path().filename()));
            }
        }
    }
    catch (const std::filesystem::filesystem_error& error)
    {
        sdk->logger->ErrorF(handle, "Failed to enumerate radio folders at %s: %s", targetUtf8.c_str(), error.what());
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

    int32_t channels = channelCount;

    if (aOut)
    {
        auto type = RED4ext::CRTTISystem::Get()->GetType("Int32");
        type->Assign(aOut, &channels);
    }

    aFrame->code++; // skip ParamEnd
}

void GetRadioExtVersion(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut,
                        int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);

    const std::string versionString = std::to_string(radioExtVersion.major) + "." +
                                      std::to_string(radioExtVersion.minor) + "." +
                                      std::to_string(radioExtVersion.patch);
    RED4ext::CString version = versionString;

    if (aOut)
    {
        auto type = RED4ext::CRTTISystem::Get()->GetType("String");
        type->Assign(aOut, &version);
    }

    aFrame->code++; // skip ParamEnd
}

void Play(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);

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
    if (!normalizeChannelID(channelID))
    {
        aFrame->code++; // skip ParamEnd
        return;
    }

    std::filesystem::path subDir = pathFromUtf8(path.c_str());
    std::filesystem::path target = gameBinDir / subDir;
    std::string targetUtf8 = pathToUtf8(target);

    if (startPos == -1) // Is a stream
    {
        targetUtf8 = path.c_str();
    }

    if (failedConnections.contains(targetUtf8))
    {
        if (failedConnections[targetUtf8] >= maxLoadAttempts)
        {
            sdk->logger->ErrorF(handle, "Resource %s has exceeded maximum amount of load attempts.", targetUtf8.c_str());
            return;
        }
    }

    FMOD_MODE mode = channelID == 0 ? FMOD_2D : FMOD_3D;

    stopAndReleaseChannel(channelID);

    logError(pSystem->createStream(targetUtf8.c_str(), mode | FMOD_NONBLOCKING, nullptr,
                                   &loadData[channelID]->sound),
             "FMOD::System::createStream");

    loadData[channelID]->fade = fade;
    loadData[channelID]->startPos = startPos;
    loadData[channelID]->volume = volume;
    loadData[channelID]->mode = mode;
    loadData[channelID]->play = true; // Sound is loading, check if loading has finished
    loadData[channelID]->path = targetUtf8;
    aFrame->code++; // skip ParamEnd
}

void SetVolume(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);

    int32_t channelID;
    float volume;
    RED4ext::GetParameter(aFrame, &channelID);
    RED4ext::GetParameter(aFrame, &volume);
    volume = max(0, volume);
    if (!normalizeChannelID(channelID))
    {
        aFrame->code++; // skip ParamEnd
        return;
    }

    if (pChannels[channelID])
    {
        logError(pChannels[channelID]->setVolume(volume), "FMOD::Channel::setVolume");
    }

    aFrame->code++; // skip ParamEnd
}

void Set3DFalloff(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);

    float falloff;
    RED4ext::GetParameter(aFrame, &falloff);
    logError(pSystem->set3DSettings(1, 1, falloff), "FMOD::System::set3DSettings");

    aFrame->code++; // skip ParamEnd
}

void Set3DMinMax(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);

    float min;
    float max;
    RED4ext::GetParameter(aFrame, &min);
    RED4ext::GetParameter(aFrame, &max);

    for (int i = 0; i <= channelCount; i++)
    {
        if (pChannels[i])
        {
            logError(pChannels[i]->set3DMinMaxDistance(min, max), "Set3DMinMax");
        }
    }

    aFrame->code++; // skip ParamEnd
}

void Stop(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);

    int32_t channelID;
    RED4ext::GetParameter(aFrame, &channelID);

    if (!normalizeChannelID(channelID))
    {
        aFrame->code++; // skip ParamEnd
        return;
    }

    stopAndReleaseChannel(channelID);

    aFrame->code++; // skip ParamEnd
}

void SetChannelTransform(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);

    int32_t channelID;
    RED4ext::Vector4 pos;
    RED4ext::GetParameter(aFrame, &channelID);
    RED4ext::GetParameter(aFrame, &pos);

    if (!normalizeChannelID(channelID))
    {
        aFrame->code++; // skip ParamEnd
        return;
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
        logError(pChannels[channelID]->set3DAttributes(&posF, nullptr), "SetChannelTransform::set3DListenerAttributes");
    }

    aFrame->code++; // skip ParamEnd
}

void SetListenerTransform(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);

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

    logError(pSystem->set3DListenerAttributes(0, &posF, &velF, &forwardF, &upF), "SetListenerTransform::set3DListenerAttributes");

    aFrame->code++; // skip ParamEnd
}

void checkSoundLoad()
{
    for (int i = 0; i <= channelCount; i++)
    {
        if (!loadData[i]->sound || !loadData[i]->play)
        {
            continue;
        }

        FMOD_OPENSTATE state = FMOD_OPENSTATE_ERROR;
        FMOD_RESULT result = loadData[i]->sound->getOpenState(&state, 0, 0, 0);

        if (result != FMOD_OK)
        {
            logError(result, "getOpenState");
            stopAndReleaseChannel(i);
            continue;
        }

        if (state == FMOD_OPENSTATE_READY)
        {
            loadData[i]->play = false;

            FMOD_MODE mode = loadData[i]->mode;
            if (mode & FMOD_3D)
            {
                mode |= FMOD_3D_INVERSETAPEREDROLLOFF;
            }

            logError(loadData[i]->sound->setMode(mode), "FMOD::Sound::setMode");
            if (mode & FMOD_3D)
            {
                logError(loadData[i]->sound->set3DMinMaxDistance(1, 10), "set3DMinMaxDistance");
            }

            unsigned int lengthMs = 0;
            logError(loadData[i]->sound->getLength(&lengthMs, FMOD_TIMEUNIT_MS), "getLength");
            int32_t startPos = min(max(loadData[i]->startPos, 0), lengthMs);

            float volume = max(0, loadData[i]->volume);

            FMOD_RESULT result = pSystem->playSound(loadData[i]->sound, nullptr, false, &pChannels[i]);
            logError(result, "FMOD::System::playSound");
            if (result != FMOD_OK || !pChannels[i])
            {
                if (result == FMOD_OK)
                {
                    sdk->logger->ErrorF(handle, "%s", "FMOD::System::playSound returned a null channel");
                }

                stopAndReleaseChannel(i);
                continue;
            }

            logError(pChannels[i]->setPosition(startPos, FMOD_TIMEUNIT_MS), "FMOD::Channel::setPosition");
            logError(pChannels[i]->setVolume(volume), "FMOD::Channel::setVolume");

            setFadeIn(pChannels[i], loadData[i]->fade);
        } else if(state == FMOD_OPENSTATE_ERROR) {
            if (failedConnections.contains(loadData[i]->path))
            {
                failedConnections[loadData[i]->path]++;
            }
            else
            {
                failedConnections[loadData[i]->path] = 1;
            }

            sdk->logger->ErrorF(
                handle, "Failed to load sound for channel %i. This has been attempt number %i for that resource.", i,
                failedConnections[loadData[i]->path]);
            stopAndReleaseChannel(i);
        }
    }
}

bool Running_OnEnter(RED4ext::CGameApplication* aApp)
{
    return true;
}

bool Running_OnUpdate(RED4ext::CGameApplication* aApp)
{
    if (!systemInitialized || !pSystem || !loadData[0])
    {
        return false;
    }

    checkSoundLoad();
    pSystem->update();
    return false;
}

bool Running_OnExit(RED4ext::CGameApplication* aApp)
{
    releaseChannelData();

    return true;
}

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle aHandle, RED4ext::v1::EMainReason aReason, const RED4ext::v1::Sdk* aSdk)
{
    switch (aReason)
    {
    case RED4ext::v1::EMainReason::Load:
    {
        sdk = aSdk;
        handle = aHandle;
        gameBinDir = getGameBinDir();
        if (gameBinDir.empty())
        {
            sdk->logger->ErrorF(handle, "%s", "Failed to determine the game executable directory");
            return false;
        }

        FMOD_RESULT result = FMOD::System_Create(&pSystem);
        logError(result, "FMOD::System_Create");
        if (result != FMOD_OK || !pSystem)
        {
            pSystem = nullptr;
            return false;
        }

        result = pSystem->init(channelCount + 1, FMOD_INIT_3D_RIGHTHANDED, nullptr);
        logError(result, "FMOD::System::init");
        if (result != FMOD_OK)
        {
            logError(pSystem->release(), "FMOD::System::release");
            pSystem = nullptr;
            return false;
        }

        systemInitialized = true;
        logError(pSystem->set3DSettings(1, 1, 0.325), "FMOD::System::set3DSettings");

        for (int i = 0; i <= channelCount; i++)
        {
            loadData[i] = new SoundLoadData{};
        }

        RED4ext::v1::GameState updateState;
        updateState.OnEnter = &Running_OnEnter;
        updateState.OnUpdate = &Running_OnUpdate;
        updateState.OnExit = &Running_OnExit;
        aSdk->gameStates->Add(aHandle, RED4ext::EGameStateType::Running, &updateState);

        RED4ext::CRTTISystem::Get()->AddRegisterCallback(RegisterTypes);
        RED4ext::CRTTISystem::Get()->AddPostRegisterCallback(PostRegisterTypes);

        break;
    }
    case RED4ext::v1::EMainReason::Unload:
    {
        releaseChannelData();

        if (pSystem)
        {
            if (systemInitialized)
            {
                logError(pSystem->close(), "FMOD::System::close");
            }

            logError(pSystem->release(), "FMOD::System::release");
            pSystem = nullptr;
        }

        systemInitialized = false;
        break;
    }
    }

    return true;
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* aInfo)
{
    aInfo->name = L"RadioExt";
    aInfo->author = L"keanuWheeze";
    aInfo->version = radioExtVersion;
    aInfo->runtime = RED4EXT_V1_RUNTIME_VERSION_INDEPENDENT;
    aInfo->sdk = RED4EXT_V1_SDK_VERSION_1_0_0_COMPAT_0_5_0;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_1_COMPAT_0;
}
