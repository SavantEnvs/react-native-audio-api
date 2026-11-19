#!/usr/bin/env bash
#
# mayhem/build.sh — builds the react-native-audio-api C++ core fuzz harnesses and upstream's
# own gtest suite. Runs in the commit image as `mayhem` in /mayhem; re-runnable and offline.
#
# Dependencies (all in-image, see mayhem/Dockerfile):
#   - react-native 0.88.0 npm package (JSI + callinvoker headers, jsi.cpp) at
#     /opt/toolchains/deps/react-native-0.88.0/src — upstream resolves it as
#     packages/react-native-audio-api/node_modules/react-native (pnpm), so build.sh links it there
#     (node_modules/ is gitignored, so it is recreated on every run).
#   - Debian libgtest-dev/libgmock-dev (upstream's find_package(GTest) path, no FetchContent),
#     libogg/libopus/libopusfile/libvorbis static libs.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

RN_DIR=/opt/toolchains/deps/react-native-0.88.0/src
PKG="$SRC/packages/react-native-audio-api"
CPP="$PKG/common/cpp"
OUT="$SRC/mayhem/build/fuzz"

cd "$SRC"

# Upstream's CMake looks for react-native under the package's node_modules (pnpm install).
mkdir -p "$PKG/node_modules"
ln -sfn "$RN_DIR" "$PKG/node_modules/react-native"

# SanCov on the library AND the harness objects (unconditional: $SANITIZER_FLAGS carries none, and
# $LIB_FUZZING_ENGINE only instruments the TU it is compiled into).
COV_FLAGS="-fsanitize=fuzzer-no-link"

# 1) The C++ core, instrumented (SanCov + ASan/UBSan halting, DWARF 3), as static libs.
cmake -S "$SRC/mayhem/fuzz" -B "$OUT" -G Ninja -Wno-dev \
  -DCMAKE_BUILD_TYPE=None \
  -DREACT_NATIVE_DIR="$RN_DIR" \
  -DCMAKE_C_FLAGS="-O1 $COV_FLAGS $SANITIZER_FLAGS $DEBUG_FLAGS" \
  -DCMAKE_CXX_FLAGS="-O1 $COV_FLAGS $SANITIZER_FLAGS $DEBUG_FLAGS"
cmake --build "$OUT" -j"$MAYHEM_JOBS"

INCS=(-I"$CPP" -I"$CPP/audioapi/external/include" -I"$CPP/audioapi/external/include/opus"
      -I"$RN_DIR/ReactCommon/jsi" -I"$RN_DIR/ReactCommon" -I"$RN_DIR/ReactCommon/callinvoker"
      -I"$SRC/mayhem/harnesses")
LIBS=("$OUT/librnaudioapi_fuzz.a" "$OUT/librnaudioapi_libs_fuzz.a"
      -l:libopusfile.a -l:libvorbisfile.a -l:libvorbis.a -l:libopus.a -l:libogg.a -lpthread -lm)
CXXF=(-std=c++20 -O1 -DRN_AUDIO_API_TEST=1 $SANITIZER_FLAGS $DEBUG_FLAGS)

$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$OUT/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OUT/standalone_main.o"

# 2) Each harness twice: libFuzzer binary + run-once standalone reproducer.
build_harness() {  # <name> <source> [extra flags...]
  local name="$1" src="$2"; shift 2
  $CXX "${CXXF[@]}" $COV_FLAGS "${INCS[@]}" "$@" -c "$src" -o "$OUT/$name.o"
  $CXX "${CXXF[@]}" $LIB_FUZZING_ENGINE "$OUT/$name.o" "$OUT/lsan_off.o" "${LIBS[@]}" -o "$SRC/$name"
  $CXX "${CXXF[@]}" $COV_FLAGS "$OUT/standalone_main.o" "$OUT/$name.o" "$OUT/lsan_off.o" "${LIBS[@]}" -o "$SRC/$name-standalone"
}
H="$SRC/mayhem/harnesses"
build_harness fuzz_decode_memory     "$H/fuzz_decode_memory.cc"
build_harness fuzz_decoder_seek_read "$H/fuzz_decoder_seek_read.cc"
build_harness fuzz_decode_pcm_base64 "$H/fuzz_decode_pcm_base64.cc"
build_harness fuzz_concat_ogg_opus   "$H/fuzz_concat.cc" -DFUZZ_CONCAT_EXT='"ogg"'
build_harness fuzz_concat_adts       "$H/fuzz_concat.cc" -DFUZZ_CONCAT_EXT='"aac"'

# 3) Upstream's own gtest suite with its NORMAL flags (no sanitizers), in upstream's build dir
#    (common/cpp/test/build, gitignored). Only the plain `tests` binary is built.
env -u CFLAGS -u CXXFLAGS -u LDFLAGS cmake -S "$CPP/test" -B "$CPP/test/build" -G Ninja -Wno-dev \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$COVERAGE_FLAGS"
cmake --build "$CPP/test/build" --target tests -j"$MAYHEM_JOBS"
