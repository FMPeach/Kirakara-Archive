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

- 以管理员权限执行 GPU + DesktopComposition WPR。当前非提升权限进程已验证 profile
  能解析到 `GPU.Light.File, DesktopComposition.Light.File,
  KirakaraCompositor.Verbose.File`，随后被系统性能策略以 `0xc5585011` 拒绝；未产生
  可分析 ETL，因此尚无 `TextureAcquire -> Present -> displayed` 实测结论。
- 1130G7 Iris Xe、真实 60 Hz 输出与热稳定状态。
- 物理双屏及 Cast 同时启用时的完整 WPR/PresentMon 样本。
- 100%～200% 混合 DPI、跨显示器、最小化/恢复和显示器热插拔。
- 剪贴板人工交互覆盖在独立轨道中维护，不与合成器改动混合。

在这些样本完成前，不把本机的 180 Hz/虚拟显示结果外推为目标实体机结论。
