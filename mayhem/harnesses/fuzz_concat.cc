// concatAudioFiles (AudioFileConcatenator) over two input files written from the fuzz bytes.
// The output extension selects the concat path:
//   FUZZ_CONCAT_EXT="ogg" -> Ogg/Opus remux (OggOpusRemux.cpp parse/take*Packet, OggStreamWriter)
//   FUZZ_CONCAT_EXT="aac" -> ADTS frame append (scanAdtsFrames, AdtsHeader::parseHeader)
//
// Input layout: byte 0 sets where the remaining bytes split into input file a and file b
// (0 -> a single input file holding all of them).
#include <audioapi/encoding/AudioFileConcatenator.h>

#include "fuzz_common.h"

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

#ifndef FUZZ_CONCAT_EXT
#error "FUZZ_CONCAT_EXT must be defined"
#endif

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  if (size < 1) {
    return -1;
  }
  const std::string ext = FUZZ_CONCAT_EXT;
  const uint8_t splitByte = data[0];
  const uint8_t *body = data + 1;
  const size_t bodySize = size - 1;

  std::vector<std::string> inputs;
  if (splitByte == 0) {
    inputs.push_back(fuzz_common::writeFile("a." + ext, body, bodySize));
  } else {
    const size_t split = bodySize * splitByte / 256;
    inputs.push_back(fuzz_common::writeFile("a." + ext, body, split));
    inputs.push_back(fuzz_common::writeFile("b." + ext, body + split, bodySize - split));
  }
  const std::string output = fuzz_common::scratchDir() + "/out." + ext;
  auto result = audioapi::concatAudioFiles(inputs, output);
  (void)result;

  for (const auto &path : inputs) {
    std::remove(path.c_str());
  }
  std::remove(output.c_str());
  return 0;
}
