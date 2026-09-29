# Windows 定制合成器 Phase 2：合成 DirectComposition 技术验证

## 当前结论

Phase 2 已完成源码、可复现构建、ABI、单元测试和自动化动态门槛。显示器点亮后的
实机探针稳定通过：两秒静止 Flutter 期间 Stage Present 120 帧，而 Flutter Present
增量为 0；750 ms platform-thread stall 期间 Stage 继续 Present 45 帧，Flutter
Present 增量仍为 0。由此已经证明下层 Visual 更新不重泵静止 Flutter，且 Flutter
platform thread 短暂卡顿不阻塞独立 Stage producer。

首次人工拖动窗口时观察到白闪。代码定位确认旧 resize 路径会先销毁整个 composition
surface，执行 `SetRoot(nullptr)` + `Commit()`，再创建新 DComp target/Visual tree，
其间会露出未合成 HWND。现已改成在同一 DComp 树内对 Stage/Flutter composition
swapchain 执行 `ResizeBuffers`，并把 Stage 恢复推迟到新尺寸 Flutter 帧 Present 之后。
修复后的自动探针已实际完成一次缩放和恢复：surface resize `+2`、Flutter Present
`+4`，恢复后 250 ms 内 Stage Present `+15`，composition tree commit 始终为 1。
用户随后连续拖动窗口复测，确认白闪已经消失，缩放后 Flutter 控件不会再被下层 Stage
吞没。根因修复还移除了 resize 路径对 ANGLE immediate context 的 `ClearState()`；该
调用会破坏 ANGLE 缓存的 Flutter 管线状态。v2 只清理独立 Stage D3D11 context。

100% DPI 下的透明孔、圆角、半透明遮罩、独立页面、有限动画、窗口缩放、焦点、
Unicode 输入和原生中文 IME 组合/候选/提交已经完成实机视觉检查；遮罩和独立页面显示
500 ms 时 Stage 分别继续 Present `+30` 和 `+31`，HWND、surface 尺寸和 DComp tree
均未改变。125% 和 150% 首次实测期间曾临时启用 Per-Monitor V2，分别通过 120/144 DPI
自动门槛；这些结果保留为历史技术证据。2026-09-30 按产品决定恢复原有
`dpiAwareness=false`：Flutter 与 DComp 使用 Windows 虚拟化的 96-DPI client space，
最终 HWND 由系统 bitmap scaling。当前构建、打包和运行时门槛均要求 manifest 为
`false`、awareness 为 `0`、window DPI 为 `96`，避免发布物意外回到 PMv2。自动探针仍会
在多显示器环境移动过去后再移回，逐段核对 DPI-unaware 契约、HWND、surface 尺寸、
DComp tree 和 Stage 推进；当前单显示器
样本明确记录为 `single_monitor` 跳过，不会冒充迁移成功。用户于 2026-09-28 明确决定
不再用当前 1080p 单屏模拟 175% 和 200%，而是在功能完成后用真实高分屏复测；混合 DPI
迁移也需要当前环境没有的第二台显示器。这些项目转入 Phase 7 实机兼容矩阵，明确保持
“未验证”，不冒充已通过，也不再阻塞 Phase 2 实现提交。此前屏幕关闭样本中的 compositor clock
`STATUS_GRAPHICS_PRESENT_OCCLUDED (0xC01E0006)` 仍保留为负向生命周期证据；探针按
设计失败并停止 Stage 线程，没有改用忙轮询、定时器或无限重试掩盖该状态。

本阶段没有接入或修改真实 Show 管线，也没有改变 external texture 回退路径。

## 已实现架构

显式设置 `KIRAKARA_COMPOSITOR_BACKEND=synthetic` 时，定制 Engine 为 Runner 的同一个
顶层 HWND 建立以下 DirectComposition 树：

```text
top-level HWND
└─ DComp root
   ├─ synthetic Stage visual
   │  └─ independent D3D11 composition swapchain
   └─ Flutter visual
      └─ premultiplied-alpha BGRA8 composition swapchain
```

- Stage 使用与 ANGLE 相同适配器、但独立的 D3D11 device/context 和生产线程。
- Stage 线程只等待 `DCompositionWaitForCompositorClock` 和停止事件，不调用 Flutter、
  Dart 或 Runner platform thread，不使用常驻 timer、Sleep pacing 或显式 `Flush`。
- Flutter 先渲染到同设备 BGRA8 EGL 中间纹理；仅在 Flutter 自己发生
  `SwapBuffers` 时，GPU `CopyResource` 到当前 DComp back buffer 并 Present。
- Stage 更新只 Present 下层 swapchain，不请求 Flutter frame，也不调用 external
  texture notification。
- 窗口 resize 保留同一个 DComp target/root/Visual tree，只原位 Resize 两条 swapchain；
  新尺寸 Flutter 帧 Present 后才恢复 Stage producer，避免空根和未定义上层缓冲被合成。
- 资源释放顺序为：停止并 join Stage 线程，解除 EGL surface，清空 Visual content/
  root 并 Commit，再逆序释放 swapchain、context、device 和事件句柄。
- 定制 Engine 且 backend 未设置时默认使用真实 `composed` 路径；官方/stock Engine
  没有版本化 export 时继续使用上游 Flutter surface 和现有 Stage external texture。
  显式 `stock` / `external_texture` 仍可强制 A/B 回退，`synthetic` 仅用于本页探针。

Runner 通过单一版本化导出 `FlutterDesktopKirakaraCompositorGetApi` 做握手。ABI、
patchset version/revision、Engine revision、结构大小或函数表不完全匹配时，启动会给出
明确错误，不会继续解引用不兼容接口。

## 已排除的错误路线

1. 直接把 flip-model composition swapchain 的每个 back buffer 包装成 EGL surface：
   当前 back buffer 可创建 RTV，非当前 back buffer 在本机返回 `E_INVALIDARG`，不能
   作为可靠多缓冲实现。
2. `Present(0)` 配合 frame-latency wait：composition swapchain 没有形成有效节流，
   实测进入约 16k fps 的忙循环。
3. Stage `Present(1)`：本机 60 Hz 桌面仅约 21.5 fps，不满足 60 Hz 技术验证。
4. `IDXGIOutput::WaitForVBlank`：当前虚拟/显示状态下立即返回，实测约 18k fps，不能
   当作事件驱动帧钟。

因此当前实现使用 Windows 的 DirectComposition compositor clock。屏幕关闭时返回
occluded 是明确的生命周期状态，恢复策略属于 Phase 4；Phase 2 自动探针要求启动时
显示器已经点亮且窗口可见。

## 自动门槛

`run_synthetic_compositor_probe.ps1` 验证并记录：

- 精确 Engine/patchset 元数据与 capability bits；
- 目标 HWND 的运行时 DPI awareness 必须为 `DPI_AWARENESS_UNAWARE (0)`，且窗口 DPI
  必须为虚拟化的 `96`，不能只靠源码 manifest 声明；
- 当前窗口的虚拟化 DPI、缩放百分比，以及进程可见的每台显示器边界、主屏标记、DPI
  和缩放百分比；每个样本都把报告值写进 JSON，避免仅靠文件名或人工记忆判断；
- 当前进程恰好一个可见顶层内容 HWND，且 Engine 诊断绑定到非零目标 HWND；不可见
  的 Windows IME 辅助窗口单独计数，不冒充 Stage/Flutter 内容窗口；
- 初始化 HRESULT、Stage Present HRESULT、compositor clock NTSTATUS；
- 两秒静止 UI 内 Stage Present/clock wake 持续增长；
- 同一窗口内静止 Flutter Present 增量不超过 3；
- test-only 的 750 ms platform-thread stall 期间 Stage 仍持续增长，Flutter Present
  增量不超过 1；
- Stage 速率有上界，防止 busy loop 被误判为“流畅”；
- test-only 的窗口缩小/恢复必须精确改变并还原 surface 尺寸，resize HRESULT 为成功；
- resize 前后顶层 HWND 不变、composition tree commit 计数保持为 1，Stage 随后继续推进；
- 自动打开/关闭半透明遮罩与不透明独立页面，验证 HWND、surface 尺寸和 DComp tree
  均不变化，并验证它们显示期间 Stage producer 继续推进；
- 如果存在多台显示器，自动移动过去再移回；两段都要求窗口保持 96 DPI、顶层 HWND 与
  DComp tree 不变、Stage 持续推进，最终尺寸精确恢复；
  单显示器环境必须在报告中明确记为 skipped；
- 等待交互相关的有限 Flutter 动画完全结束后，再采两秒静止样本，要求 Stage 继续推进
  且 Flutter Present 重新归零，防止页面/遮罩切换遗留持续帧泵；
- 无 device removal、无 occlusion。

test-only stall 仅在 `KIRAKARA_COMPOSITOR_TEST_MODE=1` 时开放，且单次时长限制为
1～2000 ms；产品路径没有这种阻塞。

## 2026-09-28 已验证

| 门槛 | 结果 |
|---|---|
| 定制源码等于锁定补丁树 | 通过，tree `245d4c2b9d94052be9c7be3c841ae85b177be4be` |
| 补丁 SHA-256 | 通过，`05CC626407306850C81591962DFF1466276FCFF9029BAF311781D873CF07FE89` |
| GN + Ninja 从锁文件重建 | 通过，`host_debug_kirakara_v2` |
| DLL 官方导出兼容性 | 通过，保留官方 102 个导出，仅增加锁定的 1 个 ABI 导出 |
| Kirakara ABI 单测 | 4 / 4，通过 |
| 关键调度单测 | 2 / 2，通过 |
| 上游 compositor/display/DPI/texture 单测 | 25 / 25，通过 |
| 两项低功耗 adapter 独立单测 | 1 / 1 + 1 / 1，通过 |
| 完整 Windows Engine 单测 | 358 / 358 已运行；仅复现 Phase 1 的两项 adapter 顺序依赖失败，独立重跑均通过 |
| Dart analyze | 通过，无诊断 |
| App 全量 analyze / test 基线 | 与 Phase 1 完全一致：68 条既有 info；全量测试仍仅有同两项 Bilibili 清晰度/登录文案失败，无 Phase 2 新增失败 |
| Stage/预览定向 Flutter 测试 | 7 / 7，通过（texture service、preview host、overlay state） |
| Git 产物边界 | 通过；Phase 2 未跟踪 Engine 源码树、构建缓存、DLL、PDB、LIB 或 EXE，产物仅留在忽略的构建/诊断目录 |
| stock → patched → stock 源码切换 | 通过；两种 tree 都经过精确校验 |
| 同一 Runner 使用官方 stock debug DLL 构建 | 通过；无 custom export 的默认路径仍可链接 |
| patched DLL、backend 未设置的上游 surface 启动/响应 | 通过；正常关闭仍复现 Phase 1 已记录的共同超时 |
| 单可见顶层内容 HWND | 通过；1 个可见内容窗口，另有 2 个不可见 Windows IME 辅助窗口 |
| 屏幕关闭时的失败识别 | 通过，准确记录 `0xC01E0006`，无 busy loop |
| 屏幕点亮后的动态/独立性门槛 | 通过；两次均为 Stage `+120 / 2 s`、`+45 / 750 ms`，Flutter 均 `+0` |
| 原位 resize 自动门槛 | 通过；resize `+2`、tree commit 保持 `1`、尺寸精确恢复、Stage 恢复推进；高 DPI 下先缩小再恢复，不依赖额外屏幕空间 |
| resize 人工复测 | 通过；用户确认白闪消失，缩放后 Flutter 控件保持可见，无整窗 Stage 穿透 |
| 透明孔、圆角与外围不透明 UI | 100% DPI 通过；桌面合成截图确认 Stage 仅从圆角孔显示 |
| 半透明遮罩 | 通过；截图像素随下层 Stage 变化，外围不透明像素保持不变；自动样本 Stage `+30 / 500 ms` |
| 独立页面 | 通过；页面完整遮盖 Stage，HWND 与 1600×900 外框不变；自动样本 Stage `+31 / 500 ms` |
| 有限动画 | 通过；动画结束后重跑门槛，Stage `+120 / 2 s`、Flutter `+0` |
| 焦点与基本输入 | 通过；输入框焦点、鼠标点击及 `KiraKara 测试 123` Unicode 输入可见 |
| 原生中文 IME | 通过；`ceshi` 组合串、候选窗和空格提交“测试”均正常 |
| DPI awareness（历史 Phase 2 样本） | 当时通过 Per-Monitor V2 门槛；125% 进程准确看到 `1920×1080 / 120 DPI`。2026-09-30 按产品决定恢复 `dpiAwareness=false`，这些样本只保留为旧实现证据，不再代表当前契约 |
| 最终 EXE manifest 门槛 | 当前要求资源 `#1` 中 `dpiAwareness` 精确为 `false`；构建与打包脚本均拒绝其他值 |
| 当前 DPI-unaware 自动门槛 | 2026-09-30 通过；运行时 awareness `0`、window DPI `96`、scale `100%`；Stage `+120 / 2 s`、Flutter `+1`，交互后静止样本 Stage `+120 / 2 s`、Flutter `+0` |
| DPI 矩阵 | PMv2 历史配置下 100%、125%、150% 已测；当前 DPI-unaware 配置的 96-DPI 自动契约已通过，系统 bitmap scaling 与 175%～200% 真正高分屏仍保留为人工兼容项 |
| 跨显示器自动迁移路径 | 单屏分支通过；报告明确为 `single_monitor` skipped，实际多屏迁移分支待不同 DPI 实机验证 |
| DPI 防误报门槛 | 当前要求 `-ExpectedScalePercent 100`、awareness `0` 和 window DPI `96`；`-RequireMixedDpi` 只在系统向 DPI-unaware 进程暴露不同 monitor scale 时可用，否则明确失败 |

对应的忽略目录报告：

- `build/diagnostics/engine/patched-engine-20260928-064955.json`
- `build/diagnostics/engine/patched-engine-tests-20260928-064302.json`
- `build/diagnostics/engine/patched-engine-tests-20260928-065108.json`（完整套件及独立对照）
- `build/diagnostics/engine/verified-phase2-final.json`（提交前锁定 revision、源码树、GN、工具链、导出和产物哈希复核，通过）
- `build/diagnostics/engine/patched-engine-tests-phase2-final.json`（提交前 4 + 2 + 25 + 1 + 1 项定向复核，全部通过）
- `build/diagnostics/engine/app-smoke-local-patched-debug-20260928-064830.json`
- `build/diagnostics/synthetic-compositor-20260928-070346.json`（屏幕关闭，预期失败）
- `build/diagnostics/synthetic-compositor-20260928-121119.json`（显示器点亮，用户实机通过）
- `build/diagnostics/synthetic-compositor-20260928-122438.json`（保持窗口打开的复核，通过）
- `build/diagnostics/engine/verified-resize-fix-v2-target.json`（v2 产物与锁文件严格一致）
- `build/diagnostics/engine/patched-engine-tests-resize-fix-v2-target.json`（v2 回归）
- `build/diagnostics/engine/verified-phase2-monitor-move-v2.json`（加入迁移门槛后的 v2 产物与锁文件复核）
- `build/diagnostics/engine/patched-engine-tests-phase2-monitor-move-v2.json`（加入迁移门槛后的 33 项定向回归）
- `build/diagnostics/synthetic-compositor-20260928-130344.json`（v2 原位 resize，通过）
- `build/diagnostics/synthetic-compositor-v2-overlay-page-gates.json`（遮罩与页面自动门槛，通过）
- `build/diagnostics/synthetic-compositor-v2-dpi-aware.json`（记录 `96 DPI / 100% / 1` 个显示器，通过）
- `build/diagnostics/synthetic-compositor-v2-phase2-final-100.json`（最终 100% 自动门槛；交互后 Stage `+120 / 2 s`、Flutter `+0`）
- `build/diagnostics/synthetic-compositor-v2-expected-scale-negative.json`（预期 125%、实测 100%，按设计拒绝）
- `build/diagnostics/synthetic-compositor-v2-mixed-dpi-negative.json`（只有 100% 单 DPI，按设计拒绝 mixed-DPI 声明）
- `build/diagnostics/synthetic-compositor-v2-monitor-move-single.json`（最新自动门槛；单显示器迁移分支明确 skipped，其余门槛通过）
- `build/diagnostics/synthetic-compositor-v2-monitor-move-mixed-negative.json`（最新迁移门槛在单屏环境按设计拒绝 mixed-DPI 声明）
- `build/diagnostics/synthetic-compositor-v2-phase2-ready-100.json`（当前保持打开的 100% 最终样本；Stage `+120 / 2 s`，交互后 Flutter `+0`）
- `build/diagnostics/synthetic-compositor-v2-phase2-125.json`（DPI-unaware 负向证据；系统已切 125%，进程仍被虚拟为 96 DPI，resize 门槛失败）
- `build/diagnostics/synthetic-compositor-v2-phase2-125-pmv2.json`（恢复 Per-Monitor V2 后准确报告 120 DPI；放大窗口触及最大跟踪尺寸，resize 门槛按设计未放宽）
- `build/diagnostics/synthetic-compositor-v2-phase2-125-pmv2-contract.json`（125% 先缩小再恢复的完整自动门槛，通过）
- `build/diagnostics/synthetic-compositor-v2-phase2-125-pmv2-physical-size.json`（125% 保持约 1600×900 物理启动占用，完整自动门槛通过）
- `build/diagnostics/synthetic-compositor-v2-phase2-125-visual.json`（125% 保持打开的人工复核窗口，自动门槛通过）
- `build/diagnostics/synthetic-compositor-v2-pmv2-runtime-gate-100.json`（100% 下新增运行时 HWND PMv2 防回归门槛，通过）
- `build/diagnostics/synthetic-compositor-v2-phase2-150-pmv2.json`（150% / 144 DPI 完整自动门槛，通过）
- `build/diagnostics/synthetic-compositor-v2-phase2-150-visual.json`（150% 保持打开的人工复核窗口，自动门槛通过）
- `build/diagnostics/synthetic-compositor-dpi-unaware-20260930.json`（当前 `dpiAwareness=false` 自动门槛，通过）
- `build/diagnostics/phase2-v2-alpha-overlay-topmost-a.png`（半透明遮罩视觉证据）
- `build/diagnostics/phase2-v2-input-unicode-sendinput.png`（焦点与 Unicode 输入证据）
- `build/diagnostics/phase2-v2-ime-composition.png`（中文 IME 组合串和候选窗证据）
- `build/diagnostics/phase2-v2-ime-committed.png`（中文 IME 提交结果证据）
- `build/diagnostics/phase2-v2-alternate-page.png`（不透明独立页面视觉证据）

## 人工视觉与交互复测

自动门槛已经通过。需要重新采样时，当前 Debug bundle 已是最新锁定的 custom Engine，
因此可跳过构建：

```powershell
Set-Location 'D:\Kirakara-App-ascii'
.\tool\windows_compositor\run_synthetic_compositor_probe.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -LocalEngine host_debug_kirakara_v4 `
  -TimeoutSeconds 45 `
  -SkipBuild
```

自动报告必须 `passed: true`。随后保持窗口打开做人工检查：

`-SkipBuild` 不再只核对 custom Engine DLL。首次不带该参数构建 synthetic 入口时，脚本会
在忽略的 Debug bundle 内写入目标与 EXE、Engine DLL、ICU、`kernel_blob.bin` 的身份指纹；
缺失、损坏或被普通 `lib/main.dart` Debug 构建覆盖的 bundle 会在创建进程前明确拒绝，
避免把 Kirakara 主程序误当作 synthetic probe。

2026-09-29 实测覆盖了四条路径：缺失 stamp 被拒绝；正确 synthetic bundle 复用并通过；
随后普通 `lib/main.dart` 构建被按 `kernel_blob.bin` 不匹配拒绝；可解析但缺字段的 stamp 被按
`schemaVersion` 不匹配拒绝。三条负向路径的 Kirakara 进程集合均未增加，恢复正确 stamp
后的 `-SkipBuild` 再次通过。

```powershell
.\tool\windows_compositor\run_synthetic_compositor_probe.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -LocalEngine host_debug_kirakara_v4 `
  -SkipBuild `
  -KeepOpen
```

当前产品恢复 DPI-unaware 模式，自动门槛只应使用
`-ExpectedScalePercent 100`，核对进程始终看到虚拟化后的 96 DPI：

```powershell
.\tool\windows_compositor\run_synthetic_compositor_probe.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -LocalEngine host_debug_kirakara_v4 `
  -ExpectedScalePercent 100 `
  -SkipBuild
```

跨显示器时，探针仍会移动同一个 HWND 后移回，并要求窗口 DPI 全程保持虚拟化的 96、
HWND 与 DComp tree 不变且 Stage 继续推进。`-RequireMixedDpi` 仅用于诊断：如果 Windows
没有向 DPI-unaware 进程暴露不同的显示器缩放值，它会明确失败，不能代替真实高分屏上的
人工 bitmap-scaling 检查。

检查并记录：

1. Stage 动画只出现在中央圆角透明孔；孔外背景、页头、两侧和页脚不漏底。
2. “覆盖 Stage”半透明面板始终位于动画上方，开关时 HWND 和窗口尺寸不变。
3. “切换页面”完整遮住 Stage；返回后透明孔恢复，期间 HWND 和窗口尺寸不变。
4. “有限动画”结束后静止，重新测量仍满足 Flutter Present 静止门槛。
5. 输入框可获得/切换焦点，中文 IME、键盘和鼠标输入正常。
6. 连续调整窗口大小，确认不再闪白，也不出现整窗 Stage 穿透；透明孔、边框和 Stage
   不错位、不残留旧尺寸画面。
7. PMv2 历史配置已在 100%、125%、150% 检查；当前 DPI-unaware 配置需在真正高分屏
   上重新观察 bitmap scaling。连接不同 DPI 的第二台显示器后，跨显示器移动并重复
   缩放、遮罩和输入测试。

Phase 2 的双 Visual、Alpha、覆盖关系与独立帧泵结论不受 DPI 策略切换影响。当前
DPI-unaware 自动门槛已于 2026-09-30 重新通过；175%、200% 真正高分屏上的 bitmap scaling
和混合 DPI 视觉质量仍需实机复核，在完成前只能标为“未验证”。
