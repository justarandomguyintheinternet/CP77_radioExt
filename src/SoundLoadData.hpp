struct SoundLoadData {
    FMOD::Sound* sound;
    int32_t startPos;
    float volume;
    float fade;
    bool play;
    std::string path;
};
