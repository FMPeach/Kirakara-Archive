# Windows 定制合成器 Phase 0 基线

采集日期：2026-09-27（Asia/Shanghai）

## 锁定源码与工具链

| 项目 | 已验证值 |
| --- | --- |
| App 基线 | `5cbc7bf61ca0ae336b417d54094f919806c6f719`，原分支 `Unified-stage-dev`，采集前工作区干净且与 `origin/Unified-stage-dev` 为 `0/0` |
| Show 基线 | `f1c9a3162ddab8c264e03c4ee2f4813ef213f58c`，原分支 `Unified-stage-dev`，采集前工作区干净且与远端为 `0/0` |
| Flutter | 3.44.4 stable，Framework `ad70ec4617166f1c38e5d2bfd388af71fda14f06` |
| Engine | `a10d8ac38de835021c8d2f920dbf50a920ccc030`，content hash `700aebeca4c0e610f109a3979ee3e71b69d666bc` |
| Dart / DevTools | 3.12.2 / 2.57.0 |
| Windows | Windows 11 专业版 23H2，`10.0.22631.6199`，x64 |
| Visual Studio | Community 2026 18.6.11806.211 |
| Windows SDK | 10.0.26100.0 |
| WPR / WPA | WPR 10.0.22621.5624 / WPA 11.7.395.0 |

官方 Flutter Engine DLL 的 SHA-256：

| 模式 | 字节数 | SHA-256 |
| --- | ---: | --- |
| debug | 45,550,592 | `9A9B638AC057DB6FCBF33C4B75B4D36FD99077E77E8AEE71D2E3020741492425` |
| profile | 21,868,032 | `A9EF249453BC960B06FBCAC4A9D2BDA9AA57260EC9D75C2BADED6AE6ED42F384` |
| release | 21,284,864 | `61B77BC881F5C57AF5F3EEAC4A96FFD9FD87E35B77565F44C678DE105C92C2ED` |

仓库中历史遗留的 `windows/runner/libshow_host.dll` 为 4,298,970 字节，SHA-256
`E85562225F79F27E1C0688012395814CB811E965D610E78760B6B1753CFDEF09`。
当前 CMake 构建实际从 Show 的 `build/bin/libshow_host.dll` 复制 DLL；本阶段没有改动
或重新提交仓库内的 DLL。

## 本机图形基线

- NVIDIA GeForce RTX 4060 Ti，驱动 `32.0.15.9186`，当前 1920×1080 @ 180 Hz。
- Intel UHD Graphics 770，驱动 `32.0.101.7088`。
- 另有 GameViewer、Oray 和 Virtual Display 虚拟显示适配器；当前采集环境不是
  Iris Xe 1130G7，也不是 60 Hz 实体显示器。
- 本记录只用于这次基线对照。应用运行时不得把 GPU、驱动或能力探测结果写入配置。

## 改动前验证结果

### App

- `flutter build windows --debug`：通过，运行产物为
  `build/windows/x64/runner/Debug/kirakara_app.exe`。
- `flutter build windows --profile`：通过；JNI 插件有既存的 C4022/C4047 警告。
- `flutter build windows --release`：通过。
- 聚焦测试 `stage_texture_service_test.dart` 与 `stage_preview_host_test.dart`：3 项通过。
- Windows 实机 integration baseline：external texture 使用真实 Show fixture 完成
  attach，挂载 Flutter `Texture` 并持续播放到 250 ms；该测试不把“成功挂载且无
  Flutter 异常”夸大为像素级画面校验。
- stock Clipboard API 的 Unicode/CRLF round-trip 已在独立轨道通过，详见
  [Windows 剪贴板 Phase 0 基线](../windows_clipboard/phase0_baseline.md)。
- 全量 `flutter test`：失败集合仍只有 2 项既存失败：
  `bilibili_resolver_test.dart` 仍期望已删除的 240P 质量；
  `widget_test.dart` 仍期望旧的“登录哔哩哔哩”文案。
- `flutter analyze`：既存 68 条 info，无 error/warning；主要是 collection 类型、
  const 建议和 `tool/` 下调试脚本 lint。

### Show

- 现有 37 项 CTest 全部通过，耗时 20.64 秒。
- 使用真实 fixture 执行 20 秒 `--texture-only --stage-diagnostics` soak：
  `59.9771 fps`，最差 5 秒窗口 `59.898 fps`，`dropped=0`；publish gap
  `15.1138–18.0799 ms`，大于 20/25/33 ms 的 gap 均为 0。
- 同一次 soak 中 preview copy 的典型 P95 不超过 0.02 ms，preview flush 的典型
  P95 不超过 0.075 ms，callback 的典型 P95 不超过 0.01 ms。
- 这些结果证明本机当前 Show producer 吞吐稳定，但不能代替 Flutter/DWM 端到端
  cadence 结论。

## Trace 接入后的回归

- App 的 debug/profile/release 构建均通过；真实 Stage texture integration test
  通过；三个 Stage 聚焦测试文件共 7 项通过。三种 App 产物携带的
  `libshow_host.dll` 均与本地 Show 构建一致，SHA-256 为
  `88BAD2D476B38A714E4A460467E954152EBFCF53B80C00F7BC12C1B7839118E3`；DLL
  仅存在于被忽略的构建目录，没有进入 Git。
- Show 全量构建与 37 项 CTest 通过，CTest 耗时 20.61 秒。
- 再次执行 20 秒 texture-only soak：`59.9412 fps`，最差 5 秒窗口
  `59.7953 fps`，`dropped=0`；大于 20/25/33 ms 的 publish gap 为 `2/1/0`。
  provider 未启用时所有逐帧事件在字段格式化前返回。本次单次回归证明功能路径
  未退化，不把两次短样本之间的抖动解释为统计性能结论。
- `flutter analyze` 仍只有相同的 68 条既存 info；全量 `flutter test` 仍只有上述
  两个既存失败。

显式诊断模式还通过 stock embedder 的一次性 next-frame callback 计数成功
`SwapBuffers` 后的 Flutter frame。真实 Stage 活跃的 1 秒窗口内，本机记录到：

| 事件 | 增量 |
| --- | ---: |
| Show texture callback | 60 |
| advanced Flutter texture acquire | 60 |
| Flutter frame presented callback | 60 / 61 |
| present 前出现新 acquire | 60 |

表中的 present 为两次连续诊断运行；第二次多出的 1 帧没有新 Stage acquire。
两次运行随后都关闭 Stage texture source，跳过 250 ms 排空窗口后再观察 750 ms，
texture callback 与 Flutter present 增量均为 0。这证明当前 external texture 后端
确实把 Stage 的 60 Hz 帧泵传递成 Flutter 整窗 present，而不是仅凭画面观感推断。
由于 stock callback 在 `SwapBuffers` 后还要投递到 platform thread，这组计数不能
代替 GPU/DXGI/DWM ETL 的精确 present/displayed 时间戳。

自动门禁要求 1 秒内至少 45 个 callback，callback、advanced acquire 和带新 acquire
的 present 三者差值不超过 2，总 present 最多额外 3 帧；停用后的窗口允许最多 1 个
尾部 callback 和 2 个尾部 present。该门禁只在基线脚本临时设置诊断环境变量时启用，
普通 App 路径不会持续注册 next-frame callback。

2026-09-27 的管理员 WPR 冒烟捕获已成功生成 21.1197568 秒 ETL，记录 0 lost
buffer、0 lost event；文件大小为 356,515,840 字节，SHA-256 为
`3DDECD9DC6C99DA191AF806D5FC3495A4016017F4DE5C667FB0A2A0B3B84BE5D`。但进程
rundown 证明捕获窗口内没有 `kirakara_app.exe`，两个 Kirakara provider 因而都没有
事件；该文件只验证 WPR 权限和 profile，不计入 compositor 基线，也不提交 Git。
采集脚本现会在 WPR 启动前检查目标 App，并按 PowerShell 当前目录解析相对输出路径，
避免再次生成同类无效样本。

## 可重复命令

采集机器、源码、Flutter 与官方 Engine 校验值：

```powershell
.\tool\windows_compositor\capture_baseline.ps1 `
  -ShowRepository 'D:\仓库\Kirakara Show' `
  -OutputPath '.\build\diagnostics\phase0-baseline.json'
```

执行真实 external texture 与标准剪贴板基线：

```powershell
.\tool\windows_compositor\run_windows_stage_texture_baseline.ps1 `
  -ShowRepository 'D:\仓库\Kirakara Show'
```

ETW/WPR 采集与分析见 [phase0_trace_method.md](phase0_trace_method.md)。

## 尚需实体机验证

- 在已启用诊断计数并加载固定 1080p60 preview 的 App 上重新执行管理员
  GPU + DesktopComposition WPR。管理员采集链路已通过，但尚无同时包含
  `kirakara_app.exe` 和两个 Kirakara provider 的有效 ETL，因此仍没有
  `TextureAcquire -> Present -> displayed` 实测结论。
- 1130G7 Iris Xe、真实 60 Hz 输出与热稳定状态。
- 物理双屏及 Cast 同时启用时的完整 WPR/PresentMon 样本。
- 100%～200% 混合 DPI、跨显示器、最小化/恢复和显示器热插拔。
- 剪贴板人工交互覆盖在独立轨道中维护，不与合成器改动混合。

在这些样本完成前，不把本机的 180 Hz/虚拟显示结果外推为目标实体机结论。
