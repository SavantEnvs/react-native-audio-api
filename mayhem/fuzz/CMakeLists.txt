# Fuzz build of the react-native-audio-api C++ core (packages/react-native-audio-api/common/cpp).
# Mirrors upstream's Linux build (common/cpp/test/CMakeLists.txt: same source glob and exclusions)
# but keeps the bundled Ogg/Opus/Vorbis support ON (no RN_AUDIO_API_STATIC_EXTERNAL_LIBS_DISABLED,
# no MA_NO_LIBOPUS/MA_NO_LIBVORBIS) so the Ogg decoders and the Ogg/Opus concat remux are reachable.
# The vendored headers in audioapi/external/include are used; the libraries come from Debian's
# static libogg/libopus/libopusfile/libvorbis(file) (uninstrumented dependencies).
# Compiler, sanitizer and debug flags come from the environment (mayhem/build.sh).
cmake_minimum_required(VERSION 3.14)
project(rnaudioapi_fuzz C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Normalized (no "mayhem/fuzz/../..") so debug info and sanitizer frames name upstream sources as
# /mayhem/packages/..., not paths under mayhem/.
get_filename_component(PKG "${CMAKE_CURRENT_SOURCE_DIR}/../../packages/react-native-audio-api" ABSOLUTE)
set(CPP "${PKG}/common/cpp")
set(RN_DIR "${REACT_NATIVE_DIR}")
if(NOT RN_DIR)
  message(FATAL_ERROR "pass -DREACT_NATIVE_DIR=<react-native package dir>")
endif()

file(GLOB_RECURSE ENGINE_SRC CONFIGURE_DEPENDS "${CPP}/audioapi/*.cpp")
list(FILTER ENGINE_SRC EXCLUDE REGEX ".*/audioapi/HostObjects/.*\\.cpp$")
list(FILTER ENGINE_SRC EXCLUDE REGEX ".*/AudioThreadGuard\\.cpp$")
list(REMOVE_ITEM ENGINE_SRC
  "${CPP}/audioapi/core/AudioContext.cpp"
  "${CPP}/audioapi/decoding/backends/FfmpegDecoder.cpp")

file(GLOB_RECURSE LIBS_SRC CONFIGURE_DEPENDS "${CPP}/audioapi/libs/*.c")

add_library(rnaudioapi_fuzz STATIC ${ENGINE_SRC} "${RN_DIR}/ReactCommon/jsi/jsi/jsi.cpp")
add_library(rnaudioapi_libs_fuzz STATIC ${LIBS_SRC})
foreach(t rnaudioapi_fuzz rnaudioapi_libs_fuzz)
  target_include_directories(${t} PUBLIC
    "${CPP}"
    "${CPP}/audioapi/external/include"
    "${CPP}/audioapi/external/include/opus"
    "${RN_DIR}/ReactCommon/jsi"
    "${RN_DIR}/ReactCommon"
    "${RN_DIR}/ReactCommon/callinvoker")
  target_compile_definitions(${t} PUBLIC RN_AUDIO_API_TEST=1)
endforeach()
