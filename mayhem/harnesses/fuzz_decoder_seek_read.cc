// Incremental decoder API used by streaming file sources and SeekDecoderDaemon:
// decoding::createDecoder(EncodedMemorySource) then a short script of seekToTime/readPcmFrames.
//
// Input layout: byte 0 picks the requested output sample rate (0 = native, otherwise resampled);
// bytes 1..8 are four (op, arg) pairs; the rest is the encoded audio file.
#include <audioapi/decoding/DecoderFactory.h>
#include <audioapi/decoding/DecoderSource.h>

#include <cstddef>
#include <cstdint>
#include <vector>

namespace {
constexpr int kRates[] = {0, 8000, 11025, 16000, 22050, 44100, 48000, 96000};
constexpr size_t kHeader = 9;
} // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  using namespace audioapi::decoding;
  if (size < kHeader) {
    return -1;
  }
  EncodedMemorySource source;
  source.sampleRate = kRates[data[0] % 8];
  source.data.assign(data + kHeader, data + size);

  auto created = createDecoder(source);
  if (created.is_err()) {
    return 0;
  }
  auto decoder = std::move(created).unwrap();
  const int channels = decoder->outputChannels();
  const float duration = decoder->getDurationInSeconds();
  (void)decoder->getTotalPcmFrameCount();
  if (channels <= 0 || channels > 64) {
    decoder->close();
    return 0;
  }
  std::vector<float> pcm(static_cast<size_t>(channels) * AudioDecoderBackend::CHUNK_SIZE);
  for (size_t i = 0; i < 4; ++i) {
    const uint8_t op = data[1 + 2 * i];
    const uint8_t arg = data[2 + 2 * i];
    switch (op % 3) {
      case 0: {
        // Seek to a fraction of the reported duration (or seconds when it is unknown),
        // sometimes past the end.
        const double target = duration > 0.0f ? duration * (arg / 200.0) : arg / 16.0;
        (void)decoder->seekToTime(target);
        break;
      }
      case 1: {
        const size_t frames = 1 + (static_cast<size_t>(arg) * 16) % AudioDecoderBackend::CHUNK_SIZE;
        (void)decoder->readPcmFrames(pcm.data(), frames);
        break;
      }
      default: {
        // Drain up to 64 chunks.
        for (int n = 0; n < 64 && decoder->readPcmFrames(pcm.data(), AudioDecoderBackend::CHUNK_SIZE) > 0; ++n) {
        }
        break;
      }
    }
    (void)decoder->getCurrentPositionInSeconds();
  }
  decoder->close();
  return 0;
}
