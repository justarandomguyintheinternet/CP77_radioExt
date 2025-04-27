#define WIN32_LEAN_AND_MEAN 
#define _CRT_SECURE_NO_WARNINGS
#define CURL_STATICLIB
#include <RED4ext/RED4ext.hpp>
#include <RED4ext/RTTITypes.hpp>
#include <RED4ext/Scripting/IScriptable.hpp>
#include <RED4ext/Scripting/Natives/Generated/Vector4.hpp>
#include <fmod.hpp>
#include <fmod_errors.h>
#include "SoundLoadData.hpp"
#include <filesystem>
#include <string>
#include <WinSock2.h>
#include <WS2tcpip.h>
#include <Windows.h>
#include <cstdio>
#include <vector>
#include <unordered_map>
#include <mutex>
#include <windows.h>
#include <curl/curl.h>
#include <thread>
#include <chrono>
#include <sstream>
#include <fstream>
#include <nlohmann/json.hpp>

#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "libcurl.lib")

#define RADIOEXT_VERSION 0.7
#define CHANNELS 256

std::unordered_map<std::string, std::pair<int, std::shared_ptr<PROCESS_INFORMATION>>> activeRelays;
std::unordered_map<std::string, std::string> relayUrlCache; // original URL -> relay URL
std::mutex relayMutex;
bool icecastStarted = false;

const RED4ext::Sdk* sdk;
RED4ext::PluginHandle handle;
std::filesystem::path root;
FMOD::System* pSystem;
FMOD::Channel* pChannels[CHANNELS + 1]; // Channels, 0 is reserved for vehicle radio
SoundLoadData* loadData[CHANNELS + 1]; // For temporarily storing the data of a channel, while the sound loads

std::wstring UTF8ToWide(const std::string& utf8)
{
    if (utf8.empty())
        return std::wstring();
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, NULL, 0);
    if (size_needed <= 0)
        return std::wstring();
    std::wstring wstr(size_needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, &wstr[0], size_needed);
    if (!wstr.empty() && wstr.back() == L'\0')
        wstr.pop_back();
    return wstr;
}

std::string WideToUTF8(const std::wstring& wstr)
{
    if (wstr.empty())
        return std::string();
    int size_needed = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, NULL, 0, NULL, NULL);
    if (size_needed <= 0)
        return std::string();
    std::string str(size_needed, 0);
    WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, &str[0], size_needed, NULL, NULL);
    if (!str.empty() && str.back() == '\0')
        str.pop_back();
    return str;
}

std::string toUTF8(const std::filesystem::path& path)
{
    return WideToUTF8(path.wstring());
}

std::filesystem::path UTF8ToPath(const std::string& utf8)
{
    return std::filesystem::path(UTF8ToWide(utf8));
}

// General purpose functions
void GetRadioExtVersion(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, float* aOut, int64_t a4);
void GetNumChannels(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t a4);
void GetFolders(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, RED4ext::DynArray<RED4ext::CString>* aOut, int64_t a4);
void GetFiles(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, RED4ext::DynArray<RED4ext::CString>* aOut, int64_t a4);
void GetSongLength(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t a4);
void ReadFileWrapper(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t a4);
void WriteFileWrapper(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, bool* aOut, int64_t a4);

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

// Provided by WSSDude / Andrej Redeky
std::filesystem::path getExePath() {
    wchar_t exePathBuf[MAX_PATH]{ 0 };
    GetModuleFileNameW(GetModuleHandle(nullptr), exePathBuf, MAX_PATH);
    std::filesystem::path exePath = exePathBuf;

    return exePath;
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

    auto getFiles = RED4ext::CClassStaticFunction::Create(&cls, "GetFiles", "GetFiles", &GetFiles, { .isNative = true, .isStatic = true });
    getFiles->AddParam("String", "path");
    getFiles->SetReturnType("array:String");

    auto readFileWrapper = RED4ext::CClassStaticFunction::Create(&cls, "ReadFileWrapper", "ReadFileWrapper", &ReadFileWrapper, { .isNative = true, .isStatic = true });
    readFileWrapper->AddParam("String", "path");
    readFileWrapper->SetReturnType("String");

    auto writeFileWrapper = RED4ext::CClassStaticFunction::Create(&cls, "WriteFileWrapper", "WriteFileWrapper", &WriteFileWrapper, { .isNative = true, .isStatic = true });
    writeFileWrapper->AddParam("String", "path");
    writeFileWrapper->AddParam("String", "data");
    writeFileWrapper->SetReturnType("Bool");

    cls.RegisterFunction(getLength);
    cls.RegisterFunction(getVersion);
    cls.RegisterFunction(getFolders);
    cls.RegisterFunction(getFiles);
    cls.RegisterFunction(getChannels);
    cls.RegisterFunction(readFileWrapper);
    cls.RegisterFunction(writeFileWrapper);
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
    // Convert a UTF-8 path to a wide-character path
    std::filesystem::path subDir = UTF8ToPath(std::string(path.c_str()));
    std::filesystem::path target = root.parent_path() / subDir;

    unsigned int length = 0;

    FMOD::Sound* sound;
    std::string targetUTF8 = toUTF8(target);
    FMOD_RESULT error = pSystem->createSound(targetUTF8.c_str(), FMOD_CREATESTREAM, nullptr, &sound);
    // Only log if there is an error, as this gets called for allll the songs
    if (error != FMOD_OK)
    {
        sdk->logger->ErrorF(handle, "FMOD::System::createSound: %s. Requested Path: %s",
            FMOD_ErrorString(error), targetUTF8.c_str());
    }

    error = sound->getLength(&length, FMOD_TIMEUNIT_MS);
    if (error != FMOD_OK)
    {
        sdk->logger->ErrorF(handle, "FMOD::System::getLength: %s. Requested Path: %s",
            FMOD_ErrorString(error), targetUTF8.c_str());
    }

    if (aOut)
    {
        auto type = RED4ext::CRTTISystem::Get()->GetType("Int32");
        type->Assign(aOut, &length);
    }

    aFrame->code++; // skip ParamEnd
}

void GetFolders(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame,
    RED4ext::DynArray<RED4ext::CString>* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);

    RED4ext::CString path;
    RED4ext::GetParameter(aFrame, &path);
    std::filesystem::path subDir = UTF8ToPath(std::string(path.c_str()));
    std::filesystem::path target = root.parent_path() / subDir;
    std::string targetUTF8 = toUTF8(target);
    sdk->logger->InfoF(handle, "GetFolders(%s)", targetUTF8.c_str());

    RED4ext::DynArray<RED4ext::CString> folders;

    try {
        for (const auto& entry : std::filesystem::recursive_directory_iterator(target, std::filesystem::directory_options::follow_directory_symlink))
        {
            if (entry.is_directory())
            {
                // Convert directory name to UTF-8
                std::string folderName = WideToUTF8(entry.path().filename().wstring());
                folders.PushBack(folderName.c_str());
            }
        }
    }
    catch (const std::filesystem::filesystem_error& e) {
        sdk->logger->ErrorF(handle, "Filesystem error: %s", e.what());
    }

    if (aOut)
    {
        auto type = RED4ext::CRTTISystem::Get()->GetType("array:String");
        type->Assign(aOut, &folders);
    }

    aFrame->code++; // skip ParamEnd
}

void GetFiles(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame,
    RED4ext::DynArray<RED4ext::CString>* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);

    RED4ext::CString path;
    RED4ext::GetParameter(aFrame, &path);
    std::filesystem::path subDir = UTF8ToPath(std::string(path.c_str()));
    std::filesystem::path target = root.parent_path() / subDir;
    std::string targetUTF8 = toUTF8(target);
    sdk->logger->InfoF(handle, "GetFiles(%s)", targetUTF8.c_str());

    RED4ext::DynArray<RED4ext::CString> files;

    try {
        for (const auto& entry : std::filesystem::recursive_directory_iterator(target, std::filesystem::directory_options::follow_directory_symlink))
        {
            if (entry.is_regular_file())
            {
                // Convert directory name to UTF-8
                std::string fileName = WideToUTF8(entry.path().filename().wstring());
                files.PushBack(fileName.c_str());
            }
        }
    }
    catch (const std::filesystem::filesystem_error& e) {
        sdk->logger->ErrorF(handle, "Filesystem error: %s", e.what());
    }

    if (aOut)
    {
        auto type = RED4ext::CRTTISystem::Get()->GetType("array:String");
        type->Assign(aOut, &files);
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

std::string GetMountFromUrl(const std::string& url)
{
    size_t pos = url.find_last_of("/");
    if (pos == std::string::npos || pos + 1 >= url.size()) {
        return "/default"; // fallback mount
    }
    return "/" + url.substr(pos + 1);
}

std::filesystem::path GetGamePluginsDirectory()
{
    char path[MAX_PATH];
    HMODULE hModule = GetModuleHandleA(nullptr);
    if (hModule && GetModuleFileNameA(hModule, path, MAX_PATH)) {
        auto fullPath = std::filesystem::path(path);
        auto gameRoot = fullPath.parent_path().parent_path(); // bin/x64 → root
        return gameRoot / "x64" / "plugins" / "cyber_engine_tweaks" / "mods" / "radioExt";
    }
    return std::filesystem::current_path();
}

std::filesystem::path GetModuleDirectory()
{
    char path[MAX_PATH];
    HMODULE hModule = GetModuleHandleA("RadioExt.dll");
    if (hModule && GetModuleFileNameA(hModule, path, MAX_PATH)) {
        return std::filesystem::path(path).parent_path();
    }
    return std::filesystem::current_path();
}

std::string GetBinaryPath(const std::string& filename)
{
    char path[MAX_PATH];
    HMODULE hModule = GetModuleHandleA("RadioExt.dll");
    if (hModule && GetModuleFileNameA(hModule, path, MAX_PATH)) {
        return (std::filesystem::path(path).parent_path() / filename).string();
    }
    return filename;
}

std::string FindExecutable(const std::string& name)
{
    std::string bundled = GetBinaryPath(name);
    if (std::filesystem::exists(bundled)) {
        return bundled;
    }

    char buffer[MAX_PATH];
    if (SearchPathA(nullptr, name.c_str(), nullptr, MAX_PATH, buffer, nullptr) > 0) {
        return std::string(buffer);
    }

    // This shouldn't happen ever if the user isn't trolling (no bundled exe and no trace in PATH)
    return bundled;
}

bool RequiresRelay(const std::string& url) {
    CURL* curl = curl_easy_init();
    if (!curl) return true;

    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_NOBODY, 1L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, .5L);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);

    CURLcode res = curl_easy_perform(curl);
    long http_version = 0;
    curl_easy_getinfo(curl, CURLINFO_HTTP_VERSION, &http_version);
    curl_easy_cleanup(curl);

    if (res != CURLE_OK) return true;

    return (http_version != CURL_HTTP_VERSION_1_0);
}


bool IsYouTubeUrl(const std::string& url)
{
    return url.find("youtube.com") != std::string::npos || url.find("youtu.be") != std::string::npos;
}

std::pair<std::string, std::string> GetIcecastCredentials()
{
    std::filesystem::path credFile = GetBinaryPath("icecast_credentials.txt");

    if (std::filesystem::exists(credFile)) {
        std::ifstream in(credFile);
        std::string line;
        if (std::getline(in, line)) {
            size_t sep = line.find(':');
            if (sep != std::string::npos) {
                std::string username = line.substr(0, sep);
                std::string password = line.substr(sep + 1);
                if (!username.empty() && !password.empty()) {
                    return { username, password };
                }
            }
        }
    }

    // fallback
    return { "source", "hackme" };
}

void StartIcecastIfNeeded()
{
    if (icecastStarted) return;

    auto baseDir = GetModuleDirectory();
    auto exe = (baseDir / "icecast" / "icecast.exe").string();
    auto config = (baseDir / "icecast" / "icecast.xml").string();

    if (!std::filesystem::exists(exe) || !std::filesystem::exists(config)) {
        return;
    }

    std::string cmd = "\"" + exe + "\" -c \"" + config + "\"";

    STARTUPINFOA si = { sizeof(si) };
    PROCESS_INFORMATION pi;

    BOOL result = CreateProcessA(nullptr, (LPSTR)cmd.c_str(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, baseDir.string().c_str(), &si, &pi);
    if (result) {
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        std::this_thread::sleep_for(std::chrono::seconds(2));
        icecastStarted = true;
    }
}

std::string ExtractStationNameFromUrl(const std::string& url) {
    size_t lastSlash = url.find_last_of("/");
    if (lastSlash == std::string::npos || lastSlash + 1 >= url.size()) {
        return "stream";
    }
    std::string raw = url.substr(lastSlash + 1);
    return raw.empty() ? "stream" : raw;
}


std::string StartRelay(const std::string& inputUrl)
{
    StartIcecastIfNeeded();
    std::string mount = GetMountFromUrl(inputUrl);
    std::lock_guard<std::mutex> lock(relayMutex);

    if (relayUrlCache.contains(inputUrl)) {
        return relayUrlCache[inputUrl];
    }

    auto it = activeRelays.find(mount);
    if (it != activeRelays.end()) {
        DWORD exitCode;
        auto& procInfo = *it->second.second;
        if (GetExitCodeProcess(procInfo.hProcess, &exitCode) && exitCode == STILL_ACTIVE) {
            std::string result = "http://127.0.0.1:8000" + mount;
            relayUrlCache[inputUrl] = result;
            return result;
        }
        TerminateProcess(procInfo.hProcess, 0);
        CloseHandle(procInfo.hProcess);
        CloseHandle(procInfo.hThread);
        activeRelays.erase(it);
    }

    auto [icecastUser, icecastPass] = GetIcecastCredentials();
    std::string icecastUrl = "icecast://" + icecastUser + ":" + icecastPass + "@127.0.0.1:8000" + mount;

    std::string ytDlpPath = FindExecutable("yt-dlp.exe");
    std::string ffmpegPath = FindExecutable("ffmpeg.exe");
    std::string relayUrl = "http://127.0.0.1:8000" + mount;

    std::string cmdLine;
    if (IsYouTubeUrl(inputUrl)) {
        cmdLine = "cmd.exe --% /s /C \"\"" + ytDlpPath +
            "\" -f 234 --downloader ffmpeg --downloader-args \"ffmpeg_i1:-extension_picky 0\" -o - \"" + inputUrl +
            "\" | \"" + ffmpegPath + "\" -i pipe:0 -vn -c:a libmp3lame -b:a 256k -f mp3 \"" + icecastUrl + "\"\"";
    }
    else {
        cmdLine = "\"" + ffmpegPath +
            "\" -reconnect 1 -reconnect_streamed 1 -reconnect_delay_max 5 -i \"" + inputUrl +
            "\" -vn -c:a libmp3lame -b:a 256k -f mp3 \"" + icecastUrl + "\"";
    }

    auto pi = std::make_shared<PROCESS_INFORMATION>();
    STARTUPINFOA si = { sizeof(si) };

    BOOL result = CreateProcessA(nullptr, (LPSTR)cmdLine.c_str(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &si, pi.get());
    if (result) {
        activeRelays[mount] = std::make_pair(8000, pi);
        relayUrlCache[inputUrl] = relayUrl;
        return relayUrl;
    }
    return "";
}

std::vector<std::string> GetStreamURLsFromMetadata()
{
    std::vector<std::string> urls;
    auto radioRoot = GetGamePluginsDirectory() / "radios";
    for (auto& entry : std::filesystem::directory_iterator(radioRoot)) {
        auto path = entry.path() / "metadata.json";
        if (!std::filesystem::exists(path)) continue;

        std::ifstream in(path);
        try {
            nlohmann::json j;
            in >> j;
            if (j.contains("streamInfo") && j["streamInfo"]["isStream"] == true) {
                urls.push_back(j["streamInfo"]["streamURL"]);
            }
        }
        catch (...) {
        }
    }
    return urls;
}

void InitRelays() /// Used on launch because creating those dynamically leads to slight freezes
{
    StartIcecastIfNeeded();
    std::thread([] {
        for (const auto& url : GetStreamURLsFromMetadata()) {
            if (RequiresRelay(url))
            {
                StartRelay(url);
            }
        }
        }).detach();
}

void ShutdownRelays() /// Clearing out junk before exiting
{
    std::lock_guard<std::mutex> lock(relayMutex);
    for (auto& [_, procPair] : activeRelays) {
        auto& pi = *procPair.second;
        TerminateProcess(pi.hProcess, 0);
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
    }
    activeRelays.clear();
    system("taskkill /IM icecast.exe /F");
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
    sdk->logger->InfoF(handle, "Play(%i, \"%s\", %i, %f, %f)",
        channelID, path.c_str(), startPos, volume, fade);

    std::filesystem::path subDir = UTF8ToPath(std::string(path.c_str()));
    std::filesystem::path target = root.parent_path() / subDir;

    std::string url = path.c_str();
    if (startPos == -1) {
        auto it = relayUrlCache.find(url);
        if (it != relayUrlCache.end()) {
            target = UTF8ToPath(it->second);
        }
        else {
            target = UTF8ToPath(url);
        }
    }

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

    std::string targetUTF8 = toUTF8(target);
    sdk->logger->InfoF(handle, "FMOD::System::createSound: %s",
        FMOD_ErrorString(pSystem->createStream(targetUTF8.c_str(),
            mode | FMOD_NONBLOCKING, nullptr, &loadData[channelID]->sound)));

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
        logError(pChannels[channelID]->stop(), "FMOD::Channel*->stop()");
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
        logError(pChannels[channelID]->set3DAttributes(&posF, nullptr), "SetChannelTransform::set3DListenerAttributes");
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

    logError(pSystem->set3DListenerAttributes(0, &posF, &velF, &forwardF, &upF), "SetListenerTransform::set3DListenerAttributes");

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

// Read file: Accepts a UTF-8 encoded path and returns the file content (UTF-8 encoded); if it fails, returns an empty string
void ReadFileWrapper(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);

    RED4ext::CString path;
    RED4ext::GetParameter(aFrame, &path);
    // Convert the UTF-8 path passed from Lua into a wide-character path
    std::filesystem::path subPath = UTF8ToPath(std::string(path.c_str()));
    std::filesystem::path fullPath = root.parent_path() / subPath;
    std::wstring wPath = fullPath.wstring();
    
    FILE* fp = _wfopen(wPath.c_str(), L"rb");
    if (!fp)
    {
        // If the file cannot be opened, return an empty string
        RED4ext::CString empty("");
        auto type = RED4ext::CRTTISystem::Get()->GetType("String");
        type->Assign(aOut, &empty);
        aFrame->code++;
        return;
    }
    
    // Get the file size
    fseek(fp, 0, SEEK_END);
    long fileSize = ftell(fp);
    rewind(fp);

    // Read the file content into a vector
    std::vector<char> buffer(fileSize);
    if (fileSize > 0)
    {
        fread(buffer.data(), 1, fileSize, fp);
    }
    fclose(fp);

    // Construct a std::string (assuming the file content itself is UTF-8 encoded)
    std::string content(buffer.begin(), buffer.end());
    RED4ext::CString result(content.c_str());
    
    auto type = RED4ext::CRTTISystem::Get()->GetType("String");
    type->Assign(aOut, &result);
    
    aFrame->code++;
}

// Write file: Accepts a UTF-8 encoded path and content, returns a Bool indicating whether the write was successful
void WriteFileWrapper(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, bool* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(a4);
    RED4EXT_UNUSED_PARAMETER(aContext);

    RED4ext::CString path;
    RED4ext::CString content;
    RED4ext::GetParameter(aFrame, &path);
    RED4ext::GetParameter(aFrame, &content);
    // Convert the path into a wide-character path
    std::filesystem::path subPath = UTF8ToPath(std::string(path.c_str()));
    std::filesystem::path fullPath = root.parent_path() / subPath;
    std::wstring wPath = fullPath.wstring();

    FILE* fp = _wfopen(wPath.c_str(), L"wb");
    bool success = false;
    if (fp)
    {
        std::string data(content.c_str());
        size_t written = fwrite(data.data(), 1, data.size(), fp);
        fclose(fp);
        success = (written == data.size());
    }
    
    auto type = RED4ext::CRTTISystem::Get()->GetType("Bool");
    type->Assign(aOut, &success);
    
    aFrame->code++;
}

bool Running_OnEnter(RED4ext::CGameApplication* aApp)
{
    InitRelays();  // preload Icecast + all relays
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
    ShutdownRelays();  // clean up FFmpeg/Icecast 

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
        root = getExePath();

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

        RED4ext::CRTTISystem::Get()->AddRegisterCallback(RegisterTypes);
        RED4ext::CRTTISystem::Get()->AddPostRegisterCallback(PostRegisterTypes);

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
    aInfo->version = RED4EXT_SEMVER(2, 2, 0);
    aInfo->runtime = RED4EXT_RUNTIME_INDEPENDENT;
    aInfo->sdk = RED4EXT_SDK_LATEST;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_LATEST;
}