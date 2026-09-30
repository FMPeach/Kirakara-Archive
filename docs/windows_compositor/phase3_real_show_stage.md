# Windows 定制合成器 Phase 3：真实 Show Stage

## 当前结论

Phase 3 已把真实 KiraKara Show Stage 接入单 HWND 的下层 DirectComposition
Visual，并保留原有 Flutter external texture 后端用于官方 Engine 与定制 Engine
A/B。当前 RTX 4060 Ti / Windows 11 / 96 DPI 实机自动门槛通过：静止 Flutter 的
2 秒最终样本中，Show 提交和下层 Stage Present 都增加 120，Flutter Present 增量为 0；
人为阻塞 Flutter platform thread 750 ms 时，Stage 继续 Present 45 帧，Flutter
Present 增量仍为 0。

真实运输门槛还覆盖了第一首与后续歌曲、无标题与带标题 KRL、暂停/恢复、重唱、
12 秒自然 EOF、视频主时钟下音频先 EOF 与视频先 EOF 两种刻意失配、失配后普通歌曲
恢复、预准备后的 seamless 自然下一曲、generation 切换、contain/cover、裁切、Flutter
半透明面板与全屏页面、窗口缩放，以及 detach/reattach。最终样本没有 callback 拒绝、NT
handle 复制失败、共享资源打开失败、stale frame 或 device removal。官方 debug
Engine 与 `host_debug_kirakara_v3` 也分别通过同一 external texture integration
smoke，证明回退路径没有因 composed 接入而腐烂。

2026-09-30 的发布后回归修复补齐了两个显示边界。Engine 在外部 Show 尚未提交资源时
创建 16×9 composition swapchain，只清为不透明黑色并 Present 一次；真实 Show 探针
在加载第一首歌前测得 Stage Present 为 1，而 Show callback、Stage frame submit、
resource/content generation 与 frame ID 全为 0。App 同时在未选歌时保留 Flutter 黑色
上盖，避免初始化时序或非定制 Engine 暴露未定义 HWND 背景。播放后，完整的 Show Stage
画布使用 `fill` 映射到实际预览 viewport；paint-transform/layout 变化会事件式重报物理
矩形，不增加轮询或常驻 timer。窗口几何探针中 `stageGeometryUpdateCount` 从 3 增至 5，
所有 HRESULT、资源和同步门槛通过，报告为
`build/diagnostics/real-stage-compositor-20260930-123139.json`。

这不是 Phase 4 生命周期结论。最小化/恢复、显示器热插拔、睡眠/恢复、锁屏、主动
graphics device removal、Show 销毁后重建和退出竞态仍要在下一阶段实现和验证。当前
环境也没有物理双屏或 Cast 接收端，因此本阶段只证明 composed preview 不在代码或
同步协议上形成反压；物理 Stage / Cast 的并发实机矩阵仍保留为未验证项。

## 锁定版本

- App branch：`main`
- Show branch：`main`
- Show commits：`40e51d8 feat: add keyed Stage visual transport`；
  `7a822b2 test: harden Stage visual synchronization smoke`
- Flutter Framework：`ad70ec4617166f1c38e5d2bfd388af71fda14f06`
- Flutter Engine：`a10d8ac38de835021c8d2f920dbf50a920ccc030`
- Engine patchset：ABI 2、version 5、`windows-dcomp-stage-visual`
- Engine patch SHA-256：
  `177E4A44817ADD629FA65159028FD5CA901CA9557D9670E2E3D54CEFBCF22279`、
  `02978CD10DB85ABCBE2FB113C8B9D7A522527F6C94A4421B56B00F0592F4B76F`
- patched source tree：`8144c37c3b06ac036c1ef6fd34c382a0dc2ce730`
- repository-local source tree：`bbec608dcc93d6b6b0c59dc83db9ba7460e3cb80`
- debug local Engine：`host_debug_kirakara_v4`（输出目录名沿用，运行时以 patchset 5 门禁）

二进制与 PDB 只存在于外部 Engine `out/` 和本地 App `build/`，没有进入普通 Git
历史。精确尺寸和 SHA-256 由 `engine/engine.lock.json` 锁定。

## 运输协议

Runner 与 Show 通过版本化的 `show_host_get_stage_visual_api` 握手。协议 revision 为
`nt-keyed-latest-v1`，结构体固定携带：

- `resource_generation`：共享纹理重建代次；
- `content_generation`：歌曲/节目代次；
- 单调 `frame_id`；
- BGRA8 尺寸和 DXGI format；
- `D3D11_RESOURCE_MISC_SHARED_NTHANDLE` 的 NT handle；
- `D3D11_RESOURCE_MISC_SHARED_KEYEDMUTEX` 的 acquire/release key。

Runner 先从 Flutter 所在的 DXGI adapter 创建独立 Show producer D3D11 device，再把
device 交给 Show。Show 从最终统一 Stage GPU 输出复制到 publication texture，随后
用 keyed mutex `ReleaseSync(consumerAcquireKey)` 发布完成帧。这里的 ReleaseSync 是
跨 device 命令提交边界；composed 路径没有无条件逐帧 `Flush`。stock external
texture 路径原有的 Flush 被原样保留，仅用于兼容回退。

Show callback 只校验并向 Engine 的 latest-frame mailbox 提交一个小描述符：

- 不等待 keyed mutex、DComp、Flutter platform/raster thread；
- 不同步调用 Dart；
- 新描述符覆盖 mailbox 内尚未消费的旧描述符，旧预览帧计入 coalesced 后丢弃；
- resource generation 回退或同一 content generation 的非递增 frame ID 直接作为
  stale frame 丢弃；
- Show producer 对 publication mutex 使用非阻塞获取，consumer 忙时只丢预览帧，
  不反压播放、物理 Stage 或 Cast。

Engine consumer thread 只在 stop event 或 mailbox event 上
`WaitForMultipleObjects(INFINITE)`，没有周期性 timer 或主动轮询。新资源只在
generation 变化时复制 NT handle 并用 `OpenSharedResource1` 打开。每帧先以零超时
`AcquireSync` 探测：正常路径立即取得 mutex；若返回 `WAIT_TIMEOUT`，说明 callback
已经在生产者成功 `ReleaseSync` 后到达、但跨设备 GPU 工作尚未完成，此时只在专用
consumer thread 上对这一帧做一次等待。不能把该描述符当成可丢弃的过期帧，否则
mutex 会停在 consumer key，生产者后续的非阻塞 acquire 将永久失败。取得纹理后以
GPU `CopyResource` 写入下层 composition swapchain，`ReleaseSync` 后 Present。该等待
不会发生在 Show callback、Show producer、Flutter platform/raster thread、物理 Stage
或 Cast 路径；没有 CPU map/readback，也没有轮询重试。

## 合成与布局

composed backend 的树保持为：

```text
main interactive top-level HWND
└─ DComp root
   ├─ Show Stage visual
   │  └─ independent composition swapchain
   └─ Flutter visual
      └─ premultiplied-alpha composition swapchain
```

Flutter Stage Widget 在 composed 模式绘制透明孔，并在布局帧结束后把物理像素矩形
报告给 Runner。Engine 原生处理 contain、cover、fill、transform 和 clip。Flutter
之后绘制的按钮、面板、遮罩和页面自然位于 Stage 上方；它们不会重新挂载 HWND，也
不会改变窗口大小。

窗口 resize 保留同一 HWND、DComp target/root/Visual tree。resize 期间只暂时解除
Stage Visual，原位 Resize Flutter swapchain，并在新尺寸 Flutter 上层首次 Present
后恢复 Stage，以避免 Phase 2 已修复的白闪和 Stage 穿透。

自动枚举会看到两个带 `WS_VISIBLE` 的顶层窗口：主控窗口，以及 Show 既有的离屏
`WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE` MediaEngine 时钟宿主。后者不是 Stage 叠加
窗口、不能交互且没有进入 z-order 方案；门槛要求可交互顶层窗口精确为 1，并同时
记录 raw count，避免把既有内部工具窗口隐藏成假证据。

## App 后端选择

`StageTextureController` 返回显式的 `StagePresentationAttachment`：

- `composed`：没有 Flutter texture ID，Widget 绘制透明孔并报告 geometry；
- `externalTexture`：继续创建现有 `Texture(textureId: ...)`。

未设置 `KIRAKARA_COMPOSITOR_BACKEND` 时，Runner 会检查已加载 Engine 的版本化
Kirakara compositor export：定制 Engine 默认选择 `composed`，官方/stock Engine
没有该 export 时继续使用既有 external texture。只要 export 存在，ABI、patchset、
Show API 或同步结构失配都会清晰报错并停止，不会静默落入回退掩盖实现 Bug。
`composed`、`external_texture`、`stock` 仍可作为显式开发/A/B 覆盖；A/B 脚本始终
显式设置 `external_texture`，不会依赖调用者残留的环境变量。真实 Stage 探针会主动
清除调用者的 backend 环境变量，并要求报告中的 `backendSelection` 为
`custom-engine-default`，从而直接验证产品默认路径。

## 自动验证结果

2026-09-28 的基础真实探针报告为本机忽略目录中的
`build/diagnostics/real-stage-compositor-20260928-165313.json`；2026-09-29 的失配 EOF
与生命周期合并复验为
`build/diagnostics/real-stage-lifecycle-eof-mismatch-20260929-101755.json`。2026-09-30
恢复 DPI-unaware 并启用产品默认 composed 路径后的联合复验为
`build/diagnostics/real-stage-default-composed-dpi-unaware-20260930.json`：backend 为
`composed`、selection 为 `custom-engine-default`、awareness 为 `0`、window DPI 为
`96`，全部门槛通过。关键数据：

| 门槛 | 实测 |
| --- | ---: |
| 静止 UI 2 秒 Show submit / Stage Present / Flutter Present | 120 / 120 / 0 |
| platform thread stall 750 ms Stage / Flutter Present | 45 / 0 |
| 暂停稳定后再等待 500 ms 的时钟漂移 | 0.000 s |
| 恢复 750 ms 的时钟推进 | 0.744 s |
| 无标题到带标题 content generation | 1 → 3 |
| 重唱前 / 后 position | 1.222 s / 0.718 s |
| 自然 EOF position / duration / state | 12.000 / 12.000 / stopped |
| 音频先 EOF：video / vocal / accompaniment / 越过双音轨 EOF 时 position / state | 6.000 / 2.000 / 2.000 / 2.348 / playing |
| 音频先 EOF：最终 position / state / buffering | 6.099 / stopped / false |
| 视频先 EOF：video / vocal / accompaniment / 最终 position / state / buffering | 2.000 / 6.000 / 6.000 / 2.090 / stopped / false |
| prepared seamless 下一曲 position / state | 1.210 s / playing |
| callback rejected / stale / device removed | 0 / 0 / 0 |
| keyed mutex 初次零超时 busy | 0（本机未触发等待分支） |

重唱使用 Show 可选 `show_host_replay` 导出；当前 ABI 没有该导出，因此探针执行 App
现有语义等价回退 `seek(0)` + `play()`，并明确把
`nativeReplaySupported=false` 写入报告。标题门槛验证实际标题 KRL 被 Show 接受并
沿真实 Stage 路径播放；标题像素渲染正确性由 Show 的 renderer tests 负责，本探针
不借没有截图证据的结果宣称逐像素一致。

自然切歌门槛在当前标题曲播放期间调用 `prepareNext` 预热首曲，等待当前媒体自然
进入 stopped 后，再以 `SHOW_TRANSITION_SEAMLESS` 加载已准备曲目；报告要求
`prepared=true`、新 content generation、playing 状态、推进的时钟和持续的 Stage
Present。它不是先发 stop 的手动切歌。

失配 EOF 门槛使用 ffmpeg 生成但不提交媒体：一组是 6 秒视频配 2 秒双音轨，另一组是
2 秒视频配 6 秒双音轨。两组都保持 App 现有 `videoMasterClock=true` 语义。探针只做
由媒体 duration 推导的有限等待；第一组要求越过音频 EOF 后仍为 playing、非 buffering
且 Stage 继续 Present，随后在视频 EOF 停止；第二组要求在较短视频 EOF 停止而不等待
较长音轨。最后再载入普通曲目并要求时钟和 Stage 恢复，过程中没有增加轮询器或修改
Show 时钟实现。

外部纹理 A/B 的同一秒样本：

- 官方 debug Engine：60 callback、60 advanced acquire、60 带新 acquire 的
  Flutter Present；inactive 750 ms 为 0 callback / 0 Present；
- v3 定制 debug Engine 在同步修正后强制 `external_texture`：60 callback、60 advanced
  acquire、60 带新 acquire 的 Flutter Present；inactive 750 ms 同样为 0 / 0。
- 2026-09-30 当前 v4 定制 debug Engine 在 DPI-unaware 配置下再次强制
  `external_texture`：61 callback、60 advanced acquire、60 Present；hidden/inactive
  样本均为 0，Show 重建后继续通过。

两者都满足 Phase 0 冻结的 cadence 一致性门槛。60 Hz producer 与 60 Hz Flutter
调度之间的相位合并仍然存在于 external texture 回退路径，这正是保留 A/B 而不把
它误写成新架构性能结论的原因。

同步修正后的 Engine 门槛为定制 API 6/6、关键调度 2/2、上游 compositor/display/
DPI/texture 25/25、adapter 隔离 2/2，全部通过。Show 仓库 37/37 CTest 通过；双
D3D11 device 的显式 GPU smoke 为 44 callback / 44 acquire，并在 consumer 占用时
按设计丢弃 24 个预览帧，资源 generation 最终为 3，未反压播放管线。

## 复现命令

```powershell
Set-Location 'D:\Kirakara-App-ascii'

.\engine\scripts\verify_engine_bundle.ps1 `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -Variant patched `
  -Mode debug `
  -RequireLockedHashes

.\engine\scripts\test_patched_windows_engine.ps1 `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine'

.\tool\windows_compositor\run_real_stage_compositor_probe.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -LocalEngine host_debug_kirakara_v3 `
  -TimeoutSeconds 90

.\tool\windows_compositor\run_windows_stage_texture_baseline.ps1 `
  -ShowRepository 'D:\仓库\Kirakara Show' `
  -FlutterExecutable 'D:\Program Files\Flutter\bin\flutter.bat' `
  -Mode debug `
  -Engine official

.\tool\windows_compositor\run_windows_stage_texture_baseline.ps1 `
  -ShowRepository 'D:\仓库\Kirakara Show' `
  -FlutterExecutable 'D:\Program Files\Flutter\bin\flutter.bat' `
  -Mode debug `
  -Engine local `
  -LocalVariant patched `
  -EngineWorkspaceRoot 'E:\Kirakara-Flutter-Engine'
```

`run_real_stage_compositor_probe.ps1` 默认使用 `%TEMP%\kira_fixtures` 的两组
720p60/12 秒 Show 素材，以及仓库内的小型 `title_probe.krl`。传入
`-EofMismatchFixtureRoot` 时再执行由 `make_eof_mismatch_fixtures.ps1` 生成的两组失配
素材。它只做有限次数的等待与采样，运行结束即关闭；不会留下后台采集器或常驻
计时器。`-KeepOpen` 仅用于人工视觉观察。

## 已验证与未验证

已验证：

- 真实 Show GPU 帧通过 NT handle/keyed mutex 进入下层 Visual；
- 最新帧 mailbox、generation 切换、资源代次、非阻塞 producer；
- contain/cover、clip、geometry、detach/reattach；
- 静止 Flutter 不被 Stage 帧泵唤醒；Flutter 短暂停顿不阻塞 Stage；
- 面板、遮罩与全屏 Flutter 页面覆盖实时 Stage；
- 第一首、后续曲、标题/无标题、暂停/恢复、重唱、自然 EOF、两种视频主时钟失配
  EOF、失配后恢复、预准备自然切歌；
- 官方与定制 Engine 的 external texture 回退。

仍需 Phase 4 或实机矩阵验证：

- 最小化/恢复、锁屏、睡眠、热插拔和 graphics device removal 后的事务式恢复；
- Show 销毁/重建与 App 退出并发；
- 不同 DPI 多屏迁移、175%/200% 真高分屏；
- 物理双屏与 Cast 同时运行时的时钟、吞吐和失配 EOF；
- Intel/AMD，以及 Windows 10；
- 4K 下采样与 576p/540p/480p/360p 上采样的实机视觉结果。
