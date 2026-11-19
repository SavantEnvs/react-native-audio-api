// decodeWithPCMInBase64 (AudioDecoder.decodePCMInBase64 from JS): libs/base64 decode, then
// RawPcmDecoder::openFromBytes de-/interleaving and decodeAll into an AudioBuffer.
//
// Input layout: byte 0 -> channel count (1..8), byte 1 -> interleaved flag, byte 2 -> input
// sample rate; the rest is the base64 text.
#include <audioapi/decoding/AudioDecoding.h>

#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <string>

namespace {
constexpr float kRates[] = {8000.0f, 16000.0f, 22050.0f, 44100.0f, 48000.0f, 96000.0f, 3000.0f, 192000.0f};
} // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  using namespace audioapi::audiodecoding;
  if (size < 3) {
    return -1;
  }
  const int channels = 1 + data[0] % 8;
  const bool interleaved = (data[1] & 1) != 0;
  const float rate = kRates[data[2] % 8];
  const std::string b64(reinterpret_cast<const char *>(data + 3), size - 3);
  try {
    auto decoded = decodeWithPCMInBase64(b64, rate, channels, interleaved);
    (void)decoded;
  } catch (const std::runtime_error &) {
    // libs/base64 base64_decode() documents rejecting non-base64 text by throwing
    // std::runtime_error("Input is not valid base64-encoded data."). That is its contract for
    // invalid input, not a memory-safety defect, so the input is simply rejected here.
    return 0;
  }
  return 0;
}
