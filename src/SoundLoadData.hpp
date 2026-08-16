#ifndef RADIOEXT_SOUND_LOAD_DATA_HPP
#define RADIOEXT_SOUND_LOAD_DATA_HPP

#include <cstdint>
#include <string>

// Forward declaration to avoid pulling the full FMOD header into every
// translation unit that includes this file. The full definition is only
// needed in main.cpp where the FMOD API is actually called.
namespace FMOD
{
class Sound;
}

// Holds the transient state for a channel while its sound is loading
// asynchronously via FMOD's FMOD_NONBLOCKING mode. Default-initialized
// to safe values so that checkSoundLoad() never dereferences an
// uninitialized sound pointer or reads garbage volume.
struct SoundLoadData
{
    FMOD::Sound* sound = nullptr;
    int32_t startPos = 0;
    float volume = 0.0f;
    float fade = 0.0f;
    bool play = false;
    std::string path;
};

#endif // RADIOEXT_SOUND_LOAD_DATA_HPP
