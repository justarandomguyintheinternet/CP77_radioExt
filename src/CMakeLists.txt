cmake_minimum_required(VERSION 3.21)

project(
  RadioExt
  VERSION 2.3.0
  LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(RADIOEXT_VENDORS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/vendors")

# build red4ext sdk as static lib
set(RED4EXT_HEADER_ONLY OFF CACHE BOOL "" FORCE)
add_subdirectory("${RADIOEXT_VENDORS_DIR}/RED4ext.SDK" EXCLUDE_FROM_ALL)

# find fmod
set(FMOD_DIR "" CACHE PATH "Root of the FMOD Core API (the 'api/core' directory of the FMOD Studio API)")

set(FMOD_SEARCH_HINTS
  "${FMOD_DIR}"
  "$ENV{FMOD_DIR}"
  "${RADIOEXT_VENDORS_DIR}/fmod"
  "$ENV{ProgramFiles\(x86\)}/FMOD SoundSystem/FMOD Studio API Windows/api/core"
  "$ENV{ProgramFiles}/FMOD SoundSystem/FMOD Studio API Windows/api/core"
)

find_path(FMOD_INCLUDE_DIR
  NAMES fmod.hpp
  HINTS ${FMOD_SEARCH_HINTS}
  PATH_SUFFIXES inc include
  DOC "Directory containing fmod.hpp"
)

find_library(FMOD_LIBRARY
  NAMES fmod_vc fmod
  HINTS ${FMOD_SEARCH_HINTS}
  PATH_SUFFIXES lib/x64 lib
  DOC "FMOD Core import library (fmod_vc.lib)"
)

find_file(FMOD_RUNTIME_LIBRARY
  NAMES fmod.dll
  HINTS ${FMOD_SEARCH_HINTS}
  PATH_SUFFIXES lib/x64 lib
  DOC "FMOD Core runtime (fmod.dll)"
)

add_library(FMOD::Core SHARED IMPORTED)
set_target_properties(FMOD::Core PROPERTIES
  IMPORTED_IMPLIB "${FMOD_LIBRARY}"
  INTERFACE_INCLUDE_DIRECTORIES "${FMOD_INCLUDE_DIR}"
)
if(FMOD_RUNTIME_LIBRARY)
  set_target_properties(FMOD::Core PROPERTIES IMPORTED_LOCATION "${FMOD_RUNTIME_LIBRARY}")
endif()

# main target
add_library(RadioExt SHARED
main.cpp
SoundLoadData.hpp
)

target_compile_definitions(RadioExt
  PRIVATE
    UNICODE # getExePath() uses the wide GetModuleFileName/GetModuleHandle
    _UNICODE
    WIN32_LEAN_AND_MEAN
)

target_link_libraries(RadioExt
  PRIVATE
    RED4ext::SDK
    FMOD::Core
)

# ensure correct naming + build straight into the game's plugin folder
set(RADIOEXT_PLUGIN_DIR "C:/Program Files (x86)/GOG Galaxy/Games/Cyberpunk 2077/red4ext/plugins/RadioExt")

set_target_properties(RadioExt PROPERTIES
  PREFIX ""
  OUTPUT_NAME "RadioExt"
  RUNTIME_OUTPUT_DIRECTORY "${RADIOEXT_PLUGIN_DIR}"
)

foreach(cfg IN ITEMS DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
  set_target_properties(RadioExt PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY_${cfg} "${RADIOEXT_PLUGIN_DIR}")
endforeach()

# include fmod dll
if(FMOD_RUNTIME_LIBRARY)
  add_custom_command(TARGET RadioExt POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${FMOD_RUNTIME_LIBRARY}"
      "$<TARGET_FILE_DIR:RadioExt>"
    COMMENT "Copying fmod.dll next to RadioExt.dll"
    VERBATIM
  )
endif()

# copy built stuff to repo directory for pack.yml to use
option(RADIOEXT_DEPLOY_TO_REPO "Copy the built DLLs into ../red4ext/ after building." ON)
if(RADIOEXT_DEPLOY_TO_REPO)
  set(RADIOEXT_DEPLOY_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../red4ext")

  add_custom_command(TARGET RadioExt POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "${RADIOEXT_DEPLOY_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "$<TARGET_FILE:RadioExt>" "${RADIOEXT_DEPLOY_DIR}"
    COMMENT "Deploying RadioExt.dll to ${RADIOEXT_DEPLOY_DIR}"
    VERBATIM
  )

  if(FMOD_RUNTIME_LIBRARY)
    add_custom_command(TARGET RadioExt POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${FMOD_RUNTIME_LIBRARY}" "${RADIOEXT_DEPLOY_DIR}"
      VERBATIM
    )
  endif()
endif()
