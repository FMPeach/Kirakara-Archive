# Windows 剪贴板 Phase 0 基线

采集日期：2026-09-27（Asia/Shanghai）

剪贴板补丁与合成器实现保持独立。本阶段仅通过 Flutter 标准 `Clipboard` API
冻结 stock Windows runner 的 Unicode 与 CRLF 文本往返行为，没有实现重试、监听、
缓存、持久化或内容诊断。

实机 integration test 已通过。测试不会输出或持久化剪贴板文本；它会临时替换系统
剪贴板，并在结束时尽力恢复此前的纯文本表示。标准 Flutter API 无法无损保存任意
非文本格式，因此测试默认跳过，只能通过显式脚本启用：

```powershell
.\tool\windows_clipboard\run_windows_clipboard_baseline.ps1
```

尚未验证的交互项保留到独立剪贴板轨道：Ctrl+C、Ctrl+X、Ctrl+V、Shift+Insert、
右键菜单、触屏显式粘贴以及 IME 焦点。Phase 0 没有在启动时读取剪贴板，也没有
添加监听器或后台任务。
