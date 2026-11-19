// decodeAudioData(ArrayBuffer) path: audiodecoding::decodeWithMemoryBlock picks a backend via
// DecoderFactory (miniaudio WAV/MP3/FLAC + the libvorbis/libopus Ogg backends) and decodes the
// whole stream into an AudioBuffer; probeDurationWithMemory is the duration probe on the same bytes.
#include <audioapi/decoding/AudioDecoding.h>

#include <cstddef>
#include <cstdint>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  using namespace audioapi::audiodecoding;
  auto decoded = decodeWithMemoryBlock(data, size, 44100.0f);
  if (decoded.is_ok()) {
    auto buffer = decoded.unwrap();
    volatile float sink = 0.0f;
    for (size_t c = 0; c < buffer->getNumberOfChannels(); ++c) {
      auto *channel = buffer->getChannel(c);
      if (buffer->getSize() > 0) {
        sink = sink + (*channel)[buffer->getSize() - 1];
      }
    }
  }
  auto duration = probeDurationWithMemory(data, size, 0);
  (void)duration;
  return 0;
}
