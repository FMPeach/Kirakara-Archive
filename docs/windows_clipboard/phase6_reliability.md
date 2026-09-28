# Windows 剪贴板 Phase 6 可靠性与交互

验证日期：2026-09-28（Asia/Shanghai）

## 结论

剪贴板补丁作为合成器补丁之后的第二个独立 Engine patch 维护；Flutter 公共
`Clipboard` API、`SystemChannels.platform` 协议以及文本编辑控件的默认快捷键和
菜单均未改变。当前 Windows 11 / RTX 4060 Ti 实机已经证明：

- 外部进程连续占有剪贴板约 120 ms 时，一次标准 `Clipboard.getData` 会异步等待并
  成功返回，不会阻塞 platform thread；
- Unicode、CRLF、Ctrl+C、Ctrl+X、Ctrl+V、Shift+Insert、右键 Paste 和粘贴后的
  输入焦点均通过 Windows integration test；
- 官方 Flutter Engine 仍通过同一套标准剪贴板测试；只在定制 Engine 的用例中启用
  临时占用门槛；
- Bilibili 外链页增加了 `116×70` 的显式粘贴按钮，只对该字段提取受支持的完整
  Bilibili URL、`BV` 或 `AV` 号；粘贴后焦点和光标保持可继续输入；
- 实现没有剪贴板监听、启动读取、轮询、历史、持久化、上传或内容日志。

Phase 6 的当前硬件自动退出条件已满足。真实触摸屏、第三方富文本程序、远程桌面和
其他 Windows/GPU 组合仍属于 Phase 7 实机兼容矩阵，不从自动测试外推。

## Engine 补丁边界

`engine/patches/0002-windows-clipboard-contention.patch` 只修改 Windows
`PlatformHandler` 及其单元测试，位于 DirectComposition patch 之后，可以单独审查和
回滚。锁文件记录了补丁 SHA-256、应用完整补丁栈后的源码 tree、v4 GN 参数和 DLL/
LIB/PDB/ICU 校验值；二进制与符号仍只存在外部 Engine 工作区。

一次操作首次 `OpenClipboard` 成功时完全沿用上游读取/写入路径。只有
`ERROR_ACCESS_DENIED` 会进入重试：

- 使用消息窗口的临时 `WM_TIMER`，间隔 16 ms；
- 最多 16 次尝试或 250 ms 总时限，以先到者为准；
- 队列为空后立即 `KillTimer`，不存在常驻 timer 或主动轮询；
- 非 `ERROR_ACCESS_DENIED` 错误立即按标准 method-channel error 返回；
- `PlatformHandler` 析构时取消仍在等待的请求并返回
  `ERROR_OPERATION_ABORTED`，避免悬挂 `MethodResult`；
- 读取结果在进入 Dart 前限制为 1 Mi UTF-16 code units，过大时返回
  `ERROR_BUFFER_OVERFLOW`；
- Debug 诊断只包含错误码、尝试次数和耗时，不包含文本、长度摘要、哈希或 URL。

重试不会 `Sleep` platform thread。测试辅助进程为了稳定制造竞争而使用的
`Start-Sleep` 只存在于 `tool/windows_clipboard/hold_clipboard.ps1`，不进入 App 或
Engine 运行路径。

## App 交互与隐私

`ClipboardService` 只会在用户点击显式粘贴按钮，或 Flutter 文本控件响应标准粘贴
动作时调用系统 API。它不缓存内容，只把 Engine 的不可用/过大错误映射为不包含内容的
用户提示。

外链字段的处理顺序为：

1. 读取纯文本并检查 1 MiB 通用上限；
2. 对 Bilibili 字段应用更小的 64 Ki code-unit 上限；
3. 去除整段首尾空白，在多行分享文本中优先寻找完整的 `bilibili.com/video/...` 或
   `b23.tv/...` URL；
4. 没有受支持 URL 时提取边界明确的 `BV`/`AV` 号；
5. 不改变其他输入框、搜索字段、歌词或 App 全局粘贴语义。

测试会临时替换系统剪贴板，只能恢复此前的纯文本表示；脚本在运行前会明确警告。
测试和产品代码都不打印剪贴板内容。

## 自动验证证据

### Engine 与补丁锁

- 顺序应用补丁后的源码 tree：
  `a2a14855283c7ff5cc58cda583b7b3f87d0ccb75`；
- clipboard patch SHA-256：
  `08BC97122592B7DD12C8E221316E7CE76FB8BD866C549663E515DBB337C5EED2`；
- v4 定制 DLL SHA-256：
  `40EF7DF5832A7EBD56FEBEE4BBF293B5397F23F8EFFD409B384E0C2D2F18FEA6`；
- 官方 102 个导出，定制 103 个导出，唯一新增仍是版本化的
  `FlutterDesktopKirakaraCompositorGetApi`；
- 19 项聚焦剪贴板单测通过，覆盖 get/set 临时竞争、截止失败、空/不支持格式、过大
  文本、复制后的所有权和析构取消；
- Windows Engine 全量实际执行 365 项：363 通过，2 项既有 low-power adapter
  顺序依赖失败；两项各自在独立进程中通过。门禁只在精确匹配这两个既有失败且独立
  对照通过时接受，1 个上游禁用测试不计入实际执行数。

本地产物和测试报告保存在被 Git 忽略的 `build/diagnostics/engine/`：

- `phase6-v4-candidate-artifacts.json`；
- `phase6-v4-locked-artifacts.json`；
- `phase6-v4-focused-tests.json`；
- `phase6-v4-full-tests-gated.json`。

### App 与 Windows integration

- `clipboard_service_test.dart` 与 `external_link_clipboard_test.dart`：8 项通过；
- 官方 Engine：Unicode/CRLF 与所有键盘/菜单交互 2 项通过，定制竞争项按预期跳过；
- `host_debug_kirakara_v4`：上述 2 项加 120 ms 外部占用重试，共 3 项通过，且 bundle
  DLL 与锁定产物逐字节匹配；
- `flutter analyze`：0 error、0 warning，保留仓库既有 68 条 info；
- 全量 `flutter test`：94 项通过，唯一失败仍是未改动的
  `bilibili_resolver_test.dart` 期待已下线的 `qn=6` 画质选项，与本阶段无关；Phase 6
  新增与受影响测试全部通过。

### 合成器非回归

- synthetic v4：静止样本 Stage `+120` / Flutter `+1`（启动边界），随后
  Stage `+120` / Flutter `+0`；750 ms stall 为 `+45/+0`，缩放、Visual tree、页面和
  遮罩门禁通过；
- real Show v4：两秒静止 UI 为 Stage submit/present `+120/+120`、Flutter `+0`；
  标题/无标题、暂停、重唱、自然切歌、隐藏恢复、Show rebuild 和 detach 均通过；
- external texture A/B：官方 Engine 活跃 `61/61`、隐藏 `0/0`、恢复
  `35/34`、重建 `45/42`；v4 定制 Engine 活跃 `60/60`、隐藏 `0/0`、恢复
  `35/35`、重建 `45/43`。计数分别为 callback/advanced acquire。

## 复现命令

```powershell
.\engine\scripts\test_patched_windows_engine.ps1 `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -Suite kirakara,clipboard,critical,compositor,adapter-isolated

.\engine\scripts\test_patched_windows_engine.ps1 `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -Suite adapter-isolated,full `
  -AllowKnownFullSuiteOrderFailures

.\tool\windows_clipboard\run_windows_clipboard_baseline.ps1 `
  -FlutterExecutable 'D:\Program Files\Flutter\bin\flutter.bat'

.\tool\windows_clipboard\run_windows_clipboard_contention_probe.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -LocalEngine host_debug_kirakara_v4
```

## 尚未验证，必须实机完成

- Windows 10、RDP/远程剪贴板、记事本/浏览器/Office 等真实来源；
- 真实触摸屏点击显式粘贴按钮，以及原生中文 IME 候选窗与粘贴交替操作；
- 非文本多格式剪贴板的无损恢复（测试工具明确不承诺）；
- 第三方程序持续占用超过 250 ms 后的用户体验，以及随后再次点击可恢复；
- release/portable 包中的最终 v4 DLL 选择和隐私审计。
