# Phase 7：兼容性门禁与发布候选

## 当前结论

Phase 7 的自动门禁和仓库所有者确认的核心实机范围已经完成。这里的“完成”表示内部
Release Candidate 的既定阶段验收完成，不表示所有 Windows/GPU/显示拓扑均已认证。
当前已经得到：

- 锁定的 v4 custom Engine debug/profile/release 三模式产物；
- 官方 Release 与 custom Release 对称的正常启动、窗口响应和优雅退出证据；
- 运行时 ABI、结构大小、patchset 版本和 Engine revision 的硬失败门禁；
- 可重复生成的 Portable、当前用户安装包、补丁源码包和独立 Engine 产物包；
- Portable 解包运行、安装、运行、卸载和隐私排除的自动门禁。
- 真实 Show DLL 的 Stage Visual ABI、协议、能力位、设备绑定导出与 bundle 哈希门禁。
- 发布烟测专用的 loopback LAN 隔离，以及“不新增 Windows 防火墙安全提示”的自动门禁。

2026-09-29 的补充现场验收确认 Intel Iris Xe / 1130G7 活动路径、真实 Show 约 30 分钟
稳态、真实高分屏或跨 DPI 移动、物理双屏与 Cast 模式切换通过。仓库所有者决定把真实
睡眠/恢复和显示器热插拔暂缓，并把 Windows 10、AMD/WARP、完整输入环境等保留为阶段
完成后的扩展兼容矩阵。另一位协作者从 clean clone 复现 Engine 归入 Phase 8，不再重复
阻塞 Phase 7。项目目前没有声明项目级发布许可证，也没有所有者提供的生产签名身份；
这两项会阻止把候选称为正式公开发行版，但不会阻止本地可移植包与无管理员权限的当前
用户安装门禁。

## 锁定的 Engine 三模式

`engine/engine.lock.json` 的 custom patchset v4 现在锁定 ABI 2，并同时锁定以下输出：

| 模式 | GN 输出 | `flutter_windows.dll` SHA-256 |
| --- | --- | --- |
| debug | `host_debug_kirakara_v4` | `40EF7DF5832A7EBD56FEBEE4BBF293B5397F23F8EFFD409B384E0C2D2F18FEA6` |
| profile | `host_profile_kirakara_v4` | `8038006253B0CDFC6AC8FB48C7E587ACE5AEAA5099DFFD471BED9F44024F52D6` |
| release | `host_release_kirakara_v4` | `03665D466DE8C3F20A1BB1ABF32348281B1E5BF35C61F537FB53F09A700B0532` |

上表保留 Phase 7 外部工作区的历史候选，继续用于 stock/custom A/B。Phase 8 的真实中文
路径构建另外锁定 `projectBootstrap.releaseCandidate`：同一
`host_release_kirakara_v4` 的 DLL 为
`DB07763F1551A8FD68346D30A547050975E14E73A79B1A239587F063CD70B0F8`，并精确锁定
import library、PDB、ICU、`gen_snapshot`、patched SDK 与仓库内 Dart SDK。外部历史候选
的旧 `gen_snapshot.exe` 在 `D:\仓库\Kirakara-App` 读取 AOT 输入时会把中文路径错误解码，
所以不能冒充仓库本地 Unicode-safe 候选；两份契约分别保留，不静默覆盖历史 A/B 证据。

profile/release 除 Windows DLL、import library、PDB 和 ICU 外，还锁定
`gen_snapshot.exe`、`flutter_patched_sdk/platform_strong.dill` 与
`vm_outline_strong.dill`。第一次 App profile 构建正是因为只构建
`gen_snapshot` 而缺少 patched SDK 被门禁拦下；补齐明确的
`flutter_patched_sdk` Ninja target 后才重新构建和锁定。这个失败证明脚本不会用
SDK 中另一份不匹配产物掩盖本地 Engine 缺件。

严格验证报告为：

- `build/diagnostics/engine/phase7-v4-all-modes-with-sdk-locked.json`；
- 三模式均保留官方 102 个导出，只增加
  `FlutterDesktopKirakaraCompositorGetApi`；
- 源码树、补丁 SHA-256、`args.gn`、MSVC 14.34、PE linker 和所有锁定产物均匹配。

## Release A/B 与冒烟脚本修正

早期 Release 烟测曾同时把官方和 custom 构建记为“正常 close 后 20 秒未退出”。这
不是 App 或 Engine 生命周期差异。烟测先调用一次会超时的 `WaitForExit`，随后没有
刷新 `.NET Process` 的主窗口缓存；Flutter 启动期间顶层窗口句柄发生变化，
`CloseMainWindow` 因而使用旧句柄。

`smoke_windows_app.ps1` 现在在关闭前调用 `Process.Refresh()`、重新记录关闭目标 HWND，
并把关闭耗时写入报告。修正后：

| 构建 | 正常关闭 | 强制清理 | 退出码 | 关闭等待 |
| --- | --- | --- | --- | --- |
| 官方 Release | 通过 | 否 | 0 | 163 ms |
| custom v4 Release | 通过 | 否 | 0 | 168 ms |
| custom v4 debug | 通过 | 否 | 0 | 见本机报告 |
| custom v4 profile | 通过 | 否 | 0 | 见本机报告 |

对应报告：

- `phase7-official-release-smoke-graceful.json`；
- `phase7-v4-release-smoke-graceful.json`；
- `phase7-v4-debug-smoke-graceful.json`；
- `phase7-v4-profile-smoke-graceful.json`。

旧的失败和显式 `-AllowForcedCleanup` 报告保留为诊断历史，不能再用于判断当前 App
退出语义。新门禁默认仍禁止强制清理；只有调用者明确选择该诊断开关时才允许记录已知
缺陷。

后续发布候选烟测暴露了另一个测试环境副作用：每个新解压或新安装路径中的 App 都会按
生产语义把点歌 LAN 服务绑定到全部 IPv4 接口，Windows 因而为新 executable path 启动
`PickerHost.exe FirewallNotificationDialogServer`。这些安全提示在无人值守烟测结束后仍然
存在，还会遮挡 DirectComposition 稳态探针。只读进程清单确认遗留实例的创建时间与此前
Portable/Installer 烟测一一对应；这不是 compositor device-loss 或计时器问题。

schema v4 烟测只给它启动的子进程设置 `KIRAKARA_SMOKE_LAN_LOOPBACK=1`，由 App 将
`LanServer` 注入绑定到 `127.0.0.1`。普通启动不设置该变量，默认仍绑定 `0.0.0.0` 并公布
探测到的 LAN 地址，点歌语义没有改变。脚本还在启动前和退出后的有限 750 ms 等待后读取
`FirewallNotificationDialogServer` PID 集合，并对比精确 executable path 对应的防火墙
application-rule ID；任何新增提示或规则都会使报告和发布门禁失败。脚本不会关闭既有或
新增安全窗口，也不会添加、删除、启用或禁用防火墙规则、profile 或策略。schema v4 已在
普通 bundle、全新解压路径及最终 Portable/Installer 路径通过：每次均正常退出、没有强制
清理，提示与规则增量都为 0。系统三个防火墙 profile 在验证时保持启用。

提交前 Flutter 回归没有新增 compositor/clipboard 问题：锁定 SDK 的
`dart analyze lib test tool` 为 68 条仓库既有 info、0 warning、0 error；完整
`flutter test` 在新增 4 项 cadence 单测后为 102 通过、1 个既有失败。
唯一失败仍是 `bilibili_resolver_test.dart` 期待已经从实际质量列表移除的 `qn=6`，与
本阶段 Windows 脚本、Engine 锁和发布包无关，未在此提交中顺手修改业务断言。

## ABI 与版本不匹配门禁

运行：

```powershell
.\engine\scripts\test_engine_abi_gate.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine'
```

脚本在独立 PowerShell 进程中直接加载三模式 DLL，但不初始化 Flutter view：

- 官方 DLL 必须没有 custom export，继续作为 stock/external texture 回退构建；
- custom DLL 以错误 ABI 请求时必须返回
  `kKirakaraFlutterCompositorVersionMismatch`；
- API 结构大小错误时也必须返回同一明确错误；
- 只有 ABI 2、patchset 4、`windows-dcomp-stage-visual` 和锁定 Engine revision
  完全一致时才成功；
- 返回的六个函数指针必须全部非空。

当前 `phase7-abi-gate.json` 对 debug/profile/release 全部通过。Runner 在选择
`synthetic` 或 `composed` 时还会再次检查相同元数据，并在缺导出或元数据不匹配时显示
明确错误；它不会用 external texture 静默掩盖一个已选择 custom backend 的版本错误。

## 发布包

构建 custom Release 后运行：

```powershell
.\engine\scripts\package_windows_release.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -ShowHostDll 'D:\仓库\Kirakara Show\build\bin\libshow_host.dll'
```

脚本在忽略的 `build/releases` 目录生成：

1. `*-portable.zip`：解压即用的运行目录；
2. `*-installer.zip`：逐文件验证 SHA-256 后安装到
   `%LOCALAPPDATA%\Programs\Kirakara` 的当前用户安装包，不要求 UAC；
3. `*-patch-source.zip`：锁文件、补丁、获取/应用/构建/校验脚本和阶段文档；
4. `*-engine-artifacts.zip`：严格候选的 DLL、import library、PDB、ICU、AOT 工具和
   patched Dart SDK，作为 Release 资产保存，不进入运行包或普通 Git；
5. `*-release-index.json`：四个归档的相对路径、大小、SHA-256、测试报告位置、Show
   协议、Engine 候选契约、签名和许可证状态。

运行冒烟报告写入所选输出目录的 `diagnostics/` 子目录，发布索引保存相对路径。这样
第二位协作者可用独立的 `-OutputDirectory` 重建同一提交，不会与已有全局报告重名，
发布索引也不会泄露或固化构建者的绝对目录。

运行文件选择把 CMake 最后一次 Debug/Profile/Release 的 `install_manifest.txt` 映射
为配置无关的 Release 相对路径，再显式包含不可变的 `data/`、`ime/` 运行目录和顶层
`.exe`、`.dll`、必要 `.json`；因此最后构建哪个模式都不影响文件集。任何不能分类的
新文件都会令打包失败。构建目录中运行 App 后产生的
`settings/**`、`bilibili_session.json`、SQLite 数据库、WAL/SHM 和 `*.log` 不会进入
包；当前 ZIP 内容扫描为零匹配。每个运行文件、`release-manifest.json` 和
`SHA256SUMS.txt` 都有哈希。

打包前必须显式提供当前 Show 产物。脚本在创建 staging 目录前验证错误 ABI/结构大小
返回 version mismatch、ABI 1、能力 `0xF`、`nt-keyed-latest-v1`、零保留位、全部函数
指针与 `show_host_set_stage_d3d_device` 导出，再要求 Release bundle 的 DLL 与该输入
逐字节一致。仓库内历史 DLL 只保留 external texture 兼容性，缺少 Stage Visual 导出，
作为 composed 发布输入会明确失败，不能等到用户机器上崩溃。

ZIP entry 按路径排序并使用固定时间戳。相同输入连续打包两次时，Portable、安装包、
补丁源码包和 Engine 产物包的 SHA-256 分别逐项完全一致。默认门禁还会：

1. 解压 Portable，核对锁定 DLL/ICU，启动并正常关闭；
2. 解压安装包，校验全部 payload 哈希；
3. 安装到隔离的临时目录，启动并正常关闭；
4. 用带产品标记与精确路径检查的卸载器删除该测试安装；
5. 确认测试安装目录已经消失。

Portable 与 Installer 两次启动都必须使用仅对子进程生效的 loopback 隔离，并在 schema v4
报告中同时满足 `firewallPromptGatePassed=true`、`newFirewallNotifications=[]`、
`firewallRuleGatePassed=true` 和 `newFirewallApplicationRules=[]`。因此发布验证不会要求
用户授权一个临时 executable path 的入站访问，也不会留下新的 Windows 安全提示或规则；
这项隔离不进入安装结果或普通 App 进程。

`-SkipRuntimeSmoke` 只用于重复性对照，不能用于发布候选验收。运行包中不包含 PDB；
PDB 只存在于 Engine 输出和单独的 Engine Release 资产，并由候选契约记录大小和
SHA-256。DLL、PDB、ZIP 和 Engine 源码都不进入普通 Git 历史。

防火墙隔离前的仓库本地门禁仍保留在
`build/diagnostics/release-show-gate-final-clean-a-20260929/`，但不再作为最新候选。schema v4
完整门禁位于 `build/diagnostics/release-firewall-schema4-a-20260929/`，重复性对照位于
`release-firewall-schema4-b-20260929/`：源码提交为
`1ea696f02be313f6f350ac1ba5d3ef4b5a688a65` 且 `sourceDirty=false`，release index schema 3，
Portable/Installer 两份运行报告均为 smoke schema 4、`lockedArtifactGate=true`、正常退出、
无强制清理、无新增安全提示、无新增 application rule，安装和卸载也通过。门禁前只读清单
中已有 64 条历史 Kirakara 临时路径规则；脚本没有删除它们，完整门禁后总数仍为 64。

A/B 四个归档的大小和 SHA-256 逐项一致：

| 归档 | 字节 | SHA-256 |
| --- | ---: | --- |
| Portable | 83,105,072 | `596FEB13F840F665A245395500A36ED8DDBF82C10256C50F60B8A8D34525B556` |
| Installer | 83,111,591 | `E8968DF950800965342EBC15E8E10E8CCD95D1C16F93AB9D457B01AE1A3D7B9F` |
| Patch source | 275,910 | `0F16C32FD297D68B51E0B58BF3BD122C271B29CD0228BACDB55F6745D60F6DD4` |
| Engine artifacts | 95,488,256 | `EE9F25543AD1C8AC22355952585890AC81081E6623C6B211DCA25976BCFC51E3` |

Show SHA-256 仍为
`1CA811AE12B508903426F89F8A3B7E4B84261C9DEC4538173519F8E465E35519`。四个 ZIP 的条目名
隐私扫描为零命中，补丁源码包包含 wrapper、release contract、Show ABI 校验器及
compositor/clipboard 工具；生成媒体、报告与缓存保持排除。Engine 包包含候选契约规定的
10 个产物和独立 manifest。使用历史 Show DLL 的负向打包仍会在创建输出目录前明确拒绝。

schema v4 前的一次预检在旧 Windows 安全窗口尚未处理时捕获到 Portable 正常关闭超时，
门禁按设计强制清理并判失败；这份失败不计入候选。相同归档在安全窗口处理后连续三次正常
退出，最终 A 的 Portable/Installer 也都正常退出。该相关性不冒充已证明的根因，负报告继续
保留，后续稳定性测试仍把退出超时作为硬失败而不是自动重试掩盖。

当前安装包是未签名的本地门禁产物。没有所有者签名证书时，脚本不会生成或信任一个
伪装成生产身份的自签名证书，也不会修改系统信任存储。

## 当前主机兼容性证据

`capture_windows_compatibility_inventory.ps1` 只写诊断报告，不会把探测结果保存为 App
运行时决策。当前 `phase7-current-host.json` 记录：

- Windows 11 Pro 23H2 / build 22631，x64，DWM 开启，非远程会话；
- Intel Core i5-12600K；
- 活动实机路径为 NVIDIA GeForce RTX 4060 Ti，驱动 `32.0.15.9186`，当前
  `1920×1080 @ 60 Hz`；
- 系统还能枚举 UHD 770 和虚拟显示驱动，但 UHD 770 不是本次活动呈现设备，虚拟 4K
  模式也不等于真实 4K 显示器验证。

已验证矩阵：

| 项目 | 状态 |
| --- | --- |
| Windows 11 / NVIDIA / 1080p60 | 自动与人工门禁通过 |
| 100%、125%、150% 单屏 DPI | Phase 2 自动门禁与用户观察通过 |
| 单 HWND、Alpha 孔、Flutter 覆盖、缩放、焦点、中文 IME | 通过 |
| 720p60 fixture 到固定 1080p Stage，再缩放到 preview | 真实 Show probe 通过 |
| 最小化/恢复、模拟 session/power/display 消息、Show 重建 | Phase 4 自动门禁通过 |
| composed preview 的音频先 EOF、视频先 EOF 与失配后恢复 | 真实 Show 刻意失配门禁通过 |
| 官方/custom external texture A/B | 通过且继续保留 |
| custom debug/profile/release 构建与启动 | 通过 |
| 官方/custom Release 正常退出 | 通过 |

补充实机验收与延期矩阵：

| 项目 | 当前状态/原因 |
| --- | --- |
| Windows 10 | 延期扩展兼容项；当前主机不可用 |
| Intel Iris Xe / 1130G7 活动真实 Stage 路径 | 2026-09-29 用户现场确认通过 |
| AMD、Microsoft Basic Render/WARP | 延期扩展兼容项；不由 Intel/NVIDIA 结果外推 |
| 真实高分屏或跨 DPI 移动 | 2026-09-29 用户现场确认通过；未附新的自动报告 |
| 真实显示器热插拔、睡眠/恢复 | 所有者决定暂缓；模拟消息结果不改写为实机通过 |
| graphics device removal | 延期扩展兼容项 |
| 物理双屏和 Cast 至少各一次模式切换 | 2026-09-29 用户确认已在实际使用与 Pure K 投屏验收中通过 |
| 4K 下采样及 576p/540p/480p/360p 上采样视觉 | Show 单测覆盖几何，尚缺本 compositor 实机视觉矩阵 |
| 物理 Stage/Cast 并行时的音视频 EOF 不一致与缓冲异常 | composed preview 已用刻意失配素材通过；当前缺实体输出拓扑 |
| Iris Xe 1130G7、真实 Show 约 30 分钟稳态 | 2026-09-29 用户现场确认通过 |
| 真实触屏、RDP、第三方富文本剪贴板 | 延期扩展兼容项；当前自动/桌面输入不能替代 |

## 实体机验收操作单

每台机器先在普通 PowerShell 采集一次只读清单，不要把结果写入 App 设置：

```powershell
Set-Location '<你的 Kirakara-App clean clone>'
.\tool\windows_compositor\capture_compatibility_inventory.ps1
```

记录报告路径、Windows 版本、活动 GPU/驱动、实际显示分辨率/刷新率和是否为 RDP。
设备“能枚举”不等于测试使用了它；必须从活动显示模式和探针窗口所在显示器确认目标
GPU/屏幕。

### 真实高分屏和混合 DPI

先用仓库入口准备并解析锁定的 debug Engine 与 Flutter SDK。普通实机验证默认使用仓库内
`.kfe`；Phase 7 的严格 release-candidate 哈希重建和 stock/custom A/B 仍可按
`engine/README.md` 使用显式外部工作区。

```powershell
.\flutterw.cmd engine prepare debug
$engineDoctor = .\flutterw.cmd engine doctor | ConvertFrom-Json
$flutterSdkRoot = $engineDoctor.flutterSdk.root
$workspaceRoot = Join-Path (Get-Location) '.kfe'
```

每个 175%/200% 档位都启动新进程，第一次不要使用 `-SkipBuild`：

```powershell
.\tool\windows_compositor\run_synthetic_compositor_probe.ps1 `
  -FlutterSdkRoot $flutterSdkRoot `
  -WorkspaceRoot $workspaceRoot `
  -LocalEngine host_debug_kirakara_v4 `
  -ExpectedScalePercent 175 `
  -KeepOpen
```

200% 时把参数改为 `200`。有两台不同 DPI 显示器时再加 `-RequireMixedDpi`；探针会移动
同一个 HWND 到另一显示器再移回，单屏或相同 DPI 环境必须明确失败/跳过，不能算通过。
留窗期间人工检查：透明孔只显示 Stage、孔外无 Stage 泄露、圆角正确、普通面板/对话框/
抽屉/全屏预览控件始终在 Stage 上方；反复拖动缩放无白闪和控件消失；鼠标、焦点、
Unicode 输入及系统中文 IME 候选/提交正常。

必须保存报告中的 `windowDpi`、每个 monitor 的 DPI/scale/bounds、mixed-DPI move/restore
结果、HWND、surface size、`compositionTreeCommitCount`、`surfaceResizeCount`、
`stagePresentDelta` 和 `flutterPresentDelta`。静止 Flutter 的 Stage-only 样本仍应为
Stage 前进且 Flutter delta 为 0；所有 HRESULT、device removal 和资源失败计数应为 0。

### 真实 Show、生命周期和当前 GPU

```powershell
$eofMismatchRoot = '.\build\diagnostics\eof-mismatch-fixtures'
.\tool\windows_compositor\make_eof_mismatch_fixtures.ps1 `
  -OutputDirectory $eofMismatchRoot

.\tool\windows_compositor\run_real_stage_compositor_probe.ps1 `
  -FlutterSdkRoot $flutterSdkRoot `
  -WorkspaceRoot $workspaceRoot `
  -LocalEngine host_debug_kirakara_v4 `
  -ShowHostDll '<当前 Show build\bin\libshow_host.dll>' `
  -EofMismatchFixtureRoot $eofMismatchRoot `
  -TimeoutSeconds 120 `
  -LifecycleProbe `
  -ExitWhileActive
```

每个 Intel/AMD/NVIDIA 主动呈现环境都单独执行。保存：静止和 platform stall 的
Stage/Flutter delta、Show callback/rejected、submit/coalesced/stale、keyed-mutex busy、
handle duplicate/resource open failure、occluded/device removed、全部 HRESULT、generation/
frame ID、最小化/恢复、Show rebuild 和 active-exit gate。若环境不支持，记录实际能力与
HRESULT 后验证 external texture 回退；崩溃、同步错误或资源破坏不得归类为兼容回退。
失配 EOF 报告还必须保存两组媒体的实际 duration、音频 EOF 后状态/position、最终
state/buffering 和普通歌曲恢复样本。生成的 MP4/WAV 位于忽略目录，不能加入 Git。

真实锁屏、睡眠/恢复和显示器热插拔必须由操作者实际执行，报告里的 simulated lifecycle
消息只证明 Win32 路由和状态机。操作前后确认同一个 App 顶层 HWND、Stage 恢复推进、
Flutter 控件覆盖仍正确，且 Show callback 不等待 Flutter/DComp。

### 回退路径与剪贴板

按 `engine/README.md` 分别运行官方 Engine 和 custom Engine 的
`run_windows_stage_texture_baseline.ps1`，两者都显式选择 `external_texture`。记录
callback/acquire/present、inactive 停止唤醒和重建结果。然后运行 stock 剪贴板 baseline
及 custom contention probe，并人工覆盖触屏粘贴、RDP、浏览器/记事本/富文本来源。
日志只能出现错误码、尝试次数和耗时；测试结束后搜索诊断/设置，确认没有剪贴板文本。

### 热态和 Trace

在 1130G7/Iris Xe 目标机先运行有界 synthetic 稳态门禁：

```powershell
.\tool\windows_compositor\run_synthetic_compositor_probe.ps1 `
  -FlutterSdkRoot $flutterSdkRoot `
  -WorkspaceRoot $workspaceRoot `
  -LocalEngine host_debug_kirakara_v4 `
  -SoakSeconds 1800
```

`-SoakSeconds` 只接受 `30..14400`，并与人工观察用的 `-KeepOpen` 互斥。脚本仅在子进程
存活期间调用线程级 `SetThreadExecutionState` 防止系统和显示器进入空闲休眠，退出或失败
都会恢复，不修改电源计划，也不需要 UAC。Dart harness 只做冷机、半程和终点三次采样，
中间是两次有限 `Future.delayed`，没有轮询或常驻 timer。synthetic producer 跟随 DComp
compositor clock，并不承诺固定 60 Hz；harness 先合并两段真实静止样本建立 30～360 Hz
范围内的参考时钟，再要求两半和全程保持在参考值的 ±10%（至少 5 Hz）内。wait wake 与
present 差值不超过 3、静止 Flutter present 增量不超过 3；HWND/尺寸/Visual Tree 不变，
device removal、occluded、handle/resource failure 与所有关键 HRESULT 必须保持健康。RSS
三点只作为趋势数据，不用单个阈值掩盖泄漏调查。这只修正测试判据，不改变真实 Show 的
独立约 60 fps 生产时钟。

窗口必须真实可见且不被系统安全桌面或其他窗口完全遮挡；`0xc01e0006`
（`STATUS_GRAPHICS_PRESENT_OCCLUDED`）会明确失败，不能作为热态通过。2026-09-29 当前主机的
30 秒负例在前台 `PickerHost / Windows 安全中心` 存在时正确失败，并写出 0/15/30 秒三点。
只读追查确认这些窗口来自旧版发布烟测触发的防火墙授权；修正后的 smoke 不再产生新实例，
现有安全窗口由用户处理，自动化没有替用户批准或关闭。桌面恢复后的正确 synthetic 30 秒
样本 `synthetic-compositor-soak-30s-measured-clock-20260929.json` 已通过：参考 140.680 Hz，
前后半程为 138.924 / 138.448 Hz，Stage present/wake 都推进 4161，Flutter present 增量 0，
RSS 增量 65,536 字节，全部 HRESULT、拓扑、遮挡及 device-removal 门为真。随后完整样本
`synthetic-compositor-soak-1800s-measured-clock-20260929.json` 也通过：实测参考 139.430 Hz，
前后 900 秒为 137.362 / 137.475 Hz，全程 137.419 Hz；Stage present/wake 都推进 247,354，
Flutter present 只在前半增加 1、后半增加 0；RSS 从 272,994,304 降到 270,983,168 字节，
差值 -2,011,136。所有 HRESULT、device removal、occlusion、handle/resource failure、HWND、
尺寸和 Visual Tree 门都保持健康。该样本证明当前桌面的有界稳态，不替代 Iris Xe 目标机、
真实 Show/物理 Stage/Cast、温度/功耗或视觉卡顿实测。

有界门禁通过后，可再用 synthetic `-KeepOpen` 做人工视觉观察；同时按实际业务方式播放
真实节目、物理 Stage/Cast 时另做一轮。冷机、15 分钟和 30 分钟各记录分辨率/刷新率、
Stage cadence、Flutter present、GPU 引擎利用率、温度/功耗（设备可提供时）、device
removal/HRESULT 和视觉卡顿。不要只报平均帧率，要保留间隔分布或 PresentMon/ETW 原始
数据。

WPR/ETW 只有这一步需要管理员终端。先确认 App/Show/服务器和固定场景已经就绪，再在
管理员 PowerShell 运行 `capture_compositor_trace.ps1`；每份 ETL 只对应一个命名场景，
结束后用 `analyze_compositor_trace.ps1` 关联 Show publish、callback、acquire 和 present。
普通构建、ABI、打包、安装和上述自动探针都不需要 UAC。

## 回滚与发布纪律

- 不改变业务代码即可用 `build_windows_app.ps1 -Engine official` 重建官方 Engine 包；
- custom Engine 仍能显式选择 `external_texture`，该路径有独立 A/B 门禁；
- custom `composed` 初始化、同步或版本错误必须可见，不能静默回退掩盖 Bug；
- Engine 升级先更新 Framework/Engine revision，再重放补丁、重新锁定三模式产物、运行
  ABI 门禁和官方/custom A/B；任何一步失败都不得沿用旧 DLL；
- 普通 Git 只保存锁、补丁、脚本、ABI header、文档和测试；发布二进制、符号和包放在
  外部构建目录或版本化 Release 资产。

## Phase 7 退出条件状态

- 定制构建和官方构建都通过 Release 冒烟：**已满足**。
- 另一位协作者根据文档与补丁复现定制 DLL：**移入 Phase 8 独立验收**；本机从锁定
  外部工作区重建和严格校验已通过，Phase 7 不再重复等待同一门槛。
- Flutter 升级时不能静默加载 ABI/版本不匹配 DLL：**已满足自动门禁**。

仓库所有者于 2026-09-29 接受上述核心实机范围，并明确将睡眠/热插拔等低频项目延期；
因此 Phase 7 标记为完成。扩展兼容矩阵、生产签名和许可证仍须保持可见，不能把本结论
宣传为全平台正式发行认证。Phase 8 和总计划仍等待独立 clean-clone 验收。
