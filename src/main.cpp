#include "main.h"
#define UNICODE
#define _UNICODE

ma_result result;
ma_engine engine;
ma_sound currentSong;
std::atomic_bool sound_active = false;
float timestamp = 0;

std::thread thd;
std::atomic_bool shouldRun = true;
std::atomic_bool firstInit = false;
std::atomic_bool engineInited = false;

std::mutex mutex;
logger* Logger; // TODO: Switch to spdlog
std::filesystem::path rootDir;

WNDCLASS wc = {0};
HWND hWin;

std::filesystem::path getExePath();
void setupThread();
void handleRequest(std::filesystem::path path);
void handlePlay(nlohmann::json json);
void handleStop();
void handleReset();
void generateMetadata();

BOOL APIENTRY DllMain( HMODULE hModule,
                       DWORD  ul_reason_for_call,
                       LPVOID lpReserved
                     )
{
    switch (ul_reason_for_call)
    {
    case DLL_PROCESS_ATTACH:{
        std::filesystem::path exePath = getExePath();
        rootDir = exePath.parent_path();

        // Quit if not attaching to CP77
        if (exePath.filename() != L"Cyberpunk2077.exe") {
            break;
        }

        Logger = new logger("radioAdditions.log");
        Logger->log("Started logging: " + rootDir.string() + "\\plugins\\radioAdditions.log");

        if (!std::filesystem::exists(rootDir / "plugins\\cyber_engine_tweaks\\mods\\radioExt\\init.lua")) {
            Logger->error("CET Part not found! Expected it in \"" + (rootDir / "plugins\\cyber_engine_tweaks\\mods\\radioExt").string() + "\"");
            break;
        }

        setupThread();

        break;
    }
    case DLL_PROCESS_DETACH:
            shouldRun = false;
            if (thd.joinable())
            thd.join();
        break;
    default:
        break;
    }
    return TRUE;
}

void generateMetadata(){ // lua cant tell me what folders there are. Also how long each song is.
    nlohmann::json table;

    ma_sound song;
    ma_uint64 length;

    for (const auto & entry : std::filesystem::recursive_directory_iterator(rootDir / "plugins\\cyber_engine_tweaks\\mods\\radioExt\\radios")){ // All the radio folders
        if(entry.is_directory()){
            Logger->log("Found radio directoy: " + entry.path().string());

            if(table["paths"].empty()){ // Cant add to empty list
                table["paths"] = {entry.path().filename().string()};
            }else{
                table["paths"].insert(table["paths"].end(), entry.path().filename().string());
            }

            nlohmann::json songs;

            for (const auto & fPath : std::filesystem::directory_iterator(entry.path())){ // Each file in the radio dir
                std::string ext = fPath.path().extension().string();

                if(ext == ".mp3" || ext == ".wav" ){
                    Logger->log("Found song file: " + fPath.path().string());

                    ma_sound_init_from_file(&engine, fPath.path().string().c_str(), NULL, NULL, NULL, &song);
                    if (result == MA_SUCCESS) {
                        ma_sound_get_length_in_pcm_frames(&song, &length);
                        std::filesystem::path dir = fPath.path().parent_path().filename() / fPath.path().filename(); // Radio dir name + file name
                        songs[dir.string()] = length / ma_engine_get_sample_rate(&engine); // Audio length in seconds
                    }
                    ma_sound_uninit(&song);
                }
            }

            std::ofstream file (entry.path() / "songInfos.json"); // Audio file name - Audio length table
            file << std::setw(4) << songs << std::endl;
            file.close();
        }
    }

    std::ofstream file (rootDir / "plugins\\cyber_engine_tweaks\\mods\\radioExt\\radios\\radiosInfo.json"); // Radio directories
    file << std::setw(4) << table << std::endl;
    file.close();
}

static LRESULT WINAPI WindowProc(HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam)
    {
        switch(uMsg)
        {
        case WM_POWERBROADCAST:
            {
                if (wParam == PBT_APMSUSPEND ){
                    if(sound_active){
                        ma_sound_stop(&currentSong);
                        ma_sound_uninit(&currentSong);
                        sound_active = false;
                    }

                    if(engineInited){
                        ma_engine_uninit(&engine);
                    }
                    engineInited = false;

                    Logger->log("System Powered off");
                }
                if (wParam == PBT_APMRESUMESUSPEND  ){
                    Logger->log("System Powered on");
                }
            }
        }

        return DefWindowProc(hWnd, uMsg, wParam, lParam);
    }

void setupThread(){
    for (const auto & entry : std::filesystem::directory_iterator(rootDir / "plugins\\cyber_engine_tweaks\\mods\\radioExt\\io\\out")){ // Clear the folder
        if(entry.path().extension().string() == ".json"){
            std::filesystem::remove(entry.path());
        }
    }

    wc.lpfnWndProc = WindowProc; // Fake window for power broadcasts
    wc.lpszClassName = TEXT("radioExtWindow");
    RegisterClass(&wc);
    hWin = CreateWindow(TEXT("radioExtWindow"), TEXT(""), 0, 0, 0, 0, 0, NULL, NULL, NULL, 0);

    thd = std::thread([]() {
        while (shouldRun) {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));

            std::lock_guard<std::mutex> lockGuard(mutex);

            if(!firstInit){
                ma_engine_init(NULL, &engine);
                firstInit = true;
                Logger->engine("maEngine inited");
                engineInited = true;

                generateMetadata();
            }

            for (const auto & entry : std::filesystem::directory_iterator(rootDir / "plugins\\cyber_engine_tweaks\\mods\\radioExt\\io\\out")){
                if(entry.path().extension().string() == ".json"){
                    Logger->log("Found new audio request: " + entry.path().string());
                    handleRequest(entry.path());
                }
            }
        }
    });
}

void handleRequest(std::filesystem::path path){
    std::ifstream jFile(path);

    if(jFile.is_open()){
        nlohmann::json json;

        try {
            json = nlohmann::json::parse(jFile);
        } catch(nlohmann::json::parse_error) {
            Logger->error("Json Parsing error");
            jFile.close();
            return;
        }

        jFile.close();

        if(json["type"].get<std::string>() == "play"){
            handlePlay(json);
        }else if(json["type"].get<std::string>() == "stop"){
            handleStop();
        }else if(json["type"].get<std::string>() == "reset"){
            handleReset();
        }else{
            Logger->error("Unknown request type:" + json["type"].get<std::string>());
        }

        std::filesystem::remove(path);
    }
}

void handleReset(){
    if(sound_active){
        ma_sound_stop(&currentSong);
        ma_sound_uninit(&currentSong);
        sound_active = false;
    }

    if(engineInited){
        ma_engine_uninit(&engine);
    }
    ma_engine_init(NULL, &engine);
    engineInited = true;

    Logger->engine("maEngine reset");
}

void handleStop(){
    if(!sound_active){return;}

    ma_sound_stop(&currentSong);
    ma_sound_uninit(&currentSong);
    sound_active = false;

    Logger->log("Stopped playing audio");
}

void handlePlay(nlohmann::json json){
    std::string ex = "plugins\\cyber_engine_tweaks\\mods\\radioExt\\" + json["path"].get<std::string>();
    std::filesystem::path path = rootDir / ex;
    int startTime = json["time"].get<int>();
    float volume = json["volume"].get<float>();
    int fade = json["fade"].get<int>();

    if(!engineInited){
        return;
    }

    if(sound_active){
        ma_sound_stop(&currentSong);
        ma_sound_uninit(&currentSong);
    }

    ma_sound_init_from_file(&engine, path.string().c_str(), NULL, NULL, NULL, &currentSong);
    ma_sound_seek_to_pcm_frame(&currentSong, ma_engine_get_sample_rate(&engine) * startTime);
    ma_sound_set_fade_in_milliseconds(&currentSong, 0, 1, fade);
    ma_sound_set_volume(&currentSong, volume);
    ma_sound_start(&currentSong);

    sound_active = true;

    Logger->log("Started playing path: " + path.string());
}

std::filesystem::path getExePath(){
    wchar_t exePathBuf[MAX_PATH] { 0 };
    GetModuleFileName(GetModuleHandle(nullptr), exePathBuf, std::size(exePathBuf));
    std::filesystem::path exePath = exePathBuf;

    return exePath;
}