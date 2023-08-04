#include <RED4ext/RED4ext.hpp>
#include <RED4ext/RTTITypes.hpp>
#include <RED4ext/Scripting/IScriptable.hpp>
#include <fmod.hpp>
#include <fmod_errors.h>

#define RADIOEXT_VERSION 0.1

const RED4ext::Sdk* sdk;
RED4ext::PluginHandle handle;
FMOD::System* pSystem;
FMOD::Channel* pChannelV; // Vehicle Radio channel
FMOD::Channel* pChannels[32]; // Physical radio channels

// General purpose functions
void GetRadioExtVersion(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4);
void GetFolders(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, RED4ext::DynArray<RED4ext::CString>* aOut, int64_t a4);
void GetSongLength(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t a4);

// Vehicle Radio functions
void PlayV(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4);
void StopV(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4);
void PauseV(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4);
void ResumeV(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4);
void SetVolumeV(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4);

// World Radio functions
void PlayR(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4);

// Red4Ext Stuff
void registerGeneralFunctions(RED4ext::CRTTISystem* rtti);
void registerVehicleRadioFunctions(RED4ext::CRTTISystem* rtti);

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
    registerVehicleRadioFunctions(rtti);
}

void registerGeneralFunctions(RED4ext::CRTTISystem* rtti)
{
    auto getLength = RED4ext::CClassStaticFunction::Create(&cls, "GetSongLength", "GetSongLength", &GetSongLength,
                                                           {.isNative = true, .isStatic = true});
    getLength->AddParam("String", "path");
    getLength->SetReturnType("Int32");

    auto getVersion = RED4ext::CClassStaticFunction::Create(&cls, "GetVersion", "GetVersion", &GetRadioExtVersion,
                                                            {.isNative = true, .isStatic = true});
    getVersion->SetReturnType("Float");

    auto getFolders = RED4ext::CClassStaticFunction::Create(&cls, "GetFolders", "GetFolders", &GetFolders,
                                                            {.isNative = true, .isStatic = true});
    getFolders->AddParam("String", "path");
    getFolders->SetReturnType("array:String");

    cls.RegisterFunction(getLength);
    cls.RegisterFunction(getVersion);
    cls.RegisterFunction(getFolders);
}

void registerVehicleRadioFunctions(RED4ext::CRTTISystem* rtti)
{
    auto playV = RED4ext::CClassStaticFunction::Create(&cls, "PlayV", "PlayV", &PlayV, {.isNative = true, .isStatic = true});
    playV->AddParam("String", "path");
    playV->AddParam("Int32", "startPos");
    playV->AddParam("Float", "volume");

    auto setVolumeV = RED4ext::CClassStaticFunction::Create(&cls, "SetVolumeV", "SetVolumeV", &SetVolumeV, {.isNative = true, .isStatic = true});
    setVolumeV->AddParam("Float", "volume");

    auto stopV = RED4ext::CClassStaticFunction::Create(&cls, "StopV", "StopV", &StopV, {.isNative = true, .isStatic = true});
    auto pauseV = RED4ext::CClassStaticFunction::Create(&cls, "PauseV", "PauseV", &PauseV, {.isNative = true, .isStatic = true});
    auto resumeV = RED4ext::CClassStaticFunction::Create(&cls, "ResumeV", "ResumeV", &ResumeV, {.isNative = true, .isStatic = true});

    cls.RegisterFunction(playV);
    cls.RegisterFunction(setVolumeV);
    cls.RegisterFunction(stopV);
    cls.RegisterFunction(pauseV);
    cls.RegisterFunction(resumeV);
}

void GetSongLength(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);

    RED4ext::CString path;
    RED4ext::GetParameter(aFrame, &path);
    std::filesystem::path subDir = path.c_str();
    std::filesystem::path target = std::filesystem::current_path() / subDir;
    sdk->logger->InfoF(handle, "GetSongLength(\"%s\")", target.c_str());

    unsigned int length = 0;

    FMOD::Sound* sound;
    FMOD_RESULT error = pSystem->createSound(target.string().c_str(), FMOD_CREATESTREAM, nullptr, &sound);
    // Only log if there is an error, as this gets called for allll the songs
    if (error != FMOD_OK)
    {
        sdk->logger->InfoF(handle, "FMOD::System::createSound: %s", FMOD_ErrorString(error));
    }

    error = sound->getLength(&length, FMOD_TIMEUNIT_MS);
    if (error != FMOD_OK)
    {
        sdk->logger->InfoF(handle, "FMOD::System::getLength: %s", FMOD_ErrorString(error));
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

void PlayV(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);

    RED4ext::CString path;
    int32_t startPos;
    float volume;
    RED4ext::GetParameter(aFrame, &path);
    RED4ext::GetParameter(aFrame, &startPos);
    RED4ext::GetParameter(aFrame, &volume);
    sdk->logger->InfoF(handle, "PlayV(\"%s\", %i, %f)", path.c_str(), startPos, volume);

    FMOD::Sound* sound;
    sdk->logger->InfoF(handle, "FMOD::System::createSound: %s", FMOD_ErrorString(pSystem->createSound(path.c_str(), FMOD_CREATESTREAM, nullptr, &sound)));

    unsigned int lengthMs = 0;
    sound->getLength(&lengthMs, FMOD_TIMEUNIT_MS);
    startPos = min(max(startPos, 0), lengthMs);

    volume = max(0, volume);

    sdk->logger->InfoF(handle, "FMOD::System::playSound: %s", FMOD_ErrorString(pSystem->playSound(sound, nullptr, false, &pChannelV)));
    sdk->logger->InfoF(handle, "FMOD::Channel::setPosition: %s", FMOD_ErrorString(pChannelV->setPosition(startPos, FMOD_TIMEUNIT_MS)));
    sdk->logger->InfoF(handle, "FMOD::Channel::setVolume: %s", FMOD_ErrorString(pChannelV->setVolume(volume)));

    aFrame->code++; // skip ParamEnd
}

void SetVolumeV(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);

    float volume;
    RED4ext::GetParameter(aFrame, &volume);
    sdk->logger->InfoF(handle, "SetVolume(%f)", volume);

    volume = max(0, volume);

    if (pChannelV)
    {
        sdk->logger->InfoF(handle, "FMOD::Channel::setVolume: %s", FMOD_ErrorString(pChannelV->setVolume(volume)));
    }

    aFrame->code++; // skip ParamEnd
}

void StopV(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aFrame);

    if (pChannelV)
    {
        pChannelV->stop();
        pChannelV = nullptr;
        sdk->logger->Info(handle, "Stopped vehicle radio");
    }

    aFrame->code++; // skip ParamEnd
}

void PauseV(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aFrame);

    if (pChannelV)
    {
        pChannelV->setPaused(true);
        sdk->logger->Info(handle, "Paused vehicle radio");
    }

    aFrame->code++; // skip ParamEnd
}

void ResumeV(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aFrame);

    if (pChannelV)
    {
        pChannelV->setPaused(false);
        sdk->logger->Info(handle, "Resumed vehicle radio");
    }

    aFrame->code++; // skip ParamEnd
}

void PlayR(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);

    RED4ext::CString path;
    int32_t startPos;
    float volume;
    int32_t id;
    RED4ext::GetParameter(aFrame, &path);
    RED4ext::GetParameter(aFrame, &startPos);
    RED4ext::GetParameter(aFrame, &volume);
    RED4ext::GetParameter(aFrame, &id);
    sdk->logger->InfoF(handle, "PlayR(\"%s\", %i, %f, %i)", path.c_str(), startPos, volume, id);

    FMOD::Sound* sound;
    sdk->logger->InfoF(handle, "FMOD::System::createSound: %s", FMOD_ErrorString(pSystem->createStream(path.c_str(), FMOD_3D, nullptr, &sound)));

    unsigned int lengthMs = 0;
    sound->getLength(&lengthMs, FMOD_TIMEUNIT_MS);
    startPos = min(max(startPos, 0), lengthMs);

    volume = max(0, volume);

    sdk->logger->InfoF(handle, "FMOD::System::playSound: %s", FMOD_ErrorString(pSystem->playSound(sound, nullptr, false, &pChannels[id])));
    sdk->logger->InfoF(handle, "FMOD::Channel::setPosition: %s", FMOD_ErrorString(pChannelV->setPosition(startPos, FMOD_TIMEUNIT_MS)));
    sdk->logger->InfoF(handle, "FMOD::Channel::setVolume: %s", FMOD_ErrorString(pChannelV->setVolume(volume)));

    aFrame->code++; // skip ParamEnd
}

bool Running_OnEnter(RED4ext::CGameApplication* aApp)
{
    return true;
}

bool Running_OnUpdate(RED4ext::CGameApplication* aApp)
{
    pSystem->update();
    return false;
}

bool Running_OnExit(RED4ext::CGameApplication* aApp)
{
    if (pChannelV)
    {
        pChannelV->stop();
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
        sdk->logger->InfoF(handle, "FMOD::System::init %s", FMOD_ErrorString(pSystem->init(32, FMOD_INIT_NORMAL, nullptr)));

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
