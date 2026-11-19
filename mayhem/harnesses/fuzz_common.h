// Shared helpers for the react-native-audio-api fuzz harnesses (scratch files only).
#pragma once

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <unistd.h>

namespace fuzz_common {

// One private scratch directory per process under $TMPDIR (default /tmp). Every file a harness
// writes lives in it and is removed again before the input returns.
inline const std::string &scratchDir() {
  static const std::string dir = [] {
    const char *tmp = std::getenv("TMPDIR");
    std::string tmpl = std::string(tmp != nullptr && *tmp != '\0' ? tmp : "/tmp") + "/rnaa-fuzz-XXXXXX";
    if (mkdtemp(tmpl.data()) == nullptr) {
      std::perror("mkdtemp");
      std::abort();
    }
    return tmpl;
  }();
  return dir;
}

inline std::string writeFile(const std::string &name, const uint8_t *data, size_t size) {
  std::string path = scratchDir() + "/" + name;
  FILE *f = std::fopen(path.c_str(), "wb");
  if (f == nullptr) {
    std::perror("fopen");
    std::abort();
  }
  if (size > 0 && std::fwrite(data, 1, size, f) != size) {
    std::perror("fwrite");
    std::abort();
  }
  std::fclose(f);
  return path;
}

} // namespace fuzz_common
