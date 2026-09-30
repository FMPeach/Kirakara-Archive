# Kirakara Windows 定制 Flutter Engine 部署指南

本文面向一台新的 Windows 开发机，说明如何从 GitHub 获取 Kirakara App 与
Kirakara Show，并用仓库内的锁文件、补丁和脚本部署定制 Flutter Engine。

这里有三种不同用途，不要混在一起：

1. 只运行现成 Release：解压 portable 包即可，不需要 Flutter、Visual Studio 或 Engine 源码。
2. 开发和调试 App：使用 App 仓库根目录的 `flutterw`，让所有专用环境落在忽略的 `.kfe`。
3. 维护 Engine 或制作正式 Release：先完成开发环境，再按严格锁定的发布流程执行。

## 1. 源码与产物边界

源码只从 GitHub 获取：

- App：`https://github.com/FMPeach/Kirakara.git`
- Show：`https://github.com/FMPeach/Kirakara-Show.git`

App 仓库只保存锁文件、可审查补丁、脚本、文档和测试。以下内容不得提交进普通
Git 历史：

- Flutter Engine 大型源码；
- `.kfe`、`out`、下载缓存和构建缓存；
- `flutter_windows.dll`、PDB 和其他 Engine 二进制；
- App/Show 的构建输出。

网络盘只用于已经打好的 Release 产物，不作为源码来源。2026-09-30 的已验证产物目录名为：

```text
Kirakara-App-Windows-DComp-20260930-65641f1-show-405dd76
```

其中 `*-portable.zip` 可直接复制到本机后解压运行。不要从 `engine-artifacts.zip`
手工拆 DLL 到 Flutter SDK 或 `.kfe`；开发环境必须由 `flutterw` 建立和验证。

## 2. 当前实现锁定值

最终权威来源始终是 [engine.lock.json](../engine/engine.lock.json)，不要根据本文手工改锁。
当前关键值如下：

| 项目 | 锁定值 |
| --- | --- |
| Flutter | stable 3.44.4 |
| Framework revision | `ad70ec4617166f1c38e5d2bfd388af71fda14f06` |
| Engine revision | `a10d8ac38de835021c8d2f920dbf50a920ccc030` |
| Patchset | `windows-dcomp-stage-visual` v5 |
| Kirakara Engine ABI | 2 |
| Visual Studio | Visual Studio Community 2026 `18.6.11806.211` |
| MSVC toolset | `14.34.31933`，compiler `19.34.31948.0` |
| Windows SDK | `10.0.22621.0` |
| 本地工作区 | App 仓库下的 `.kfe` |
| 最低空闲空间 | 64 GiB |

构建目录名仍带 `host_*_kirakara_v4`，它只是既有缓存标签；运行时兼容性由导出的
ABI 与 patchset 版本判断，不能根据目录名猜测。

## 3. 本机旧布局不是部署要求

最初研发机器上曾同时存在：

- `D:\Program Files\Flutter`：只读使用的官方 Flutter SDK；
- `E:\Kirakara-Flutter-Engine`：Phase 1～7 使用的外置 Engine 工作区；
- `D:\Kirakara-App-ascii`：早期规避上游路径问题的入口。

这些路径是研发过程遗留，不需要在新机器复刻。Phase 8 已把普通 App 开发收敛到仓库
本地 `.kfe`，并为中文路径加入受锁定和测试覆盖的修复。推荐布局是：

```text
<任意开发目录>\
├─ Kirakara\          # App 仓库
│  └─ .kfe\           # flutterw 自动创建，Git 忽略
└─ Kirakara-Show\     # Show 仓库
```

`.kfe` 内会包含未修改的锁定 Flutter SDK（仅在系统没有匹配 SDK 时）、depot_tools、
Engine 源码、三个模式的输出、项目专用 pub/cache/tmp、日志和 ready stamp。不要在
`flutterw` 运行时手工删除它。

## 4. 新机器前置条件

先安装并确认：

- Windows 10/11 x64；
- Git；
- PowerShell 7，命令名必须为 `pwsh`；
- CMake 3.20 或更新版本；
- Ninja；
- 可用于 Show 的 C++ 工具链；当前已验证 Show 构建使用 MinGW-w64 + Ninja；
- 锁中指定的 Visual Studio Community 2026；
- MSVC `14.34.31933` 的 x86/x64 与 ATL 组件；
- Windows SDK `10.0.22621.0`；
- App 仓库所在磁盘至少 64 GiB 空闲空间。

需要的 MSVC component ID 已写入锁：

```text
Microsoft.VisualStudio.Component.VC.14.34.17.4.x86.x64
Microsoft.VisualStudio.Component.VC.14.34.17.4.ATL
```

Visual Studio 产品、版本、MSVC 或 SDK 不匹配时，脚本会明确拒绝继续。这是发布可复现
合同，不要通过放宽检查或编辑 `engine.lock.json` 绕过。若基础 Visual Studio 已正确
安装而只有旧工具集/ATL 缺失，可在普通 PowerShell 执行：

```powershell
.\engine\scripts\install_pinned_msvc_toolset.ps1 `
  -VisualStudioPath '<Visual Studio 安装目录>'
```

脚本只在实际需要安装组件时请求 UAC。日常构建从非管理员终端开始即可。

## 5. 从 GitHub 建立两个仓库

以下示例使用 HTTPS；已配置 SSH 时可换成对应的 SSH URL。

```powershell
Set-Location '<开发目录>'
git clone https://github.com/FMPeach/Kirakara.git
git clone https://github.com/FMPeach/Kirakara-Show.git

git -C .\Kirakara switch main
git -C .\Kirakara pull --ff-only
git -C .\Kirakara-Show switch main
git -C .\Kirakara-Show pull --ff-only
```

两个仓库都应保持干净。若已经存在本地改动，先报告并保护它们，不要 reset、clean 或覆盖。
当前合成器修复基线至少应包含 App `65641f1` 和 Show `405dd76`：

```powershell
git -C .\Kirakara merge-base --is-ancestor 65641f1 HEAD
git -C .\Kirakara-Show merge-base --is-ancestor 405dd76 HEAD
```

两条命令退出码都应为 0。以后有新提交时，以 `origin/main` 和锁文件为准。

## 6. 先构建并验证 Kirakara Show

App 的新合成路径依赖当前 Show 导出的 Stage Visual API。必须先构建 Show，再把得到的
DLL 作为进程级输入交给 App 构建；否则 App 可能悄悄带上仓库中用于兼容的旧 DLL。

```powershell
Set-Location '<开发目录>\Kirakara-Show'
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
ctest --test-dir build --output-on-failure
```

确认产物存在：

```powershell
Test-Path .\build\bin\libshow_host.dll
Get-FileHash .\build\bin\libshow_host.dll -Algorithm SHA256
```

回到 App 仓库，为当前 PowerShell 进程设置 Show DLL。不要写入用户/机器永久环境变量：

```powershell
Set-Location '<开发目录>\Kirakara'
$env:KIRAKARA_SHOW_HOST_DLL = (
  Resolve-Path '..\Kirakara-Show\build\bin\libshow_host.dll'
).Path

.\engine\scripts\verify_show_host_stage_visual_abi.ps1 `
  -ShowHostDll $env:KIRAKARA_SHOW_HOST_DLL
```

ABI 验证失败时停止，不要继续构建 App，也不要复制旧 DLL 充数。

## 7. 由 flutterw 自举定制 Engine

Windows 开发必须从 App 仓库根目录调用 `flutterw`，不要用裸 `flutter` 代替：

```powershell
Set-Location '<开发目录>\Kirakara'
.\flutterw engine status
.\flutterw engine doctor
.\flutterw engine prepare debug
.\flutterw pub get
```

首次执行会进行严格预检，然后下载/检出锁定版本、应用补丁、构建并验证 Engine。根据网络、
CPU 和存储性能，可能需要几十分钟到数小时。脚本没有输出时不要凭感觉终止，先查看
`.kfe\logs` 和对应进程状态。

网络需要代理时，只为当前 PowerShell 进程设置：

```powershell
$env:KIRAKARA_ENGINE_PROXY = 'http://127.0.0.1:7890'
.\flutterw engine prepare debug
Remove-Item Env:\KIRAKARA_ENGINE_PROXY
```

代理地址仅为示例，必须换成当前机器真实可用的地址。不得把代理或凭据写进仓库。

三个模式按需独立准备：

```powershell
.\flutterw engine prepare debug
.\flutterw engine prepare profile
.\flutterw engine prepare release
```

也可以直接运行普通命令；wrapper 会按模式惰性准备：

```powershell
.\flutterw run -d windows
.\flutterw run -d windows --profile
.\flutterw build windows --release
```

第二次相同命令应复用已经验证的 ready stamp，不再重复 fetch、sync、GN、Ninja 和完整
Engine 构建。如果仍然全量重建，应先查 `.kfe\logs` 中的指纹失配原因。

## 8. 验证 App 实际绑定的 Show 与 Engine

Release 构建完成后，先确认输入 DLL 和 bundle 中 DLL 的哈希一致：

```powershell
$showInput = Get-FileHash $env:KIRAKARA_SHOW_HOST_DLL -Algorithm SHA256
$showBundle = Get-FileHash `
  .\build\windows\x64\runner\Release\libshow_host.dll `
  -Algorithm SHA256
$showInput
$showBundle
if ($showInput.Hash -ne $showBundle.Hash) {
  throw 'App bundle 使用了错误的 libshow_host.dll。'
}
```

然后至少执行：

```powershell
.\flutterw test
git diff --check
git status --short
```

仓库当前存在一个已知业务测试问题：`bilibili_resolver_test.dart` 仍可能期待已经从真实质量
列表移除的 `qn=6`。必须按实际输出区分该既有问题与新增回归，不能把全部失败统称为通过。

运行态还应确认：

- 启动时没有 Engine ABI/patchset 不匹配错误；
- 默认使用 composed Stage 路径；
- 未播放时预览孔为黑色；
- 第一首歌加载后，小于 1080p 的窗口能正确缩放并对齐；
- Flutter 静止时 Stage 继续更新，而 Flutter present 计数不被 Stage 帧泵拖动；
- 窗口缩放、最小化/恢复、双屏和 Cast 基本切换无崩溃。

“能编译”不能替代上述运行验证。

## 9. 清理与重试边界

可用的受控维护命令：

```powershell
.\flutterw engine status
.\flutterw engine doctor
.\flutterw engine clean debug
.\flutterw engine purge
```

- `flutterw clean` 只清 App 构建，不删除 `.kfe` Engine 工作区；
- `engine clean <mode>` 只删除指定模式输出和 ready stamp；
- `engine purge` 只删除当前仓库的 `.kfe`；
- 不要在 wrapper 或构建进程运行时手工删除 `.kfe`；
- 不要用 `git clean` 清理未知内容。

若 App bundle 带入旧 Show DLL，先确认 `KIRAKARA_SHOW_HOST_DLL` 在同一个 PowerShell
进程中设置且指向正确文件，再执行一次 `flutterw clean` 后重建。不要直接覆盖 bundle 来
掩盖 CMake 输入错误。

## 10. 正式 Release 打包

只有 debug/profile/release Engine、Show ABI 和 App 运行验证都完成后，才执行严格发布脚本：

```powershell
.\engine\scripts\package_windows_release.ps1 `
  -FlutterSdkRoot '<锁定 Flutter SDK 根目录>' `
  -WorkspaceRoot '.\.kfe' `
  -ShowHostDll $env:KIRAKARA_SHOW_HOST_DLL `
  -OutputDirectory '<新的空输出目录>'
```

发布脚本会检查锁定的 Release 产物哈希。Windows PE/PDB、链接时间戳或 CodeView 信息可能
导致一次功能正确的新构建与已审核候选并非 bit-for-bit 相同；因此哈希失败时必须停止并
提交候选报告，不能自动更新锁、关闭校验或把新哈希写回 `engine.lock.json`。

需要调整锁或维护 stock/custom A/B 时，阅读 [Engine README](../engine/README.md) 的
“External Engine developer and release workflow”。普通 App 开发不需要外置
`E:\Kirakara-Flutter-Engine`。

## 11. 交接时必须留下的证据

让另一台机器或 AI 完成部署后，至少记录：

- 两个仓库的绝对路径、分支、HEAD 与 `git status --short`；
- `pwsh`、Git、CMake、Ninja、Visual Studio、MSVC、Windows SDK 版本；
- 可用空间与 `.kfe` 实际位置；
- `flutterw engine doctor/status` 输出摘要；
- Show 的 CTest 结果、DLL 路径与 SHA-256；
- Show Stage Visual ABI 验证结果；
- debug/profile/release 中实际完成的模式和 ready stamp；
- App bundle 中 `flutter_windows.dll`、`libshow_host.dll` 的 SHA-256；
- App 测试、运行 smoke 与未验证项；
- 若失败，保留第一处真实错误及相应 `.kfe\logs`，不要只给最后一行退出码。

只有这些证据齐全，才能判断是部署成功、环境不满足，还是仅仅完成了下载/编译。
