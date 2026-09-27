#ifndef RUNNER_STAGE_TEXTURE_TRACE_H_
#define RUNNER_STAGE_TEXTURE_TRACE_H_

#include <cstdint>

namespace stage_texture_trace {

void RegisterProvider();
void UnregisterProvider();

void Attach(std::uint64_t host_address, std::int64_t texture_id,
            bool succeeded);
void SetActive(bool active, std::int64_t texture_id);
void TextureCallback(std::uint64_t generation, std::uint64_t frame_id);
void FrameAvailable(std::uint64_t generation, std::uint64_t frame_id,
                    std::int64_t texture_id);
void TextureAcquire(std::uint64_t generation, std::uint64_t frame_id,
                    bool advanced);

}  // namespace stage_texture_trace

#endif  // RUNNER_STAGE_TEXTURE_TRACE_H_
