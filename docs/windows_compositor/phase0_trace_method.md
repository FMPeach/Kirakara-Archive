# Phase 0：Show → Flutter → Present Trace 方法

## 事件链

同一进程、同一 QPC 时钟中记录以下事件：

```text
Kirakara.Show.NativeStage
  StagePublish
  -> PreviewPublication
  -> PreviewCallback
Kirakara.App.StageTexture
  -> TextureCallback
  -> FrameAvailable
  -> TextureAcquire
  -> FlutterFramePresented
Windows GPU / DXGI / DWM
  -> Present start/stop
  -> displayed
```

Show provider GUID 为 `9b2572f2-7f04-4059-9e9c-fcbafbf5b0de`；App provider
GUID 为 `6862b681-4cdb-45e5-936c-05d82d83ef9a`。Show 事件正文和 App 事件字段
都包含 QPC、generation、frame ID 与线程 ID。ETW provider 未启用时不逐帧格式化、
不写文件，也不输出控制台。

`StagePublish` 是 UnifiedStageRenderer 成功发布不可变 StageFrame 后的边界；
`PreviewPublication` 是 consumer publication texture 的 GPU copy/flush 已提交后；
`PreviewCallback` 与 `TextureCallback` 分别位于 Show 调用前和 Runner 回调入口；
`TextureAcquire` 的 `Advanced=true` 表示 Flutter 本次取得了新的 latest frame，
`false` 表示重复取得上一个 descriptor。

显式设置 `KIRAKARA_COMPOSITOR_DIAGNOSTICS=1` 时，Runner 还会用 stock embedder 的
一次性 next-frame callback 记录 `FlutterFramePresented`。Flutter 3.44.4 源码中的
该回调位于成功 `SwapBuffers` 之后，但随后会投递回 platform thread，所以它适合做
“发生了多少次 Flutter present”的计数和顺序证据，不是精确的 SwapBuffers 或 DWM
displayed 时间戳。回调只由已发生的 Flutter frame 唤醒；它不请求新帧、不轮询，也
不启动定时器。基线脚本只在自己的子进程范围内临时设置该环境变量并在结束后恢复。

## 捕获

1. 在普通 PowerShell 中临时启用诊断计数并启动 profile App。只让新 App 进程继承
   环境变量，随后立即恢复当前 shell：

   ```powershell
   Set-Location 'D:\Kirakara-App-ascii'
   $env:KIRAKARA_COMPOSITOR_DIAGNOSTICS = '1'
   Start-Process `
     '.\build\windows\x64\runner\Profile\kirakara_app.exe'
   Remove-Item Env:KIRAKARA_COMPOSITOR_DIAGNOSTICS
   ```

   使用 debug 或 profile App 构建，先打开待测页面并准备好固定 fixture。本次已
   生成的 profile 入口为
   `D:\Kirakara-App-ascii\build\windows\x64\runner\Profile\kirakara_app.exe`；
   它是本机构建产物，不进入 Git，也不能当作另一台机器的可复现发布包。
2. 另开一个明确选择“以管理员身份运行”的 PowerShell。切换目录不会提升已有
   shell。先执行下式，结果必须为 `True`：

   ```powershell
   $principal = [Security.Principal.WindowsPrincipal] `
     [Security.Principal.WindowsIdentity]::GetCurrent()
   $principal.IsInRole(
     [Security.Principal.WindowsBuiltInRole]::Administrator
   )
   ```

3. 在这个已提升窗口中启动一次有上限的捕获：

   ```powershell
   Set-Location 'D:\Kirakara-App-ascii'
   .\tool\windows_compositor\capture_compositor_trace.ps1 `
     -DurationSeconds 20 `
     -OutputPath '.\build\diagnostics\static-ui-1080p60.etl'
   ```

   脚本会在启动 WPR 前确认至少有一个 `kirakara_app.exe` 正在运行，并打印目标
   PID；缺少 App 时直接失败，避免生成只有系统事件、无法关联 Stage frame 的无效
   基线。相对 `OutputPath` 按当前 PowerShell 目录解析，不按 PowerShell 宿主进程最初
   的工作目录解析。若目标文件已经存在，脚本会拒绝覆盖。

   本机 WPR 10.0.22621 在结果路径经过 `D:\Kirakara-App-ascii` Junction 时会在
   `wpr -stop` 返回 `0xc5600600`。脚本因此让 WPR 先完成到系统临时目录，再把完整的
   ETL 移到 `OutputPath`；不会改变采集内容。若最终搬运失败，脚本会明确报告并保留
   临时 ETL，而不是删除唯一的有效样本。

   WPR 要求从“以管理员身份运行”的 PowerShell 启动。非提升权限会返回
   `0xc5585011` 或 `0x80070005`；不要把它解释为应用或 provider 失败。

4. 只执行一个场景，记录开始/结束动作；脚本到时自动停止，不留下后台 session。
5. 分别采集：静止 UI、1080p60、打开/关闭面板、全屏预览、物理双屏、Cast。
6. 发生捕获错误时脚本只取消自己已成功启动的 WPR session。

若管理员检查为 `True` 但仍得到 `0xc5585011`，不要修改本地安全策略；先运行
`whoami /priv | Select-String SeSystemProfilePrivilege` 并保留输出，以区分令牌权限和
机器策略问题。

WPR profile 同时启用 `GPU.Light`、`DesktopComposition.Light` 和两个 Kirakara
provider。若机器已有其他 WPR session，先保留现场并另行安排采集，不要直接
`wpr -cancel` 清理未知 session。

## WPA 分析

1. 在 WPA 打开 ETL，将 Generic Events、Present、DWM Frame Details、GPU Usage
   与 CPU Usage 表加入同一时间轴。
2. Generic Events 按 Process=`kirakara_app.exe` 和上述两个 provider GUID 过滤。
3. 按 `(generation, frame_id)` 关联七个 Kirakara 事件。
4. 先按 PID 找 DXGKRNL `Present/win:Info`，再以非零 HWND、context 和事件顺序
   锁定 Flutter 主窗口 Present。以 QPC 和单调事件顺序，把每次
   `TextureAcquire` 配给 5 ms 内最近的后续主窗 Present；`Advanced=true` 表示该
   Present 取得新源帧，`false` 表示重复取 latest descriptor。没有纹理 acquire 的
   主窗 Present 单独保留，不能猜成新源帧。不要把每次 Present 直接分配给“当时
   最新的 StagePublish”：stock `FlutterFramePresented` callback 会异步投递到
   platform thread，执行时读取的 current frame ID 可能已被后续 acquire 更新，因而
   callback 只用于计数和延迟诊断，不作为 source/present 归属权威。同一进程还存在
   `hWindow=0` 的 Show/ANGLE 图形事件。
5. 分别计算：

   - `StagePublish -> PreviewPublication`；
   - `PreviewPublication -> TextureCallback`；
   - `TextureCallback -> TextureAcquire`；
   - `TextureAcquire -> FlutterFramePresented`（带 platform-thread 投递延迟）；
   - `TextureAcquire -> DXGI Present`；
   - `Present -> DWM displayed`；
   - callback 数、advanced acquire 数、Flutter present 数与重复 acquire 数；
   - 源帧 disposition：未 acquire、已 present 后 DWM drop、最终 displayed；
   - 窗口 present disposition：无新 Stage acquire、DWM drop、displayed。

两条独立 60 Hz 时钟可能让一次 Flutter acquire 合并多个 frame notification，也可能
在没有新 Stage frame 时重复 present 上一帧。因此不能只比总帧数；必须分别看源
frame ID、窗口 Present ID、相邻间隔以及 P50/P95/P99/max。stock next-frame callback
可以证明成功 SwapBuffers 后的 present 次数；精确 swapchain 时间和 DWM displayed
仍必须由 Present/DWM 事件证明，不能用“画面看起来流畅”替代。

## 自动离线分析

仓库内的分析器只保存 PowerShell/C# 源码，不保存 PresentMon、ETL、CSV 或其他
二进制。采集仍可使用 Windows PowerShell；离线分析因为调用 WPT TraceProcessing
程序集，要求 PowerShell 7 或更高版本。完整 displayed 关联还要求调用者显式提供
PresentMon 单文件程序路径：

```powershell
Set-Location 'D:\Kirakara-App-ascii'
pwsh .\tool\windows_compositor\analyze_compositor_trace.ps1 `
  -InputPath '.\build\diagnostics\static-ui-1080p60.etl' `
  -ProcessId 58692 `
  -PresentMonPath `
    "$env:LOCALAPPDATA\Temp\kirakara-presentmon-v2.6.0\PresentMon-2.6.0-x64.exe" `
  -ReportPath `
    '.\build\diagnostics\static-ui-1080p60-a4618395-analysis.json' `
  -Scenario 'static-ui-with-1080p60-stage' `
  -RefreshRateHz 180
```

PID 使用采集脚本开始时打印的值；`RefreshRateHz` 只为本次报告生成 refresh-period
分桶，不会被 App 读取或持久化。分析器会：

1. 用 Show 的 QPC/frame ID 解析三段 producer/callback 边界；
2. 用 App TraceLogging 解析 texture callback、acquire 与 stock presented callback；
3. 从 DXGKRNL 找主窗口非零 HWND Present，以 raster `TextureAcquire` 向后做有界
   单调配对，再区分取得新 Stage frame、重复 acquire 和未调用纹理 acquire 的
   Present；异步 stock presented callback 另行配对，只做诊断；
4. 让 PresentMon 以 raw QPC 离线重放 ETL，再关联 displayed/dropped；
5. 分别输出全窗口和裁掉首尾各 1 秒后的 P50/P95/P99/max；源帧和窗口 Present
   各自拥有 displayed cadence 与刷新周期分布，避免重复 Present 掩盖被合并的源帧。

报告 schema version 2 将源帧和窗口 Present 的结果分开：
`sourceFrameDisposition.steadyNotAcquiredFrameIds` 给出稳定区间在 acquire 前被 latest
frame 取代的源帧；`counts.steadyPresented/steadyDropped` 按唯一源帧统计；
`counts.steadyWindowPresentDisplayed/steadyWindowPresentDropped` 按实际窗口 Present
统计。`displayCadence.sourceFrameRefreshPeriodHistogram` 与
`windowPresentRefreshPeriodHistogram` 也必须分别解读，不能相加或互相替代。
`textureAcquirePairing` 会保留配对时延、未匹配 acquire 及没有纹理 acquire 的主窗
Present，WPR 启动造成的长延迟不会被异步 callback 悄悄重标成精确 source 归属。

脚本拒绝覆盖已有报告。报告默认应放在被忽略的 `build/diagnostics`；ETL、报告、
PresentMon CSV 和工具二进制都不得提交普通 Git。PresentMon 会在 ETL 开头建立内部
状态，可能不报告最初几帧；报告会保留 DXGKRNL 与 PresentMon 的未匹配数量和 frame
ID，不能悄悄把 warm-up 缺口算成 displayed。

本机基线使用 PresentMon 2.6.0 x64，SHA-256 为
`B2A706BC6AD475749E3B7E3409263AA1E6906D45BDCF993F6DBC0F660188F1AF`，Authenticode
签名为 Intel Corporation / Valid。换版本重分析时必须在报告中保留新版本、校验值
和签名状态，不能把不同分析器版本的数值无说明地混为同一基线。

## PresentMon

PresentMon 不需要安装为服务；本机使用官方签名的单文件程序离线读取现有 ETL。
分析器固定传入 `--etl_file`、`--process_id`、`--qpc_time` 与 `--v1_metrics`，raw QPC
用于和 Kirakara/DXGKRNL 事件共钟关联。ETL 始终是 frame ID、provider 和原始事件的
权威来源，PresentMon 负责采用其完整 DXGKRNL/Win32k/DWM 状态机判断 displayed 与
dropped；不能只拿 CSV 的进程总行数冒充主窗口帧数。
