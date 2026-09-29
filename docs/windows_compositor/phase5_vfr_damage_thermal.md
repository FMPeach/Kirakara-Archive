# Phase 5：VFR、Damage、遮挡与热限制

## 范围与结论

本阶段没有改变歌词解析、播放时钟、物理 Stage 或 Cast，也没有增加轮询、常驻
timer、CPU readback 或逐帧 `Flush`。当前实现把“用户请求预览”“顶层窗口可用”和
“预览 geometry 可见”合成为实际 activity：任一条件为假，预览 consumer 会停用；
恢复条件后继续取得最新完成帧，不追赶过期帧。

当前 Windows 11、RTX 4060 Ti、单屏环境的自动退出条件已经通过：

- composed backend 的纯 Stage 更新仍为 Stage `+120`、Flutter Present `+0`；
- Flutter 进行 1.4 秒透明度动画时，Stage `+84`、Flutter Present `+99`，两条节奏
  同时前进；
- 预览 geometry 隐藏后的 750 ms 内 Show publish 和 Stage Present 均为 `+0`，恢复
  后 750 ms 均为 `+42`；
- 播放暂停并稳定后的 500 ms 内 Show publish 和 Stage Present 均为 `+0`；
- external texture 回退也会在窗口不可用时停止 callback/texture acquire，官方与
  定制 Engine 均已 A/B 验证；
- 生命周期回归、Show 同进程重建和 Stage 活跃退出仍通过。

这些数据证明当前机器上的调度和 idle/visibility 门禁，不等同于 Iris Xe 长时间热
稳定性。1130G7、物理双屏、Cast 并行、真实遮挡和不同 GPU 的功耗/降频结论保留到
Phase 7 实机矩阵。

## Activity 状态机

composed backend 的实际 Stage activity 为：

```text
requestedActive && windowAvailable && geometryVisible
```

external texture 回退没有 geometry API，实际 activity 为：

```text
requestedActive && windowAvailable
```

`windowAvailable` 由 Win32 事件驱动更新：窗口隐藏/最小化、session lock 和 power
suspend 会停用 consumer，恢复事件会重新激活。Flutter 页面销毁或主动隐藏预览时，
Dart attachment/geometry 路径更新 `requestedActive` 或 `geometryVisible`。没有通过
高频 `IsWindowVisible` 查询、遮挡探针或 Dart timer 轮询状态。

对 composed backend，geometry 先提交给 Engine，再改变实际 activity；失败不会把
Runner 状态推进到与 Engine 不一致的位置。隐藏会停用 Show source 并从 Stage Visual
detach，恢复时复用同一顶层 HWND 并按 latest-frame 语义重新接入。对 external texture
backend，窗口可用性使用与 composed backend 相同的 Runner 生命周期信号，标准 Flutter
texture 注册和 `Clipboard` 等其他平台通道不变。

## 自动门禁与实测

最终 composed 报告：

- `build/diagnostics/real-stage-phase5-vfr-final.json`
- `build/diagnostics/real-stage-phase5-lifecycle-final.json`

关键有界样本：

| 场景 | 时长 | Show publish | Stage Present | Flutter Present |
| --- | ---: | ---: | ---: | ---: |
| 静止 Flutter、播放中 | 2001 ms | +120 | +120 | +0 |
| platform thread stall | 750 ms | 继续前进 | +45 | +0 |
| geometry 隐藏且已稳定 | 750 ms | +0 | +0 | 不要求新帧 |
| geometry 恢复 | 750 ms | +42 | +42 | 不由 Stage 驱动 |
| Flutter 淡入/淡出动画 | 1400 ms | +84 | +84 | +99 |
| 暂停且已稳定 | 500 ms | +0 | +0 | 不适用 |
| 完成交互后再次静止 | 2000 ms | +120 | +120 | +0 |

报告中的 `requestedActive`、`active`、`windowAvailable`、`geometryVisible` 和
`activityTransitionCount` 使停用原因可审查；callback rejection、handle duplication、
resource open、stale descriptor 和 device removal 计数均为零。生命周期复跑还覆盖
最小化/恢复、session/power 测试消息、显示变化消息、快速导航、Show rebuild 和活跃
退出，所有 Phase 4 门禁继续通过。

复现 composed 测试：

```powershell
Set-Location 'D:\Kirakara-App-ascii'
.\tool\windows_compositor\run_real_stage_compositor_probe.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -LocalEngine host_debug_kirakara_v3 `
  -TimeoutSeconds 120 `
  -ReportPath '.\build\diagnostics\real-stage-phase5-vfr.json'
```

复现生命周期回归时再加 `-LifecycleProbe -ExitWhileActive`，并使用新的报告文件名。
脚本不会覆盖既有报告。

external texture A/B 的窗口不可用测试通过测试专用 method channel 注入，只有
`KIRAKARA_COMPOSITOR_TEST_MODE=1` 才接受该调用，运行脚本会在 `finally` 中恢复环境
变量。结果如下：

| Engine | 活跃 1 s callback/acquire | 隐藏 750 ms | 恢复 750 ms | inactive | Show rebuild |
| --- | ---: | ---: | ---: | ---: | ---: |
| 官方 debug | 61 / 59 | 0 / 0 | 34 / 33 | 0 / 0 | 45 / 45 |
| `host_debug_kirakara_v3` | 60 / 60 | 0 / 0 | 35 / 35 | 0 / 0 | 45 / 43 |

这条测试 API 不在生产条件下开放，也没有改变外部纹理兼容回退的公开协议。

## VFR 与超载策略

Show 已有的 `NativeStageFrameScheduler` 在画面完全静止时跳过无意义 render/present；
本阶段的暂停样本以真实 Show 证明稳定窗口为零帧。物理 Stage 活跃时，既有
`StageTexturePublicationCadence` 只限制可选主控预览 consumer，物理输出仍保持原有
60 Hz producer：

- 正常为 30 fps 预览 publication；
- 持续错过 host slot 时按 30 -> 20 -> 15 fps 降级；
- 单次严重瞬态不会触发降级；
- 连续稳定 12 秒后一次恢复一个等级；
- 晚到的 consumer 只发布最新帧，不补发错过的 publication。

`kirakara_show_stage_texture_publication_cadence_tests` 和
`kirakara_show_native_stage_frame_scheduler_tests` 均通过。这里没有新增 Show 修改，
也没有让预览压力反向改变播放时钟、物理 Stage 或 Cast。

## Damage 的准确边界

锁定的上游 Windows `Compositor::Present` 接口只接收 layers 和 layer count，没有将
dirty rectangle 传入平台 compositor；`CompositorOpenGL::Present` 对收到的 Flutter
帧执行整张 framebuffer blit，然后 `SwapBuffers()`。因此本阶段没有伪造“Windows
局部 Present 已验证”的结论，也没有为了标签而维护高风险的额外 Engine patch。

已验证且真正降低成本的是：Stage-only 更新根本不请求 Flutter frame；Flutter 真正
需要动画时仍走锁定上游的 raster/backing-store/Present 行为。未来若上游接口提供可
审查的 damage 传播，可作为独立补丁评估，不能混入 Stage transport。

## 回归结果

- Show cadence/scheduler 聚焦 CTest：2/2 通过。
- composed VFR probe：所有 runtime gates 通过，脚本以退出码 0 结束。
- composed lifecycle probe：所有 Phase 4/5 runtime gates 通过，脚本以退出码 0 结束。
- 官方和定制 debug Engine 的 external texture visibility A/B：均通过，并核对实际
  bundle DLL。
- Phase 5 两个改动 Dart 文件的聚焦 analyze 无诊断；`stage_texture_service_test.dart`
  5/5 通过。
- App 全量 `flutter analyze` 仍为既有 68 条 info，无新增 warning/error；全量
  `flutter test` 为 85 项通过、2 项既有失败：Bilibili 清晰度列表缺少 `6`，以及外链
  页面旧“登录哔哩哔哩”文案断言。这两处与 Phase 1/4 记录相同，不在合成器改动中。
- `git diff --check` 通过。

## 实机热限制与兼容性步骤

在 1130G7 或同级受限核显上，用 `-KeepOpen` 保留真实 Show harness，分别采集以下单一
场景，每项至少 20 分钟并单独保存 ETL/计数报告：单屏主控预览、物理双屏 + 主控预览、
Cast + 主控预览、物理双屏 + Cast + 主控预览、Flutter 面板动画。记录 GPU 频率/占用、
封装功耗、温度、Show missed slots、预览 cadence 等级、物理 Stage cadence 和音频时钟。
在真实 Show 场景之前，先按 `phase7_compatibility_release.md` 的 `-SoakSeconds 1800`
步骤运行 synthetic 有界门禁，保存冷机/半程/终点计数；该自动门禁不替代上述真实业务
拓扑与视觉观察。

管理员 PowerShell 仅在采集 WPR/ETW 时需要：

```powershell
Set-Location 'D:\Kirakara-App-ascii'
.\tool\windows_compositor\capture_compositor_trace.ps1 `
  -DurationSeconds 30 `
  -OutputPath '.\build\diagnostics\phase5-<scenario>.etl'
```

当前 UAC 终端没有保持成功，因此自动验证没有冒充管理员采集。ETL、JSON、DLL、PDB
和构建缓存仍放在忽略目录或外部 Engine workspace，不进入普通 Git 历史。

已验证：事件驱动的隐藏/恢复、暂停静态 VFR、Flutter 动画期间 Stage 独立前进、静止
Flutter 不被 Stage 帧泵拖动、external texture 回退的窗口 lifecycle，以及现有
latest-frame/自适应 cadence 单元语义。

未验证：Iris Xe 1130G7 长时间热负载、真实窗口完全遮挡检测、Windows 10、Intel/AMD、
真实物理双屏/Cast 压力、真实 mixed-DPI 跨屏、175%/200% 真高分屏、真实 device
removal。150% 当前屏幕测试已通过；用户决定其余比例留到真正高分屏执行。
