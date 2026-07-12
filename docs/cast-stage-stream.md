# Cast Stage Stream

Kirakara 的投屏输出是一条独立的 Stage Program Feed。它不是 Flutter
Controller UI 的镜像，也不是从预览窗口或第二屏窗口捕获画面。它更接近
内置的 KTV 专用 OBS：所有 source 都由 Kirakara Show / ShowHost 主动提供，
然后合成、编码、推流。

本文描述的是目标架构和阶段边界，不表示当前代码已经拥有完整
StageCompositor。当前 ShowHost 已经是播放状态权威；真正缺口是把现有
窗口叠层输出改造成主动合成输出。

## Architecture

```mermaid
flowchart TD
    Flutter["Flutter Controller UI\n点歌 / 队列 / 设置 / 控制"] -->|commands only| Session["ShowHost PlaybackSession\n唯一播放权威"]

    Session --> Clock["PlaybackClock\nplay / pause / seek / load / next / buffering"]
    Session --> Source["CurrentMediaSource\nvideo / krl / vocal / inst / clockMode"]

    Source --> VideoDecoder["Native Video Decoder\nMF Source Reader / Decoder MFT / D3D11"]
    Source --> AudioEngine["Show Audio Engine\n原唱/伴奏 / 音量 / Key / Fade"]

    Clock --> VideoDecoder
    Clock --> AudioEngine
    Clock --> Lyrics["KRL Renderer\n歌词 / Stage Overlay 预留"]

    VideoDecoder --> Compositor["StageCompositor\nD3D11 合成"]
    Lyrics --> Compositor
    AudioEngine --> AudioTap["Processed PCM Tap\n处理后 PCM"]

    Compositor --> Preview["Controller Preview\n本机预览"]
    Compositor --> StageWindow["Second Screen Stage\n双屏异显"]
    Compositor --> CastVideo["Cast Video Encoder\nH.264 hardware"]
    AudioTap --> CastAudio["Cast Audio Encoder\nAAC"]

    CastVideo --> Mux["MPEG-TS Muxer"]
    CastAudio --> Mux
    Mux --> Http["HTTP /cast/stage.ts"]
    Http --> DLNA["DLNA TV\nSetAVTransportURI"]
```

## Playback Authority

ShowHost PlaybackSession 是唯一播放权威。DLNA / Cast 只是一种输出端，
不能维护第二套播放状态。

CastBackend 必须跟随 ShowHost 的状态：

- load / next：切换当前媒体源。
- play：开始推进时间轴。
- pause：停止推进时间轴，重复暂停帧或输出静止帧。
- seek：跳到 ShowHost 指定位置。
- buffering：输出等待帧或重复最后一帧，不能让音视频继续漂移。

ShowHost 当前已经集中持有播放状态、位置、暂停位置、音轨和视频主时钟等
状态。Cast 侧需要补的是可读取/可订阅的边界，例如 current media source
和 playback revision / callback，而不是另建一套播放器。

## State Machine

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> LoadedPaused: load song
    LoadedPaused --> Playing: play
    Playing --> Paused: pause
    Paused --> Playing: play
    Playing --> Buffering: media not ready
    Buffering --> Playing: ready
    Playing --> Switching: next/load new song
    Paused --> Switching: next/load new song
    Switching --> LoadedPaused: loaded but paused
    Switching --> Playing: loaded and should play
    Playing --> Idle: queue empty/stop
```

## Media Foundation Boundary

Media Foundation 可以用于 native 媒体管线：

- video decode：Source Reader / decoder MFT / D3D11 texture。
- video encode：H.264 encoder MFT / hardware encoder。
- audio encode：AAC encoder MFT。
- D3D11 device / DXGI texture flow.

Media Foundation 不应该用于从窗口或预览框取帧。`TransferVideoFrame` /
窗口 readback 属于已经验证过的错误路线：它会把已显示的东西再抠回来，
既容易阻塞，也会绕开真正的 Stage 输出架构。

## Current Show Pipeline

当前 Show 的实际显示管线仍然是窗口层叠：

```text
MF Media Engine -> stage HWND / swap chain
LyricRenderer   -> independent WS_EX_LAYERED subtitle window
```

视频和字幕目前靠窗口 Z-order 组合，不是同一张 texture。DLNA / Cast 如果
直接从这些窗口取画面，就会回到窗口捕获路线，也会继续受到 Flutter 弹窗、
窗口层级和桌面焦点影响。

因此 StageCompositor 是投屏路线的核心阻塞项。它需要得到：

```text
video texture + transparent overlay texture -> composed stage texture
```

StageCompositor 必须维护固定节目画布，例如 1920x1080@30fps 或
1920x1080@60fps。源视频无论是 720p、1080p、4K、24fps、30fps 还是
60fps，都只是这个画布里的一个 source：按规则 letterbox / scale 后放入
画布，再叠加字幕；QR 和报幕后续按统一 Stage overlay 设计接入。
Encoder 只看到固定规格的 composed
stage texture，不直接感知源视频分辨率或帧率变化。

最终路线是用 MF Source Reader / Decoder MFT 或等价低级解码链路输出
D3D11 texture，再把 KRL 和后续统一 Stage overlay 渲染到透明 overlay
texture，最后合成。

允许有一个过渡路线：保留现有窗口输出，同时为 Cast 建立独立 offscreen
StageCompositor。过渡期可以重复解码当前视频，但它必须完全受 ShowHost
PlaybackSession 控制，不能自己推进时间轴。这个重复解码只应被记录为临时
技术债，后续需要收敛到统一 Stage 输出。

## Cast Video

Cast video 必须来自 ShowHost 主动合成的 Stage 画面：

1. 读取当前歌曲背景视频。
2. 按 16:9 Stage 输出 letterbox / scale。
3. 叠加 KRL 歌词；QR、报幕和指示层等后续按统一 Stage overlay 接入。
4. 输出给 H.264 encoder。

未播放时不能推进视频。暂停时不能推进视频。切歌时优先保持 HTTP / DLNA URL
稳定，可以重复最后一帧或输出 idle frame，等新源 ready 后继续输出 SPS/PPS
和 IDR。因为 Cast 输出是固定画布，切歌不应该改变 encoder 的输出分辨率、
帧率或基础流规格。真实电视兼容性不佳时，允许重建内部 encoder/session，
但外部 URL 应尽量稳定，并把这种行为记录为设备兼容策略，而不是默认架构。

## Cast Audio

Cast audio 必须来自 Show 音频处理链之后的 PCM。它必须已经应用：

- 原唱 / 伴奏切换。
- volume。
- key shift。
- key fade。

CastBackend 不能重新读取 vocal / inst 文件，也不能偷用背景视频自带音轨。
否则 DLNA 听到的声音会和房间实际播放不一致。

## Fallback Policy

ffmpeg 可以作为开发 fallback，用于临时验证 HTTP MPEG-TS / DLNA 控制面。
它不能成为默认生产链路，也不能独立读取当前视频并自行推进时间轴。

如果 fallback 存在，必须满足：

- 默认关闭或显式标记为 dev-only。
- 不冒充最终 NativeCastBackend。
- 不绕过 ShowHost PlaybackSession。
- 不绕过 Show 音频处理链。

## DLNA Control Surface

DLNA 控制面不是单个 URL 推送按钮。第一版可以做最小可用子集，但仍然要把
这些模块当成真实边界：

- SSDP discovery：M-SEARCH / NOTIFY。
- device description：解析 device.xml 和 service URL。
- ConnectionManager：`GetProtocolInfo`。
- AVTransport：`SetAVTransportURI` / `Play` / `Pause` / `Seek`。
- RenderingControl：`SetVolume`。

可以评估 libupnp、Platinum 或自写最小子集。协议层不能反过来拥有播放状态；
它只把电视端控制映射回 ShowHost 命令。

## Phase Checklist

- Done: old local `DLNA-dev` branches were discarded and recreated from
  App `dev` and Show `main`.
- Done: this document freezes the cast architecture and forbidden paths.
- Done: ShowHost current media source / playback revision boundary.
- Done: Show fixed-canvas StageCompositor proof:
  1920x1080 canvas, source letterbox rect, transparent overlay texture, and
  native D3D/DXGI/D2D handles.
- Done: StageCompositor scales BGRA/D3D texture sources into the fixed canvas
  with D2D DrawBitmap, then allows lyrics to render into the same texture.
- Done: dev raw-BGRA cast stream is driven by ShowHost state; pause/stop do
  not advance the diagnostic frame.
- Done: transitional MF SourceReader BGRA video frames are driven by ShowHost
  playback time and wired into StageCompositor.
- Done: dev raw-BGRA fallback output is frame-rate throttled and preserves
  whole-frame socket ordering with a pending buffer.
- Done: dev raw-BGRA fallback socket/pacing state is isolated in a sink class
  so Host commands no longer own fallback transport details.
- Deferred: QR and report/ticker overlay are disabled until the second-screen
  Stage overlay design is unified.
- Done: processed PCM tap / ring buffer boundary in Show audio output path.
- Not done: NativeCastBackend.
- Not done: decoder-backed D3D11 video texture / H.264 encode.
- Not done: processed PCM to AAC encode.
- Done: native MPEG-TS muxer foundation for PAT/PMT/PES/PTS/PCR packets.
- Done: AAC ADTS packetizer foundation for wrapping encoded AAC frames.
- Not done: wire H.264/AAC encoder output into MPEG-TS and HTTP `/cast/stage.ts`.
- Not done: DLNA discovery and `SetAVTransportURI`.

## Verification Requirements

The cast implementation is not considered working until these are all true:

- Before pressing play, cast video does not run.
- During play, cast video follows ShowHost time.
- During pause, cast video freezes.
- After seek, cast video jumps to the same position as ShowHost.
- After next /切歌, cast switches to the new song without opening a second
  independent player.
- HTTP `/cast/stage.ts` survives pause, seek, and next.
- Cast audio reflects original / accompaniment, volume, key, and key fade.
