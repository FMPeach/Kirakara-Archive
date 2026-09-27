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

1. 使用 debug 或 profile App 构建，先打开待测页面并准备好固定 fixture。本次已
   生成的 profile 入口为
   `D:\Kirakara-App-ascii\build\windows\x64\runner\Profile\kirakara_app.exe`；
   它是本机构建产物，不进入 Git，也不能当作另一台机器的可复现发布包。
2. 启动一次有上限的捕获：

   ```powershell
   .\tool\windows_compositor\capture_compositor_trace.ps1 `
     -DurationSeconds 20 `
     -OutputPath '.\build\diagnostics\static-ui-1080p60.etl'
   ```

   WPR 要求从“以管理员身份运行”的 PowerShell 启动。非提升权限会返回
   `0xc5585011` 或 `0x80070005`；不要把它解释为应用或 provider 失败。

3. 只执行一个场景，记录开始/结束动作；脚本到时自动停止，不留下后台 session。
4. 分别采集：静止 UI、1080p60、打开/关闭面板、全屏预览、物理双屏、Cast。
5. 发生捕获错误时脚本只取消自己已成功启动的 WPR session。

WPR profile 同时启用 `GPU.Light`、`DesktopComposition.Light` 和两个 Kirakara
provider。若机器已有其他 WPR session，先保留现场并另行安排采集，不要直接
`wpr -cancel` 清理未知 session。

## WPA 分析

1. 在 WPA 打开 ETL，将 Generic Events、Present、DWM Frame Details、GPU Usage
   与 CPU Usage 表加入同一时间轴。
2. Generic Events 按 Process=`kirakara_app.exe` 和上述两个 provider GUID 过滤。
3. 按 `(generation, frame_id)` 关联七个 Kirakara 事件。
4. 将同一进程在 `TextureAcquire` 后的第一个 DXGI Present 作为候选 Flutter
   Present，再用 swapchain/HWND 与 DWM displayed 事件排除其他 present。
5. 分别计算：

   - `StagePublish -> PreviewPublication`；
   - `PreviewPublication -> TextureCallback`；
   - `TextureCallback -> TextureAcquire`；
   - `TextureAcquire -> FlutterFramePresented`（带 platform-thread 投递延迟）；
   - `TextureAcquire -> DXGI Present`；
   - `Present -> DWM displayed`；
   - callback 数、advanced acquire 数、Flutter present 数与重复 acquire 数。

两条独立 60 Hz 时钟可能让一个 Flutter present 合并多个 frame notification。
因此不能只比总帧数；必须看 frame ID、相邻间隔以及 P50/P95/P99/max。stock
next-frame callback 可以证明成功 SwapBuffers 后的 present 次数；精确 swapchain 时间和
DWM displayed 仍必须由 Present/DWM 事件证明，不能用“画面看起来流畅”替代。

## PresentMon

本机 Phase 0 没有安装 PresentMon，因此已验证路径是 WPR/WPA。若测试机已有
PresentMon，先用该版本的 `--help` 确认参数，再按进程名 `kirakara_app.exe` 做同一
时长的 CSV 捕获；不要在脚本中假定某一版 CLI。PresentMon CSV 与 ETL 应共享场景
起止时间，且 ETL 仍作为 Kirakara frame ID 关联的权威来源。
