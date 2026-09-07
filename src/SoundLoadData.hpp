struct SoundLoadData {
    FMOD::Sound* sound = nullptr;
    int32_t startPos = 0;
    float volume = 1.0f;
    float fade = 0.0f;
    FMOD_MODE mode = FMOD_2D;
    bool play = false;
    std::string path;
};
