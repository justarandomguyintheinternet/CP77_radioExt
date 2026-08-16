cmake_minimum_required(VERSION 3.21)
project(RadioExt VERSION 0.9.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---------------------------------------------------------------------------
# RED4ext SDK
# ---------------------------------------------------------------------------
add_subdirectory("C:/BuildDeps/red4ext-sdk" "${CMAKE_BINARY_DIR}/red4ext-sdk")

# ---------------------------------------------------------------------------
# FMOD Core API
# ---------------------------------------------------------------------------
set(FMOD_ROOT "C:/Program Files (x86)/FMOD SoundSystem/FMOD Studio API Windows/api/core")

add_library(FMOD::Core SHARED IMPORTED)
set_target_properties(FMOD::Core PROPERTIES
    IMPORTED_LOCATION          "${FMOD_ROOT}/lib/x64/fmod.dll"
    IMPORTED_IMPLIB            "${FMOD_ROOT}/lib/x64/fmod_vc.lib"
    INTERFACE_INCLUDE_DIRECTORIES "${FMOD_ROOT}/inc"
)

# ---------------------------------------------------------------------------
# RadioExt DLL
# ---------------------------------------------------------------------------
add_library(radioext SHARED
    src/main.cpp
    src/SoundLoadData.hpp
)

target_link_libraries(radioext PRIVATE
    RED4ext::SDK
    FMOD::Core
)

target_compile_definitions(radioext PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
)

# Set output name to "radioext" → radioext.dll
set_target_properties(radioext PROPERTIES
    OUTPUT_NAME "radioext"
    PREFIX ""
    SUFFIX ".dll"
)

# Copy FMOD DLL alongside the built DLL
add_custom_command(TARGET radioext POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${FMOD_ROOT}/lib/x64/fmod.dll"
        "$<TARGET_FILE_DIR:radioext>"
    COMMENT "Copying fmod.dll to output directory"
)
