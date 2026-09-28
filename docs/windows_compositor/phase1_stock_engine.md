# Windows 定制合成器 Phase 1：Stock Engine 基线

## 结论

Phase 1 使用与 Flutter 3.44.4 完全匹配、没有 Kirakara 行为补丁的 Windows
Engine 源码，建立了可重复获取、校验、构建和切换流程。源码与产物位于 App
仓库外的 `E:\Kirakara-Flutter-Engine`；App 仓库只保存锁文件、空补丁栈、脚本、
测试与本文档。安装目录 `D:\Program Files\Flutter` 保持未修改。

本阶段最重要的兼容性结论是：Flutter 官方 Windows DLL 使用 MSVC 14.34 链接。
使用 Visual Studio 2026 默认的 14.51 工具集时，源码虽然能够编译和链接，但
`TaskRunnerDelayedTask` 会超时，`NextFrameCallback` 和真实 Show integration 也会
停住。安装并显式锁定 14.34.31933、编译器 19.34.31948.0 和对应 ATL 后，这三条
运行路径恢复正常。因此锁文件同时固定工具集与 ATL component，而不是把“编译
成功”当作可运行性证明。

## 锁定输入

| 项目 | 锁定值 |
| --- | --- |
| Flutter Framework | `ad70ec4617166f1c38e5d2bfd388af71fda14f06` |
| Flutter Engine DEPS revision | `a10d8ac38de835021c8d2f920dbf50a920ccc030` |
| Engine source tree | `61678b80d02f518a8a4d15868d398b8480d6613e` |
| Engine content hash | `700aebeca4c0e610f109a3979ee3e71b69d666bc` |
| depot_tools | `41c9bd890277c2f551499d171d215dfdf5dab97d` |
| patchset | `stock`，version 0，补丁列表为空 |
| Visual Studio | Community 2026 `18.6.11806.211` |
| MSVC | `14.34.31933`，编译器 `19.34.31948.0`，含 ATL |
| Engine Windows SDK | `10.0.22621.0` |

`engine/engine.lock.json` 是机器可读的权威记录。脚本在 fetch、build、verify 和 App
切换前都会校验 revision、源码内容、补丁状态与工具链；stock 阶段发现 Engine
源码或 depot_tools 工作树有改动时直接失败。

## 三模式构建与 ABI

三种模式均使用 `--no-rbe --no-goma --no-lto --no-stripped`；release 另外保留
上游工具要求的 `--xcode-symlinks`。最终锁定的关键产物为：

| 模式 | `flutter_windows.dll` 大小 | SHA-256 |
| --- | ---: | --- |
| debug | 45,547,520 | `971CCDC1C737825FB86D73858A168594A880F6C8BEB2D44CDEB3D9A13B5639A9` |
| profile | 21,864,448 | `821B9B60419B8537E21346AE180CE4A22041FBE4A32EFE842BC833DF9783FEA2` |
| release | 21,281,280 | `F12FD0BBECC2C0ED99C16EE5A69819C4E9A95DC08304D28E67428D73A95B3D9E` |

每个模式的 DLL、import library、PDB、ICU 数据及 profile/release 的
`gen_snapshot.exe` 都已记录大小和 SHA-256。PDB 与二进制仅留在外部构建目录，
没有进入普通 Git 历史。

`verify_engine_bundle.ps1 -RequireLockedHashes` 对三种模式均通过：

- `args.gn` 与锁文件逐字节校验；
- 所有列出的本地产物大小和 SHA-256 完全匹配；
- 官方和本地 `flutter_windows.dll` 都有 102 个导出，差异为 0；
- 官方和本地三个模式的 PE linker version 均为 14.34；
- 本地源码、depot_tools、Framework 与 SDK Engine revision 均保持锁定状态。

本地 DLL 不要求与官方 DLL 字节相同。官方构建的内部路径和构建环境不同；本阶段
以相同源码、相同公开 ABI、相同 linker 世代、锁定产物及运行行为作为等价门槛。

### 原始哈希的边界

对完全相同的源码、GN 参数和 14.34 工具链执行第二轮构建时，三个模式的 DLL 与
PDB 原始 SHA-256 都发生了变化；import library 和 ICU 数据保持不变，DLL 大小、
102 个导出和 linker version 也保持不变。`dumpbin /headers` 进一步确认 stock
链接器把实际链接时间写入 PE header 和 debug directory，并更新 CodeView/PDB
identity。Flutter SDK 随附的官方 DLL 也带有其 CI 链接时间和构建路径，而不是
确定性时间戳。第二轮中 profile PDB 还出现了 8192 字节的尺寸变化。

因此本项目不把 stock Engine 描述为 bit-for-bit 可复现。锁文件中的原始大小和
SHA-256 用来唯一绑定经过测试、准备随 App 分发的那套产物；“可复现构建”指锁定
源码、依赖、GN 参数和工具链后可以重新构建并重新执行 ABI、单测和 App A/B
门槛。重建后的候选值只能通过显式 `-CaptureArtifactHashes` 生成报告：该模式仍
校验 revision、洁净源码、`args.gn`、MSVC、PE linker 和导出表，列出全部差异，
但不会修改锁文件。候选报告必须先经人工审查，校验值才可作为独立、可审查的源码
变更写入锁；随后必须用 `-RequireLockedHashes` 复核并完成运行门槛，任一门槛失败都
不能把该候选作为可分发产物；不存在自动接受漂移的路径。

本次最终接受流程先生成 schema 2 候选报告，逐项确认 revision、洁净源码、GN
参数、14.34 linker 和 102/102 导出，再人工更新锁文件；随后三模式严格哈希校验
全部通过。Debug 是清理后完整恢复的第三次构建，profile/release 是第二次完整
构建。锁定值标识这套已完成下述运行门槛的分发候选，不声称任意重建会得到同一
原始哈希。

## Engine 测试

Debug `flutter_windows_unittests.exe` 的有界门槛结果：

| 测试组 | 结果 |
| --- | --- |
| 延迟任务与 next-frame callback | 2 / 2，通过 |
| OpenGL/Software compositor、显示/DPI、D3D external texture | 25 / 25，通过 |
| 两个 low-power adapter 测试，各自独立进程 | 1 / 1 + 1 / 1，通过 |
| 完整 Windows suite | 354 项中 352 通过，原始进程 exit 1 |

完整 suite 唯一失败项为：

- `WindowsTest.GetGraphicsAdapterWithLowPowerPreference`
- `WindowsTest.GetEngineGraphicsAdapterWithLowPowerPreference`

它们在各自独立进程中都通过。完整进程先执行 no-preference/high-performance
adapter 测试并缓存 LUID `67357`，随后 low-power 测试预期 LUID `83655`，表现为
上游 stock suite 的进程内顺序依赖。脚本不会把原始 exit 1 改写成全绿：报告保留
`allProcessesExitedZero=false`；只有同一次运行同时完成两个隔离对照，且失败集合
精确等于上述两项时，显式参数 `-AllowKnownFullSuiteOrderFailures` 才允许阶段门槛
通过。任何新增失败、超时或测试数变化仍会失败。

## App 运行 A/B

官方 Engine 与本地 stock Engine 都已通过真实 Show external texture integration，
且生成 bundle 后逐文件确认实际携带所选择的 DLL 与 ICU 数据。最终通过样本为：

| 模式 | Engine | 活跃窗口计数 | inactive 750 ms |
| --- | --- | --- | --- |
| debug | 官方 | 61 callback / 60 advanced acquire / 60 present | 0 callback / 0 present |
| debug | 本地 stock | 60 / 60 / 60 | 0 / 0 |
| profile | 官方 | 60 / 60 / 61 | 0 / 0 |
| profile | 本地 stock | 60 / 60 / 61 | 0 / 0 |

这里的 61 present 是异步 acquire/present 跨计数快照边界的一帧，不代表额外源帧。
在最终样本前，官方 debug 曾出现 60 callback / 55 advanced acquire，本地 debug
曾出现 60 / 53；各自无代码变化复测又回到 60 / 60。这复现了 Phase 0 已由 ETW
定位的 60 Hz 相位合帧，而不是本地 Engine 的稳定差异。回归门槛因此不再错误要求
“每个 callback 必须在同一个 1 秒窗口内 acquire”：它仍要求 callback 与
`FrameAvailable` 一致、advanced acquire 至少达到 callback 的 2/3、acquire/present
计数只允许有界线程快照差，以及 inactive 时停止唤醒。理想的 1:1 行为属于 Phase 2
架构目标，不能靠测试重试伪装成 stock 基线。

Release 因 `flutter drive --release` 不受支持，使用普通 App release bundle 做有界
启动、响应与退出烟测。官方和本地 bundle 都成功创建可响应顶层窗口并稳定观察
5 秒；两者收到标准关闭请求后都未在 20 秒内退出，随后由脚本只清理其自身启动的
精确 PID。未允许强制清理的报告均失败；显式 `-AllowForcedCleanup` 的报告仅证明
启动/响应路径通过，不把强制终止描述为优雅退出。该对称结果满足 Phase 1 的 Engine
行为等价判断，正常退出问题保留到生命周期阶段处理。

Phase 7 复核说明（2026-09-28）：上述现象后来定位为烟测在一次超时
`WaitForExit` 后复用了缓存的旧主窗口句柄；Flutter 启动期间 HWND 已变化。脚本在
close 前 `Process.Refresh()` 并重新读取 HWND 后，官方与 custom Release 分别约
163/168 ms 正常退出、退出码 0，均不需要强制清理。这里保留原始 Phase 1 观察用于
说明当时的等价判定，当前生命周期结论以
`docs/windows_compositor/phase7_compatibility_release.md` 为准。

烟测只追踪它自己启动的精确 PID；等待输入队列和顶层窗口均有截止时间，观察期间
检查窗口响应，退出阶段先发送正常 close，最后才允许对该 PID 做有界清理。测试
启动探针不是产品轮询或常驻定时器。集成测试生成的 runner bundle 不能拿来执行
普通 App 烟测，因为它在独立启动时不会建立正常主窗口；必须先用
`build_windows_app.ps1` 生成 App bundle。

App 侧补充门槛：Stage texture、preview host 与 Windows native media I/O 的定向
Flutter 测试共 5 项全部通过。全量 `flutter test` 为 82 项通过、2 项既有无关失败：
`bilibili_resolver_test` 仍期待已移除的 360p 质量项，`widget_test` 仍期待旧的
“登录哔哩哔哩”文案。`flutter analyze` 无 error/warning，但仍有 68 条既有 info。
这些结果均保留原始 exit code，不计为全绿，也没有在合成器阶段顺手修改业务测试。

## 可重复命令

首次获取与同步：

```powershell
.\engine\scripts\fetch_engine.ps1 `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine'
```

安装锁定工具集（需要时会触发一次 UAC）：

```powershell
.\engine\scripts\install_pinned_msvc_toolset.ps1 `
  -VisualStudioPath 'D:\Program Files\Microsoft Visual Studio\Community\2026'
```

验证空补丁栈并构建：

```powershell
.\engine\scripts\apply_patches.ps1 `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine'

.\engine\scripts\build_windows_engine.ps1 `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -VisualStudioPath 'D:\Program Files\Microsoft Visual Studio\Community\2026' `
  -Mode debug,profile,release
```

校验三模式产物和官方 ABI：

```powershell
.\engine\scripts\verify_engine_bundle.ps1 `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -Mode debug,profile,release `
  -RequireLockedHashes
```

构建 App 时，`-Engine official` 不传 local-engine 参数；切换到本地 stock 只需：

```powershell
.\engine\scripts\build_windows_app.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -Engine local `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -Mode debug,profile,release
```

## 尚需实体机与后续阶段验证

- 本阶段只证明 stock Engine 构建流程可复现和本机行为等价，不证明 Phase 2 的 Alpha 或
  DirectComposition 设计；Engine 源码尚无 Kirakara 行为改动。
- Iris Xe、AMD、其他 NVIDIA、Windows 10 以及目标部署机仍需重新构建或使用受控
  artifact 做运行验证，不能持久化本机能力探测结果。
- 混合 DPI、跨显示器、最小化/恢复、显示器热插拔、睡眠/恢复和 device removal
  属于 Phase 2～4，不从 stock smoke 外推。
- 现有 external texture 路径与官方 Engine 构建继续保留，后续每个 Phase 都要做
  A/B，避免兼容回退腐烂。
