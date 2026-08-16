#include <RED4ext/RED4ext.hpp>
#include <RED4ext/RTTITypes.hpp>
#include <RED4ext/Scripting/IScriptable.hpp>
#include <RED4ext/Scripting/Natives/Generated/Vector4.hpp>
#include <fmod.hpp>
#include <fmod_errors.h>
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <unordered_map>
#include "SoundLoadData.hpp"

namespace
{
// ---------------------------------------------------------------------------
// Constants (prefer constexpr over #define per modern C++ practice)
// ---------------------------------------------------------------------------

constexpr const char* RadioExtVersion = "0.9.0";
constexpr int32_t ChannelCount = 64;
constexpr int32_t MaxLoadAttempts = 3;

// ---------------------------------------------------------------------------
// Forward declarations
// ---------------------------------------------------------------------------

// Forward-declared so that helpers below can reference it.
struct RadioExt;

// ---------------------------------------------------------------------------
// File-scope state (anonymous namespace = internal linkage)
// ---------------------------------------------------------------------------

// Native class setup — must be fully defined before TTypedClass<RadioExt> below
struct RadioExt : RED4ext::IScriptable
{
    RED4ext::CClass* GetNativeType();
};

const RED4ext::v1::Sdk* Sdk = nullptr;
RED4ext::v1::PluginHandle PluginHandle = nullptr;
std::filesystem::path GameExePath;
FMOD::System* AudioSystem = nullptr;

// Index 0 is the vehicle radio (Lua sentinel -1 maps here internally).
// Indices 1..ChannelCount are physical radios.
FMOD::Channel* Channels[ChannelCount + 1] = {};

// Transient load state per channel, used while a sound is loading asynchronously.
SoundLoadData* LoadData[ChannelCount + 1] = {};

// Tracks how many times a given resource path has failed to load; after
// MaxLoadAttempts, further Play() calls for that path are rejected.
std::unordered_map<std::string, uint32_t> FailedConnections;

// The native RTTI class descriptor for the RadioExt IScriptable.
RED4ext::TTypedClass<RadioExt> RadioExtClass("RadioExt");

// ---------------------------------------------------------------------------
// Forward declarations — native function handlers (registered into RTTI)
// ---------------------------------------------------------------------------

void GetRadioExtVersion(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut,
                        int64_t aUnused);
void GetNumChannels(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t aUnused);
void GetFolders(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame,
                RED4ext::DynArray<RED4ext::CString>* aOut, int64_t aUnused);
void GetSongLength(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t aUnused);

void Play(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t aUnused);
void Stop(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t aUnused);
void SetVolume(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t aUnused);
void SetListenerTransform(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t aUnused);
void SetChannelTransform(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t aUnused);
void Set3DFalloff(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t aUnused);
void Set3DMinMax(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t aUnused);

void RegisterGeneralFunctions(RED4ext::CRTTISystem* aRtti);
void RegisterAudioFunctions(RED4ext::CRTTISystem* aRtti);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Normalizes a Lua-side channel ID into a valid C++ array index.
/// The Lua side uses -1 as the vehicle-radio sentinel; internally we map
/// that to slot 0. Any other out-of-range value is clamped to [0, ChannelCount].
int32_t NormalizeChannelId(int32_t aChannelId)
{
    if (aChannelId == -1)
    {
        return 0;
    }
    return std::clamp(aChannelId, 0, ChannelCount);
}

/// Converts a RED4ext::Vector4 to an FMOD_VECTOR, applying the axis
/// remapping required by RED4ext's left-handed coordinate system.
FMOD_VECTOR ToFmodVector(const RED4ext::Vector4& aVec, RED4ext::CClass* aVector4Class)
{
    auto xProp = aVector4Class->GetProperty("X");
    auto yProp = aVector4Class->GetProperty("Y");
    auto zProp = aVector4Class->GetProperty("Z");

    FMOD_VECTOR result;
    result.x = -xProp->GetValue<float>(&const_cast<RED4ext::Vector4&>(aVec));
    result.y = zProp->GetValue<float>(&const_cast<RED4ext::Vector4&>(aVec));
    result.z = yProp->GetValue<float>(&const_cast<RED4ext::Vector4&>(aVec));
    return result;
}

// Provided by WSSDude / Andrej Redeky
std::filesystem::path GetExePath()
{
    wchar_t exePathBuffer[MAX_PATH]{0};
    GetModuleFileNameW(GetModuleHandle(nullptr), exePathBuffer, std::size(exePathBuffer));
    return std::filesystem::path(exePathBuffer);
}

void LogFmodError(FMOD_RESULT aResult, const char* aMessage)
{
    if (aResult != FMOD_OK)
    {
        Sdk->logger->ErrorF(PluginHandle, "%s: %s", aMessage, FMOD_ErrorString(aResult));
    }
}

/// Returns true if the FMOD error is one of the expected "channel handoff"
/// errors that occur when FMOD reuses a channel slot internally. These are
/// not real errors — they happen during normal operation when a new sound
/// steals a channel that was still being referenced by an old pointer.
/// Logging them at error level caused massive log spam (1000+ lines) when
/// multiple custom stations were active or when other radio mods were installed.
///
/// FMOD's error code names have shifted across versions: older SDKs used
/// FMOD_ERR_CHANNEL_REUSE and FMOD_ERR_CHANNEL_STOLEN, while newer ones
/// (2.02+) consolidated these. We use #ifdef guards so the code compiles
/// against any FMOD SDK version. As a final fallback, we match the error
/// string returned by FMOD_ErrorString, so even unknown error codes with
/// the "channel has been reused" / "invalid handle" text are recognized.
bool IsExpectedHandoffError(FMOD_RESULT aResult)
{
    if (aResult == FMOD_OK)
    {
        return false;
    }

    // Known error codes (present in most FMOD versions)
#ifdef FMOD_ERR_INVALID_HANDLE
    if (aResult == FMOD_ERR_INVALID_HANDLE) return true;
#endif
#ifdef FMOD_ERR_CHANNEL_REUSE
    if (aResult == FMOD_ERR_CHANNEL_REUSE) return true;
#endif
#ifdef FMOD_ERR_CHANNEL_STOLEN
    if (aResult == FMOD_ERR_CHANNEL_STOLEN) return true;
#endif

    // String-based fallback for FMOD versions where the error code name
    // differs but the error message text is the same.
    const char* errStr = FMOD_ErrorString(aResult);
    if (errStr != nullptr)
    {
        // "The specified channel has been reused to play another sound." (FMOD 2.02+)
        // "Invalid handle" / "The handle is invalid."
        return std::strstr(errStr, "reused") != nullptr
            || std::strstr(errStr, "Invalid handle") != nullptr
            || std::strstr(errStr, "invalid handle") != nullptr;
    }

    return false;
}

/// Same as LogFmodError but suppresses expected channel-handoff errors.
/// Use this for operations on channels that may have been reused by FMOD
/// between the time the pointer was stored and the time it is used.
void LogFmodErrorSilent(FMOD_RESULT aResult, const char* aMessage)
{
    if (aResult != FMOD_OK && !IsExpectedHandoffError(aResult))
    {
        Sdk->logger->ErrorF(PluginHandle, "%s: %s", aMessage, FMOD_ErrorString(aResult));
    }
}

/// Probes whether a cached FMOD::Channel* pointer is still valid.
/// FMOD reuses channel slots internally: when a new sound steals a channel,
/// the old FMOD::Channel* handle becomes invalid and any operation on it
/// returns FMOD_ERR_INVALID_HANDLE or FMOD_ERR_CHANNEL_REUSE.
/// We probe with isPlaying() (a lightweight call) to detect this. If the
/// channel is stale, the caller should null out its cached pointer.
bool IsChannelValid(FMOD::Channel* aChannel)
{
    if (aChannel == nullptr)
    {
        return false;
    }
    bool playing = false;
    auto result = aChannel->isPlaying(&playing);
    // FMOD_OK means the handle is valid (whether or not the channel is
    // currently playing). Any other return value means the handle is stale.
    return result == FMOD_OK;
}

void SetFadeIn(FMOD::Channel* aChannel, float aDuration)
{
    // Guard against stale channel handles. FMOD may have reused the channel
    // slot between the playSound() call and this fade-in setup.
    if (!IsChannelValid(aChannel))
    {
        return;
    }

    LogFmodErrorSilent(aChannel->setPaused(true), "setPaused(true)");

    auto dspClock = 0ull;
    auto rate = 0;

    FMOD::System* system = nullptr;
    LogFmodErrorSilent(aChannel->getSystemObject(&system), "getSystemObject");
    if (system == nullptr)
    {
        return;
    }
    LogFmodErrorSilent(system->getSoftwareFormat(&rate, nullptr, nullptr), "getSoftwareFormat");
    LogFmodErrorSilent(aChannel->getDSPClock(nullptr, &dspClock), "getDSPClock");
    LogFmodErrorSilent(aChannel->addFadePoint(dspClock, 0.0f), "addFadePoint");
    LogFmodErrorSilent(aChannel->addFadePoint(dspClock + (rate * aDuration), 1.0f), "addFadePoint");
    LogFmodErrorSilent(aChannel->setPaused(false), "setPaused(false)");
}

// ---------------------------------------------------------------------------
// Native class GetNativeType implementation
// ---------------------------------------------------------------------------

RED4ext::CClass* RadioExt::GetNativeType()
{
    return &RadioExtClass;
}

void RegisterGeneralFunctions(RED4ext::CRTTISystem* aRtti)
{
    RED4EXT_UNUSED_PARAMETER(aRtti);

    auto getLength = RED4ext::CClassStaticFunction::Create(&RadioExtClass, "GetSongLength", "GetSongLength",
                                                           &GetSongLength, {.isNative = true, .isStatic = true});
    getLength->AddParam("String", "path");
    getLength->SetReturnType("Int32");

    auto getVersion = RED4ext::CClassStaticFunction::Create(&RadioExtClass, "GetVersion", "GetVersion",
                                                            &GetRadioExtVersion, {.isNative = true, .isStatic = true});
    getVersion->SetReturnType("String");

    auto getChannels = RED4ext::CClassStaticFunction::Create(&RadioExtClass, "GetNumChannels", "GetNumChannels",
                                                              &GetNumChannels, {.isNative = true, .isStatic = true});
    getChannels->SetReturnType("Int32");

    auto getFolders = RED4ext::CClassStaticFunction::Create(&RadioExtClass, "GetFolders", "GetFolders", &GetFolders,
                                                            {.isNative = true, .isStatic = true});
    getFolders->AddParam("String", "path");
    getFolders->SetReturnType("array:String");

    RadioExtClass.RegisterFunction(getLength);
    RadioExtClass.RegisterFunction(getVersion);
    RadioExtClass.RegisterFunction(getFolders);
    RadioExtClass.RegisterFunction(getChannels);
}

void RegisterAudioFunctions(RED4ext::CRTTISystem* aRtti)
{
    RED4EXT_UNUSED_PARAMETER(aRtti);

    auto play = RED4ext::CClassStaticFunction::Create(&RadioExtClass, "Play", "Play", &Play,
                                                       {.isNative = true, .isStatic = true});
    play->AddParam("Int32", "channelID");
    play->AddParam("String", "path");
    play->AddParam("Int32", "startPos"); // -1 indicates stream
    play->AddParam("Float", "volume");
    play->AddParam("Float", "fade");

    auto setVolume = RED4ext::CClassStaticFunction::Create(&RadioExtClass, "SetVolume", "SetVolume", &SetVolume,
                                                            {.isNative = true, .isStatic = true});
    setVolume->AddParam("Int32", "channelID");
    setVolume->AddParam("Float", "volume");

    auto setFalloff = RED4ext::CClassStaticFunction::Create(&RadioExtClass, "Set3DFalloff", "Set3DFalloff",
                                                             &Set3DFalloff, {.isNative = true, .isStatic = true});
    setFalloff->AddParam("Float", "falloff");

    auto stop = RED4ext::CClassStaticFunction::Create(&RadioExtClass, "Stop", "Stop", &Stop,
                                                      {.isNative = true, .isStatic = true});
    stop->AddParam("Int32", "channelID");

    auto setListener = RED4ext::CClassStaticFunction::Create(&RadioExtClass, "SetListener", "SetListener",
                                                              &SetListenerTransform, {.isNative = true, .isStatic = true});
    setListener->AddParam("Vector4", "pos");
    setListener->AddParam("Vector4", "forward");
    setListener->AddParam("Vector4", "up");

    auto setChannelPos = RED4ext::CClassStaticFunction::Create(&RadioExtClass, "SetChannelPos", "SetChannelPos",
                                                                &SetChannelTransform, {.isNative = true, .isStatic = true});
    setChannelPos->AddParam("Int32", "channelID");
    setChannelPos->AddParam("Vector4", "pos");

    auto setMinMax = RED4ext::CClassStaticFunction::Create(&RadioExtClass, "SetMinMax", "SetMinMax", &Set3DMinMax,
                                                            {.isNative = true, .isStatic = true});
    setMinMax->AddParam("Float", "min");
    setMinMax->AddParam("Float", "max");

    RadioExtClass.RegisterFunction(play);
    RadioExtClass.RegisterFunction(setVolume);
    RadioExtClass.RegisterFunction(setFalloff);
    RadioExtClass.RegisterFunction(stop);
    RadioExtClass.RegisterFunction(setListener);
    RadioExtClass.RegisterFunction(setChannelPos);
    RadioExtClass.RegisterFunction(setMinMax);
}

// ---------------------------------------------------------------------------
// Native function implementations
// ---------------------------------------------------------------------------

void GetSongLength(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t aUnused)
{
    RED4EXT_UNUSED_PARAMETER(aUnused);
    RED4EXT_UNUSED_PARAMETER(aContext);

    RED4ext::CString path;
    RED4ext::GetParameter(aFrame, &path);
    auto subDir = std::filesystem::path(path.c_str());
    auto target = GameExePath.parent_path() / subDir;

    auto length = 0u;

    FMOD::Sound* sound = nullptr;
    auto createResult = AudioSystem->createSound(target.string().c_str(), FMOD_CREATESTREAM, nullptr, &sound);
    // Only log if there is an error, as this gets called for all the songs
    if (createResult != FMOD_OK || sound == nullptr)
    {
        Sdk->logger->ErrorF(PluginHandle, "FMOD::System::createSound: %s. Requested Path: %s",
                            FMOD_ErrorString(createResult), target.string().c_str());
        if (aOut)
        {
            auto type = RED4ext::CRTTISystem::Get()->GetType("Int32");
            type->Assign(aOut, &length);
        }
        aFrame->code++; // skip ParamEnd
        return;
    }

    auto lengthResult = sound->getLength(&length, FMOD_TIMEUNIT_MS);
    if (lengthResult != FMOD_OK)
    {
        Sdk->logger->ErrorF(PluginHandle, "FMOD::System::getLength: %s. Requested Path: %s",
                            FMOD_ErrorString(lengthResult), target.string().c_str());
    }

    // Release the temporary sound used only for length probing to avoid leaking FMOD resources.
    sound->release();

    if (aOut)
    {
        auto type = RED4ext::CRTTISystem::Get()->GetType("Int32");
        type->Assign(aOut, &length);
    }

    aFrame->code++; // skip ParamEnd
}

void GetFolders(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame,
                RED4ext::DynArray<RED4ext::CString>* aOut, int64_t aUnused)
{
    RED4EXT_UNUSED_PARAMETER(aUnused);
    RED4EXT_UNUSED_PARAMETER(aContext);

    RED4ext::CString path;
    RED4ext::GetParameter(aFrame, &path);
    auto subDir = std::filesystem::path(path.c_str());
    auto target = GameExePath.parent_path() / subDir;
    Sdk->logger->InfoF(PluginHandle, "GetFolders(%s)", target.string().c_str());

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

void GetNumChannels(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t aUnused)
{
    RED4EXT_UNUSED_PARAMETER(aUnused);
    RED4EXT_UNUSED_PARAMETER(aContext);

    auto channels = ChannelCount;

    if (aOut)
    {
        auto type = RED4ext::CRTTISystem::Get()->GetType("Int32");
        type->Assign(aOut, &channels);
    }

    aFrame->code++; // skip ParamEnd
}

void GetRadioExtVersion(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut,
                        int64_t aUnused)
{
    RED4EXT_UNUSED_PARAMETER(aUnused);
    RED4EXT_UNUSED_PARAMETER(aContext);

    RED4ext::CString version = RadioExtVersion;
    if (aOut)
    {
        auto type = RED4ext::CRTTISystem::Get()->GetType("String");
        type->Assign(aOut, &version);
    }

    aFrame->code++; // skip ParamEnd
}

void Play(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t aUnused)
{
    RED4EXT_UNUSED_PARAMETER(aUnused);
    RED4EXT_UNUSED_PARAMETER(aContext);

    int32_t channelId;
    RED4ext::CString path;
    int32_t startPos;
    float volume;
    float fade;
    RED4ext::GetParameter(aFrame, &channelId);
    RED4ext::GetParameter(aFrame, &path);
    RED4ext::GetParameter(aFrame, &startPos);
    RED4ext::GetParameter(aFrame, &volume);
    RED4ext::GetParameter(aFrame, &fade);
    Sdk->logger->InfoF(PluginHandle, "Play(%i, \"%s\", %i, %f, %f)", channelId, path.c_str(), startPos, volume, fade);

    auto normalizedId = NormalizeChannelId(channelId);

    if (LoadData[normalizedId]->play == true)
    {
        aFrame->code++; // skip ParamEnd
        return;
    }

    auto subDir = std::filesystem::path(path.c_str());
    auto target = GameExePath.parent_path() / subDir;

    if (startPos == -1) // Is a stream
    {
        target = subDir;
    }

    if (FailedConnections.contains(target.string()))
    {
        if (FailedConnections[target.string()] >= MaxLoadAttempts)
        {
            Sdk->logger->ErrorF(PluginHandle, "Resource %s has exceeded maximum amount of load attempts.",
                                target.string().c_str());
            aFrame->code++; // skip ParamEnd
            return;
        }
    }

    FMOD_MODE mode = FMOD_3D;
    if (channelId == -1)
    {
        mode = FMOD_DEFAULT;
    }

    // Release any previously loading sound on this channel before overwriting the slot,
    // otherwise we leak the FMOD::Sound handle when the channel is reused while still loading.
    if (LoadData[normalizedId]->sound != nullptr)
    {
        LoadData[normalizedId]->sound->release();
        LoadData[normalizedId]->sound = nullptr;
    }

    auto createResult = AudioSystem->createStream(target.string().c_str(), mode | FMOD_NONBLOCKING, nullptr,
                                                   &LoadData[normalizedId]->sound);
    Sdk->logger->InfoF(PluginHandle, "FMOD::System::createSound: %s", FMOD_ErrorString(createResult));
    if (createResult != FMOD_OK)
    {
        // createStream failed; do not mark the slot as playing, otherwise CheckSoundLoad
        // would dereference an invalid sound pointer on the next tick.
        LoadData[normalizedId]->play = false;
        LoadData[normalizedId]->sound = nullptr;
        aFrame->code++; // skip ParamEnd
        return;
    }

    LoadData[normalizedId]->fade = fade;
    LoadData[normalizedId]->startPos = startPos;
    LoadData[normalizedId]->volume = volume;
    LoadData[normalizedId]->play = true; // Sound is loading, check if loading has finished
    LoadData[normalizedId]->path = target.string();
    aFrame->code++; // skip ParamEnd
}

void SetVolume(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t aUnused)
{
    RED4EXT_UNUSED_PARAMETER(aUnused);
    RED4EXT_UNUSED_PARAMETER(aContext);

    int32_t channelId;
    float volume;
    RED4ext::GetParameter(aFrame, &channelId);
    RED4ext::GetParameter(aFrame, &volume);
    Sdk->logger->InfoF(PluginHandle, "SetVolume(%i, %f)", channelId, volume);

    volume = std::max(0.0f, volume);
    auto normalizedId = NormalizeChannelId(channelId);

    if (Channels[normalizedId])
    {
        if (IsChannelValid(Channels[normalizedId]))
        {
            Sdk->logger->InfoF(PluginHandle, "FMOD::Channel::setVolume: %s",
                               FMOD_ErrorString(Channels[normalizedId]->setVolume(volume)));
        }
        else
        {
            // Channel was reused by FMOD; clear the stale pointer.
            Channels[normalizedId] = nullptr;
        }
    }

    aFrame->code++; // skip ParamEnd
}

void Set3DFalloff(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t aUnused)
{
    RED4EXT_UNUSED_PARAMETER(aUnused);
    RED4EXT_UNUSED_PARAMETER(aContext);

    float falloff;
    RED4ext::GetParameter(aFrame, &falloff);
    Sdk->logger->InfoF(PluginHandle, "Set3DFalloff(%f)", falloff);

    Sdk->logger->InfoF(PluginHandle, "FMOD::System::set3DSettings: %s",
                       FMOD_ErrorString(AudioSystem->set3DSettings(1, 1, falloff)));

    aFrame->code++; // skip ParamEnd
}

void Set3DMinMax(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t aUnused)
{
    RED4EXT_UNUSED_PARAMETER(aUnused);
    RED4EXT_UNUSED_PARAMETER(aContext);

    float minDistance;
    float maxDistance;
    RED4ext::GetParameter(aFrame, &minDistance);
    RED4ext::GetParameter(aFrame, &maxDistance);

    for (auto i = 0; i <= ChannelCount; i++)
    {
        if (Channels[i])
        {
            if (IsChannelValid(Channels[i]))
            {
                LogFmodErrorSilent(Channels[i]->set3DMinMaxDistance(minDistance, maxDistance), "Set3DMinMax");
            }
            else
            {
                Channels[i] = nullptr;
            }
        }
    }

    aFrame->code++; // skip ParamEnd
}

void Stop(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t aUnused)
{
    RED4EXT_UNUSED_PARAMETER(aUnused);
    RED4EXT_UNUSED_PARAMETER(aContext);

    int32_t channelId;
    RED4ext::GetParameter(aFrame, &channelId);

    auto normalizedId = NormalizeChannelId(channelId);

    LoadData[normalizedId]->play = false;

    if (Channels[normalizedId])
    {
        // Use silent logging: if the channel was reused by FMOD, stop() returns
        // FMOD_ERR_INVALID_HANDLE / FMOD_ERR_CHANNEL_REUSE, which is expected
        // and should not spam the log.
        LogFmodErrorSilent(Channels[normalizedId]->stop(), "FMOD::Channel*->stop()");
        Channels[normalizedId] = nullptr;
        Sdk->logger->InfoF(PluginHandle, "Stopped channel %i", normalizedId);
    }

    aFrame->code++; // skip ParamEnd
}

void SetChannelTransform(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t aUnused)
{
    RED4EXT_UNUSED_PARAMETER(aUnused);
    RED4EXT_UNUSED_PARAMETER(aContext);

    int32_t channelId;
    RED4ext::Vector4 pos;
    RED4ext::GetParameter(aFrame, &channelId);
    RED4ext::GetParameter(aFrame, &pos);

    auto normalizedId = NormalizeChannelId(channelId);

    auto rtti = RED4ext::CRTTISystem::Get();
    auto vector4Class = rtti->GetClass("Vector4");

    auto posFmod = ToFmodVector(pos, vector4Class);

    if (Channels[normalizedId])
    {
        if (IsChannelValid(Channels[normalizedId]))
        {
            LogFmodErrorSilent(Channels[normalizedId]->set3DAttributes(&posFmod, nullptr),
                               "SetChannelTransform::set3DAttributes");
        }
        else
        {
            // Channel was reused by FMOD; clear the stale pointer so we don't
            // keep probing it on every frame.
            Channels[normalizedId] = nullptr;
        }
    }

    aFrame->code++; // skip ParamEnd
}

void SetListenerTransform(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t aUnused)
{
    RED4EXT_UNUSED_PARAMETER(aUnused);
    RED4EXT_UNUSED_PARAMETER(aContext);

    RED4ext::Vector4 pos;
    RED4ext::Vector4 forward;
    RED4ext::Vector4 up;
    RED4ext::GetParameter(aFrame, &pos);
    RED4ext::GetParameter(aFrame, &forward);
    RED4ext::GetParameter(aFrame, &up);

    auto rtti = RED4ext::CRTTISystem::Get();
    auto vector4Class = rtti->GetClass("Vector4");

    auto posFmod = ToFmodVector(pos, vector4Class);
    auto forwardFmod = ToFmodVector(forward, vector4Class);
    auto upFmod = ToFmodVector(up, vector4Class);

    FMOD_VECTOR velFmod{};
    LogFmodError(AudioSystem->set3DListenerAttributes(0, &posFmod, &velFmod, &forwardFmod, &upFmod),
                 "SetListenerTransform::set3DListenerAttributes");

    aFrame->code++; // skip ParamEnd
}

// ---------------------------------------------------------------------------
// Audio polling — called every frame while the game is running
// ---------------------------------------------------------------------------

void CheckSoundLoad()
{
    for (auto i = 0; i <= ChannelCount; i++)
    {
        if (!LoadData[i]->sound || !LoadData[i]->play)
        {
            continue;
        }

        FMOD_OPENSTATE state;
        auto result = LoadData[i]->sound->getOpenState(&state, nullptr, nullptr, nullptr);

        if (result != FMOD_OK)
        {
            LogFmodError(result, "getOpenState");
            LoadData[i]->play = false;
            // `state` may be uninitialized when getOpenState fails; skip the
            // rest of this iteration so we don't act on garbage state values.
            continue;
        }

        if (state == FMOD_OPENSTATE_READY)
        {
            LoadData[i]->play = false;

            Sdk->logger->InfoF(PluginHandle, "FMOD::Sound::setMode: %s",
                               FMOD_ErrorString(LoadData[i]->sound->setMode(FMOD_3D_INVERSETAPEREDROLLOFF)));
            LogFmodError(LoadData[i]->sound->set3DMinMaxDistance(1, 10), "set3DMinMaxDistance");

            auto lengthMs = 0u;
            LogFmodError(LoadData[i]->sound->getLength(&lengthMs, FMOD_TIMEUNIT_MS), "getLength");
            auto startPos = std::clamp(static_cast<int32_t>(LoadData[i]->startPos), 0, static_cast<int32_t>(lengthMs));

            auto volume = std::max(0.0f, LoadData[i]->volume);

            // Stop any previously active channel on this slot before starting a new one.
            // Use silent logging: if FMOD already reused this channel, stop() returns
            // an expected handoff error that should not spam the log.
            if (Channels[i] != nullptr)
            {
                LogFmodErrorSilent(Channels[i]->stop(), "CheckSoundLoad::stop previous channel");
                Channels[i] = nullptr;
            }

            auto playResult = AudioSystem->playSound(LoadData[i]->sound, nullptr, false, &Channels[i]);
            Sdk->logger->InfoF(PluginHandle, "FMOD::System::playSound: %s", FMOD_ErrorString(playResult));
            if (playResult != FMOD_OK || Channels[i] == nullptr)
            {
                // playSound failed; mark slot as not playing so we don't try to operate on a null channel.
                LoadData[i]->play = false;
                // Release the loaded sound; caller can retry by calling Play() again from Lua.
                LoadData[i]->sound->release();
                LoadData[i]->sound = nullptr;
            }
            else
            {
                // Validate the new channel before operating on it. In rare cases
                // FMOD can immediately reuse the slot between playSound and the
                // setPosition call below.
                if (IsChannelValid(Channels[i]))
                {
                    Sdk->logger->InfoF(PluginHandle, "FMOD::Channel::setPosition: %s",
                                       FMOD_ErrorString(Channels[i]->setPosition(startPos, FMOD_TIMEUNIT_MS)));
                    Sdk->logger->InfoF(PluginHandle, "FMOD::Channel::setVolume: %s",
                                       FMOD_ErrorString(Channels[i]->setVolume(volume)));

                    SetFadeIn(Channels[i], LoadData[i]->fade);
                }
                else
                {
                    Sdk->logger->InfoF(PluginHandle, "Channel %i became invalid immediately after playSound", i);
                    Channels[i] = nullptr;
                }
            }
        }
        else if (state == FMOD_OPENSTATE_ERROR)
        {
            if (FailedConnections.contains(LoadData[i]->path))
            {
                FailedConnections[LoadData[i]->path]++;
            }
            else
            {
                FailedConnections[LoadData[i]->path] = 1;
            }

            Sdk->logger->ErrorF(PluginHandle,
                                "Failed to load sound for channel %i. This has been attempt number %i for that resource.",
                                i, FailedConnections[LoadData[i]->path]);

            // Release the failed sound handle and clear the slot so the next Play() on this
            // channel does not reuse a stale pointer.
            LoadData[i]->sound->release();
            LoadData[i]->sound = nullptr;
            LoadData[i]->play = false;
        }
    }
}

// ---------------------------------------------------------------------------
// Game state callbacks
// ---------------------------------------------------------------------------

bool OnRunningEnter(RED4ext::CGameApplication* aApp)
{
    RED4EXT_UNUSED_PARAMETER(aApp);
    return true;
}

bool OnRunningUpdate(RED4ext::CGameApplication* aApp)
{
    RED4EXT_UNUSED_PARAMETER(aApp);
    CheckSoundLoad();
    AudioSystem->update();
    return false;
}

bool OnRunningExit(RED4ext::CGameApplication* aApp)
{
    RED4EXT_UNUSED_PARAMETER(aApp);

    for (auto i = 0; i <= ChannelCount; i++)
    {
        if (Channels[i])
        {
            Channels[i]->stop();
            Channels[i] = nullptr;
        }
        if (LoadData[i])
        {
            if (LoadData[i]->sound)
            {
                LoadData[i]->sound->release();
                LoadData[i]->sound = nullptr;
            }
            delete LoadData[i];
            LoadData[i] = nullptr;
        }
    }

    return true;
}

} // anonymous namespace

// ---------------------------------------------------------------------------
// RED4ext plugin exports (must have C linkage and external linkage —
// cannot live inside the anonymous namespace)
// ---------------------------------------------------------------------------

RED4EXT_C_EXPORT void RED4EXT_CALL RegisterTypes()
{
    RED4ext::CNamePool::Add("RadioExt");

    RadioExtClass.flags = {.isNative = true};
    RED4ext::CRTTISystem::Get()->RegisterType(&RadioExtClass);
}

RED4EXT_C_EXPORT void RED4EXT_CALL PostRegisterTypes()
{
    auto rtti = RED4ext::CRTTISystem::Get();
    auto scriptable = rtti->GetClass("IScriptable");
    RadioExtClass.parent = scriptable;

    RegisterGeneralFunctions(rtti);
    RegisterAudioFunctions(rtti);
}

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle aHandle, RED4ext::v1::EMainReason aReason,
                                        const RED4ext::v1::Sdk* aSdk)
{
    switch (aReason)
    {
    case RED4ext::v1::EMainReason::Load:
    {
        Sdk = aSdk;
        PluginHandle = aHandle;
        GameExePath = GetExePath();

        Sdk->logger->InfoF(PluginHandle, "FMOD::System_Create %s",
                           FMOD_ErrorString(FMOD::System_Create(&AudioSystem)));
        Sdk->logger->InfoF(PluginHandle, "FMOD::System::init %s",
                           FMOD_ErrorString(AudioSystem->init(ChannelCount, FMOD_INIT_3D_RIGHTHANDED, nullptr)));
        Sdk->logger->InfoF(PluginHandle, "FMOD::System::set3DSettings %s",
                           FMOD_ErrorString(AudioSystem->set3DSettings(1, 1, 0.325)));

        for (auto i = 0; i <= ChannelCount; i++)
        {
            LoadData[i] = new SoundLoadData;
            LoadData[i]->play = false;
        }

        RED4ext::v1::GameState runningState;
        runningState.OnEnter = &OnRunningEnter;
        runningState.OnUpdate = &OnRunningUpdate;
        runningState.OnExit = &OnRunningExit;
        aSdk->gameStates->Add(aHandle, RED4ext::EGameStateType::Running, &runningState);

        RED4ext::CRTTISystem::Get()->AddRegisterCallback(RegisterTypes);
        RED4ext::CRTTISystem::Get()->AddPostRegisterCallback(PostRegisterTypes);

        break;
    }
    case RED4ext::v1::EMainReason::Unload:
    {
        AudioSystem->close();
        AudioSystem->release();
        break;
    }
    }

    return true;
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* aInfo)
{
    aInfo->name = L"RadioExt";
    aInfo->author = L"keanuWheeze";
    aInfo->version = RED4EXT_V1_SEMVER(2, 3, 0);
    aInfo->runtime = RED4EXT_V1_RUNTIME_VERSION_INDEPENDENT;
    aInfo->sdk = RED4EXT_V1_SDK_VERSION_CURRENT;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_1;
}
