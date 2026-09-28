# Phase 4：生命周期与失败恢复

## 范围与结论

本阶段只处理主控预览运输和单 HWND DirectComposition 树的生命周期，不改变 Show
的歌词解析、播放时钟、物理 Stage 或 Cast 语义。当前 Windows 11、单显示器、NVIDIA
环境的自动门禁已通过；真实锁屏、睡眠、显示器热插拔、混合 DPI 迁移和 graphics
device removal 仍需要对应硬件/系统事件，不能由测试消息的通过结果替代。

已完成的生命周期边界：

- Runner 为 `libshow_host.dll` 持有自己的 loader 引用。Dart FFI 在 Show 重建时关闭并
  重新加载 DLL，不会让已解析的 C ABI 函数指针悬空；释放顺序为 callback、source、
  D3D device、DLL。
- composed 和 external texture 两条后端都支持显式 detach。即使 Windows allocator
  复用相同的原生 Show 指针，新实例也不会误命中旧 attachment 缓存。
- composed source 替换是事务式的：先绑定设备并完整创建未激活的候选 source；只有
  候选成功且 Engine detach 成功后才停用、销毁旧 source。候选准备失败时旧 source
  保持有效。
- `requestedActive` 与实际 `active` 分离。最小化、会话锁定或系统挂起只把预览 source
  停用并从下层 Visual detach；播放继续，恢复后使用同一 HWND、同一 Show 和最后一次
  geometry 自动续接最新帧。
- Runner 注册 `WTSRegisterSessionNotification(..., NOTIFY_FOR_THIS_SESSION)`，处理
  `WM_WTSSESSION_CHANGE`；同时处理 `WM_SIZE` 和 `WM_POWERBROADCAST`。这条路径不使用
  轮询、常驻定时器或同步 Dart 回调。
- App 退出时 Runner 先拒绝新 callback，再停用/销毁 source 和 external texture
  transport，最后销毁 Flutter controller。另有测试模式会故意跳过 Dart 清理，在
  Stage 仍活跃时关闭顶层窗口，以覆盖原生 shutdown 顺序。

## 自动门禁

运行命令：

```powershell
Set-Location 'D:\Kirakara-App-ascii'
.\tool\windows_compositor\run_real_stage_compositor_probe.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -LocalEngine host_debug_kirakara_v3 `
  -LifecycleProbe `
  -ExitWhileActive `
  -TimeoutSeconds 100
```

`build/diagnostics/real-stage-lifecycle-phase4-commit.json` 的关键结果：

| 有界样本 | Stage Present 增量 | 结论 |
| --- | ---: | --- |
| 最小化后的 900 ms | 1 | 只剩切换边界上的 1 帧，Show publish 同为 1 |
| 最小化恢复后的 1250 ms | 67 | 同一顶层 HWND 自动恢复 |
| 模拟 session lock 的 350 ms | 0 | 预览 source 停止，`requestedActive=true` |
| 模拟 session unlock 的 900 ms | 47 | 预览自动恢复 |
| 模拟 power suspend 的 350 ms | 0 | 预览 source 停止 |
| 模拟 power resume 的 900 ms | 51 | 预览自动恢复 |
| 模拟 `WM_DISPLAYCHANGE` 的 500 ms | 30 | 消息处理后 Stage 保持前进 |
| 最终静止 Flutter 的 2 s | 120 | Flutter Present 增量为 0 |

测试消息直接投递到真实顶层窗口，覆盖与操作系统通知相同的 Win32 handler 和状态机，
但报告内固定记录 `realOperatingSystemTransition=false`。它们只证明代码路由，不证明
机器真的完成过锁屏、睡眠或热插拔。

同一探针还覆盖：最小化/恢复、最大化/恢复、六次快速全屏 Flutter 页面切换、Show
销毁后同进程重建、detach/reattach、自然 EOF 后载入下一首，以及 Stage 活跃时直接
退出。所有 callback rejection、NT handle duplication、resource open、stale frame、
device removal 和最终 HRESULT 计数均为零。

external texture 回退使用官方 debug Engine 和定制 debug Engine 各复测一次 Show
重建：

- 官方 Engine 的第一次 1 s 样本为 `60 callback / 36 acquire`，低于既定 40 门槛；
  原样保留为调度波动负样本。未改代码立即复测为 `60 / 48`，Show 重建后的 750 ms
  为 `45 / 41`，通过。
- 定制 Engine 强制 external texture 为 `60 / 59`，Show 重建后为 `45 / 41`，通过。

这与 Phase 0 已记录的 Flutter external texture 帧调度相位波动一致；没有通过降低
门槛或把失败归入 composed backend 来掩盖。

提交前回归结果：

- Phase 4 相关 Dart analyze 无诊断；`stage_texture_service_test.dart` 5/5 通过，包含
  replacement attach 失败后保留旧 attachment 并可重试的门禁。
- App 全量 `flutter analyze` 仍为 Phase 0/1 已记录的 68 条 info，无新增 warning/error。
- App 全量 `flutter test` 为 84 项通过、2 项既有失败：Bilibili 清晰度列表缺少 `6`
  和外链页旧“登录哔哩哔哩”文案断言；失败位置与 Phase 1 相同，均不在合成器改动中。
- Show 仓库 `ctest --test-dir build --output-on-failure` 为 37/37 通过。
- 最终 composed lifecycle probe、官方 Engine external texture 复测和定制 Engine
  external texture 复测均使用各自校验过的 DLL bundle；未把 DLL/PDB 写入 Git。

## 仍需真实系统事件的手工门禁

先在普通 PowerShell 启动可交互产物：

```powershell
Set-Location 'D:\Kirakara-App-ascii'
.\tool\windows_compositor\run_real_stage_compositor_probe.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -LocalEngine host_debug_kirakara_v3 `
  -LifecycleProbe `
  -KeepOpen
```

自动门禁完成后窗口会保留。需要逐项执行并记录，不要把多种事件混进同一条结论：

1. 最小化 10 秒再恢复；确认歌曲时钟继续、恢复后直接显示最新帧，没有黑孔、旧帧、
   白闪或额外顶层窗口。
2. `Win+L` 锁屏，等待至少 10 秒后解锁；检查同上，并确认播放没有被预览恢复改写。
3. 睡眠后恢复；检查主控、Show 重建需求、音频时钟和窗口输入。若系统/驱动移除了
   图形设备，必须保留 HRESULT 和崩溃转储，不能把重新启动后正常当作恢复通过。
4. 在两台不同 DPI/刷新率显示器之间移动，随后全屏/退出全屏、最小化/恢复；检查
   透明孔、圆角、clip、输入和面板遮盖。175%/200% 留到真实高分屏执行。
5. 在 App 运行时热插拔非主显示器，再以该显示器作为主显示器复测。记录物理 Stage
   和 Cast 是否同时启用；当前单屏机器没有覆盖这一项。
6. graphics device removal 只在可恢复的测试机和受控驱动测试环境执行。不要为了本
   项自动修改 TDR 注册表；真实 `DXGI_ERROR_DEVICE_REMOVED/RESET` 后需验证同进程恢复
   或明确兼容回退，并检查没有孤立 DComp target/Visual。当前实现只记录该 HRESULT，
   尚未用真实 TDR 证明恢复，因此此项保持未验证。

需要 GPU/DWM 证据时，在已经提权的独立 PowerShell 中为单一场景采集：

```powershell
Set-Location 'D:\Kirakara-App-ascii'
.\tool\windows_compositor\capture_compositor_trace.ps1 `
  -DurationSeconds 30 `
  -OutputPath '.\build\diagnostics\phase4-<scenario>.etl'
```

每项保存对应 ETL、自动 JSON 报告、操作系统版本、显示拓扑和观察到的时间点；ETL、
DLL、PDB、缓存与临时测试产物都留在被忽略的 `build/diagnostics` 或外部构建目录，
不提交普通 Git 历史。

## 已验证与未验证边界

已验证：同 HWND resize/maximize/minimize、预览按窗口可用性停启、测试消息路径、快速
导航、Show rebuild、重复 attachment、活跃退出、官方/定制 external texture 回退，
以及恢复后的静止 Flutter 不被 Stage 重新拖入帧泵。

未验证：真实锁屏/睡眠、真实显示器热插拔、混合 DPI 跨屏、175%/200% 真高分屏、真实
device removal、Windows 10、Intel/AMD、物理双屏和 Cast 并行。这些进入 Phase 7 实机
矩阵，不能由当前 NVIDIA 单屏自动报告外推。
