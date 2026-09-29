# Phase 8：仓库内自举与项目隔离的定制 Engine

## 当前结论

Phase 8 已把 Phase 1～7 的底层 Engine 脚本收敛为仓库根目录的 `flutterw.ps1` /
`flutterw.cmd` 入口。Windows `pub get`、`run` 和 `build windows` 不再要求开发者手工
建立外部 Engine 工作区或拼接 local-Engine 参数；debug、profile、release 按命令语义
惰性准备，并且只有在源码、补丁、工具链、GN、ABI 和实际产物全部通过门禁后才会写入
ready stamp。

当前 Windows 11 / NVIDIA 主机已经在仓库的真实物理路径
`D:\仓库\Kirakara-App` 完成仓库本地源码获取、补丁、debug/profile/release 构建、ABI
门禁、App 三模式构建和运行门禁，全程没有借助 junction、全局 alias 或短 ASCII 路径。
这次真实中文路径构建依次暴露并修复了 vpython virtualenv 前缀读取、GN 写 Ninja 文件、
Ninja 创建 Windows 子进程、Engine `shader_archiver` 路径转换和 Dart `gen_snapshot` 参数
解码五个独立边界。GN 与 Ninja 现在从锁定 revision 和可审查补丁源码构建，分别通过
736/736 与 396/396 项上游测试；Engine 主仓库和内嵌 Dart 仓库的补丁都能精确反向恢复
stock tree 并重新得到锁定 patched tree。

中途还从一次被中断的干净 App/CMake
依赖下载直接续跑成功，没有清理 `.kfe` 或 App build。随后在子进程 PATH 中完全移除
已安装 Flutter，先观察到 GitHub 直连 reset 和明确失败，再通过仅限进程树的代理自动
获取 `.kfe/sdk`、checkout 锁定 revision、完成 Windows precache 并运行成功；第二次在
无代理环境中 1.397 秒复用，没有再次 clone、precache 或下载。随后同一隔离环境中的
真实 `flutterw pub get` 在 11.354 秒内复用 debug Engine 并完成依赖解析。该结论不替代
计划要求的第二位协作者从全新 clone 独立复现；Phase 7 已按所有者确认的核心实机范围
完成，该独立复现现在只作为 Phase 8 和总计划的未完成门槛。

在此基础上，当前主机又从同一提交 `d708cf7` 建立三份互不共享 `.kfe` 的真正 clean
clone，分别把 `flutterw run -d windows`、`flutterw pub get` 和未指定模式的
`flutterw build windows` 作为第一次命令。三轮都完成源码获取、GN 736/736、Ninja
396/396、目标 Engine 构建、ABI 门禁和 Flutter 子命令；需要运行证明的两轮均核对了
Engine 输出、App bundle 与进程实际加载 DLL 的同一 SHA-256。相同命令第二次均未出现
fetch、gclient sync、GN、Ninja 或 Engine build。clean clone 过程另外发现并修复了三个
此前排列测试没有覆盖的问题：现代 depot_tools 的 uv-based vpython 空缓存初始化、
PowerShell 把 Flutter 短参数 `-d` 误绑定为 common parameter，以及锁定 Engine 构建所用
`VCToolsVersion` 泄漏到随后 App CMake 配置。最终三轮 App 均使用 Visual Studio 2026 /
MSVC 14.51，`MSB8052` 计数为 0。当前主机的 clean-clone 门禁因此已经完成；第二位协作者
复现仍是不能由同机自证替代的剩余发布门槛。

Phase 7 之后的发布边界也已补齐：普通 clean clone 不再依赖机器上的 Show checkout，默认
构建确定性携带仓库内既有 external-texture 兼容 DLL；真实 composed probe 和发布打包则
必须选择通过版本化 Stage Visual ABI 门禁的当前 Show DLL。仓库本地 Unicode-safe
Release Engine 已作为独立 `projectBootstrap.releaseCandidate` 锁定并通过四归档打包、
Portable/Installer 运行及无 UAC 安装卸载。历史外部候选仍保留用于 A/B，不被新候选
覆盖。二进制、PDB 与 ZIP 只留在 `.kfe`/`build` 或后续 Release 资产，不进入 Git。

## 仓库入口与模式选择

日常 Windows 开发只使用：

```powershell
.\flutterw pub get
.\flutterw run -d windows
.\flutterw run -d windows --profile
.\flutterw build windows
```

入口保留 Flutter 的参数语义：

- `pub get` 先准备 debug Engine，再执行依赖解析；
- Windows `run` 默认为 debug，显式 `--profile` / `--release` 选择对应模式；
- `build windows` 未指定模式时按 Flutter 规则选择 release；
- 明确的非 Windows device 不准备也不注入定制 Windows Engine；
- 调用者显式传入 `--local-engine`、`--local-engine-host` 或
  `--local-engine-src-path` 会被拒绝，避免绕过同一状态机。

匹配模式就绪后，入口自动传入三个 local-Engine 参数。切换模式前会比较选择的 Engine
输出与 Flutter 生成的 `windows/flutter/ephemeral`；若发现上一次模式留下的 DLL、
import library、ICU 或头文件不一致，只删除 Flutter 可再生的精确 DLL sentinel，让
官方 Flutter assemble 重新生成整套 ephemeral 内容。脚本不手工复制 DLL，也不广泛
清理 App 构建目录。

## 隔离布局与环境边界

所有项目专属的源码、输出、下载缓存、临时文件、日志、锁和状态都位于被 Git 整体忽略
的 `.kfe/`。入口优先只读使用 revision 完全匹配的普通官方 Flutter SDK；没有匹配 SDK
时才把锁定的官方原版 SDK 放到 `.kfe/sdk`。Engine 补丁只应用于 `.kfe/engine`，不会
修改已安装 Flutter SDK 或其 cache。

`PUB_CACHE`、CIPD/vpython cache、`TEMP`、`TMP`、depot_tools 路径和代理只在 wrapper
子进程环境中设置。`flutterw.ps1` 在退出前按名称和值恢复调用进程的完整环境；自动测试
同时核对用户/系统环境、全局 Git 配置哈希和外部官方 Flutter SDK tracked 状态。脚本
不写 PATH、注册表、服务、计划任务、junction 或全局 alias。

`KIRAKARA_ENGINE_PROXY` 会转换为同一进程树内的 HTTP/HTTPS 代理，不仅覆盖 Engine
fetch，也覆盖备用 Flutter SDK、Flutter tool 和 CMake 第三方依赖下载。一次
`flutterw clean` 后的 sqlite CMake 下载先因该传递缺口被中止；修正后从原中间状态
直接完成，证明失败路径不会要求人工删目录。代理地址不写入报告、Git 或持久配置。

`projectBootstrap.maxLogFiles` 把 `.kfe/logs` 限制为有界集合；裁剪时始终保护三个当前
ready stamp 引用的 verification/ABI 报告。日志记录路径、哈希、模式、错误和耗时，不
记录剪贴板文本或代理值。

## 中文路径工具链补丁

仓库可以位于非 ASCII 路径，不要求开发者创建映射盘或英文路径副本。锁文件额外固定
以下小型补丁栈及其输入/输出哈希：

- vpython virtualenv 以 UTF-8 读写解释器前缀；
- GN 在 Windows 通过 Unicode 安全的原子写入生成 Ninja 文件；
- Ninja 将 UTF-8 命令行转换后调用 `CreateProcessW`；
- `shader_archiver` 把 `std::filesystem::path` 明确转换为 UTF-8 后交给 FML；
- 内嵌 Dart 的 `gen_snapshot` 在 Windows 把宽字符命令行转换为 UTF-8 argv。

内嵌依赖补丁和 Engine 主仓库补丁采用相同的 stock/patched tree 门禁，不能在依赖仓库
存在未知 tracked 修改时继续。`test_project_engine_unicode_paths.ps1` 会在 `.kfe/tmp` 的
真实中文目录中分别运行 `shader_archiver` 和 `gen_snapshot`，检查产物后只删除这一个
已验证位于项目临时根目录内的探针目录。

## 指纹、并发与中断恢复

每个模式的指纹包含 Framework/Engine revision、目标 OS/架构、stock 与 patched source
tree、补丁栈及哈希、ABI/patchset 版本、GN/Ninja 配置、MSVC/Windows SDK 身份、关键
脚本和 wrapper 内容。普通 Dart、资源或业务代码不在指纹中。ready stamp 还锁定本次
开发构建的实际产物集合、大小与非 PDB 文件哈希；PDB 只做存在和大小门禁，避免链接器
identity 的非确定性导致锁文件被自动改写。Phase 7 发布候选的精确哈希门禁保持不变。
指纹使用剔除所有精确产物列表和 `projectBootstrap.releaseCandidate` 后的规范化构建锁；
因此只更新人工审核的发布哈希不会令三种开发模式失效，而 revision、source tree、补丁、
GN target/参数、ABI、工具链或构建脚本变化仍会改变指纹。聚焦测试同时验证这两个方向。

同一仓库身份映射到一个 Windows named mutex。锁外先做廉价复用检查；需要准备时取得
互斥锁并再次检查，因此同时启动的第二个进程会等待第一个完成，然后复验并复用，不会
并发 fetch、patch 或写同一输出。

中断后没有完整 ready stamp 的输出不会交给 Flutter。仓库本地获取脚本可以：

- 删除仅位于预期 `.kfe` 子路径、且尚无 Git metadata 的中断 clone 后重新获取；
- 对来源完全匹配、没有 tracked 修改的 checkout 续拉并 detached checkout 到锁定
  revision；
- 对来源不同或存在 tracked 修改的目录明确失败，不执行 reset 或覆盖；
- 复用 Ninja 的已完成目标继续编译，全部门禁通过后才原子替换 ready stamp。

## 清理与兼容入口

```powershell
.\flutterw engine status
.\flutterw engine doctor
.\flutterw engine prepare debug
.\flutterw engine clean debug
.\flutterw engine purge
```

`engine clean <mode>` 只删除 `.kfe/out` 中精确的该模式目录和 ready stamp；`engine
purge` 只删除当前仓库的 `.kfe`。二者使用同一个互斥锁。普通 `flutterw clean` 仍是
Flutter App clean，不删除 Engine 工作区。原有 `engine/scripts/*.ps1` 继续支持显式
外部 workspace，用于官方/custom A/B、Engine 开发和 Phase 7 发布候选打包。

VS Code task 和 launch 示例调用相同的 `flutterw` 入口；Dart 调试器通过单独 attach
连接，不另造绕过 ABI 门禁的启动流程。裸 `flutter` 不被劫持，因而相邻普通 Flutter
仓库仍使用自己的 SDK、cache、参数和官方 Engine。根目录双击入口所调用的四个 Windows
批处理也从 `%~dp0` 解析当前 clone，并统一经过 `flutterw.cmd`；它们不再绑定旧仓库盘符或
`D:\Program Files\Flutter`。直接启动 Debug EXE 的入口会先执行一次增量 debug build，
防止脚本更新、模式切换或 Engine 更新后绕过 ready-stamp 和 bundle 门禁。

## 当前主机验证

下列门禁已在本机执行：

| 门禁 | 当前结果 |
| --- | --- |
| wrapper 命令推导、冲突拒绝、指纹、ready stamp 损坏 | 通过 |
| 双击构建/启动入口的项目隔离 | 通过；四个批处理使用相对仓库根和 `flutterw.cmd`，无固定 SDK/仓库路径 |
| stale ephemeral Engine 检测 | 通过 |
| 有界日志及当前报告保护 | 通过 |
| 中断目录恢复、干净 checkout 续拉、dirty checkout 拒绝 | 通过 |
| 两个并发 debug prepare | 一个构建/验证，另一个等待后复用 |
| process/user/machine 环境、全局 Git、官方 SDK 隔离 | 通过 |
| PATH 无匹配 SDK 时自动获取 `.kfe/sdk` | 通过；直连失败明确退出，进程代理重试成功 |
| `.kfe/sdk` 第二次无代理复用 | 通过；1.397 s，无 clone/precache/download |
| `.kfe/sdk` 执行 `flutterw pub get` | 通过；真实中文路径 11.354 s，复用 verified debug Engine |
| 锁定 GN / Ninja 源码构建与上游测试 | 通过；736/736 与 396/396 |
| Engine 主仓库和 Dart 依赖补丁反向/重放 | 通过；精确得到锁定 stock/patched tree |
| 中文临时目录工具探针 | 通过；`shader_archiver` 与 `gen_snapshot` 均退出 0 并产生有效输出 |
| debug/profile/release Engine 与 ABI | 三模式通过，错误 ABI/结构大小均返回明确 version mismatch |
| debug/profile/release App build 与 GUI smoke | 三模式均加载对应 DLL、响应、正常关闭且退出码 0 |
| 第二次命令不 fetch/sync/GN/Ninja | 通过；10.094 s / 9.830 s / 9.841 s |
| `flutterw clean` 保留 `.kfe` | 通过；App build 被清除，三模式 stamp 与 DLL 哈希不变 |
| 三份独立 clean clone 的第一次命令 | 通过；debug `run` / `pub get` / 默认 release `build windows` 均从空 `.kfe` 完成 |
| clean clone 的实际运行 DLL 与 ABI | 通过；bundle/loaded/Engine SHA-256 一致，ABI 2、patchset 4、锁定 Engine revision |
| clean clone 的 App 工具链隔离 | 通过；VS 2026 / MSVC 14.51，三轮 `MSB8052` 均为 0 |
| clean clone 的第二次相同命令 | 通过；无 fetch/sync/GN/Ninja/Engine build，并复用各自 verified ready stamp |
| 默认 Show 构建输入隔离 | 通过；撤销进程覆盖后 CMake cache 和 Debug bundle 都恢复仓库内兼容 DLL |
| 当前 Show Stage Visual ABI | 通过；ABI 1、能力 `0xF`、协议、保留位、函数表和 D3D device binding 均匹配 |
| 仓库本地严格 Release 打包 | 通过；四个归档、locked smoke、安装/卸载与隐私扫描均通过 |

当前仓库本地开发 DLL（开发态 ready stamp 的实际哈希，不改写 Phase 7 release lock）：

| 模式 | `flutter_windows.dll` SHA-256 | 大小 |
| --- | --- | ---: |
| debug | `4D3DA24999D235B38BCE2948A7C271C9B57BB6A703496A0190575E514C2190B1` | 45,583,872 |
| profile | `A135150C9BF3C7A3ECF01A0EDB23784FDF4E37A12ACF173F1BDE0EB74465BD26` | 21,899,776 |
| release | `DB07763F1551A8FD68346D30A547050975E14E73A79B1A239587F063CD70B0F8` | 21,316,608 |

三份独立 clean clone 的最终证据：

| 第一次入口 | 冷启动耗时 | 第二次耗时 | 实际 Engine / bundle / loaded DLL SHA-256 |
| --- | ---: | ---: | --- |
| `flutterw run -d windows` | 1412.220 s | 43.654 s（含运行检查；App build 9.3 s） | `75B7E0CA427C807B49CC9D9CD2BD9CD7C9290D2318FC30BA16C6D9803952A067` |
| `flutterw pub get` | 1310.307 s | 14.403 s | `95EF78BE8635A81C3FDB463D8162256ABDE0640B10E3EB4BC3FF69541CC4808F`；随后 `run` 实际加载确认 |
| `flutterw build windows` | 1353.412 s | 27.927 s（Flutter App build 15.9 s） | `DFDA92EB62138B6636B03F7237CB7447F85077834C8377B0BEBE96F4A5024308F`；Release 进程实际加载确认 |

这些开发构建的 PE/PDB 和 `gen_snapshot` 不承诺跨次 bit-for-bit 一致，因此三轮 DLL 哈希
彼此不同、也不同于 Phase 7 人工审核的 release lock；每轮都把自身实际产物写入 ready
stamp，并在第二次入口和 bundle/load 边界复验，且没有自动改写 `engine.lock.json`。
clean clone 使用 Windows 默认 CRLF checkout，主工作区保留 LF；指纹按工作树实际字节
计算，所以两种 checkout 的指纹不同，但三份证据均记录同一 Git HEAD，不能据此跨工作区
互换 ready stamp。

关键报告：

- `build/diagnostics/engine/project-bootstrap-tests-20260929-095102.json`；
- `build/diagnostics/engine/flutterw-local-sdk-fallback-20260929-044316.json`；
- `build/diagnostics/engine/flutterw-local-sdk-fallback-20260929-044440.json`；
- `build/diagnostics/engine/project-engine-reuse-20260929-044304.json`；
- `build/diagnostics/engine/project-app-bundles-20260929-083630.json`；
- `build/diagnostics/engine/flutterw-isolation-20260929-044318.json`；
- `build/diagnostics/engine/flutterw-clean-boundary-20260929-043715.json`；
- `build/diagnostics/engine/project-engine-unicode-paths-20260929-044327.json`；
- `build/diagnostics/engine/app-smoke-local-patched-debug-20260929-083647.json`；
- `build/diagnostics/engine/app-smoke-local-patched-profile-20260929-083708.json`；
- `build/diagnostics/engine/app-smoke-local-patched-release-20260929-083729.json`；
- `build/diagnostics/engine/patched-engine-tests-20260929-044547.json`；
- `build/diagnostics/synthetic-compositor-20260929-044729.json`；
- `.kfe/logs/verify-debug-20260929-064833-44113229.json` 与对应 ABI 报告；
- `.kfe/logs/verify-profile-20260929-083013-98db71f9.json` 与对应 ABI 报告；
- `.kfe/logs/verify-release-20260929-083210-4d8e825b.json` 与对应 ABI 报告；
- `.kfe/logs/verify-debug-20260929-092207-3f2f6f48.json`、
  `verify-profile-20260929-092409-8edd0da2.json`、
  `verify-release-20260929-092609-e224dd75.json` 与各自 ABI 报告；
- `build/diagnostics/engine/clean-clone-evidence/debug-run-final-summary.json`；
- `build/diagnostics/engine/clean-clone-evidence/pub-get-final-summary.json`；
- `build/diagnostics/engine/clean-clone-evidence/release-build-final-summary.json`；
- `build/diagnostics/engine/clean-clone-evidence/debug-run-toolchain-restore-integration.json`；
- `build/diagnostics/real-stage-lifecycle-20260929-094629.json`；
- `build/diagnostics/release-show-gate-final-clean-a-20260929/` 下的 release index 与两份
  smoke 报告，以及 `release-show-gate-final-clean-b-20260929/` 的确定性打包对照。

Engine 聚焦回归为 compositor API 6、剪贴板 19、关键调度 2、上游 compositor 25 和
两个隔离 adapter 测试全部通过。最终真实 Show 复验中，交互后的静止 2 秒样本 Stage
submit/present 各推进 120 帧而 Flutter present 增量为 0；750 ms 观察窗 Stage 继续推进
45 帧且 Flutter present 增量仍为 0。最小化/恢复、会话/电源信号、快速导航、Show 重建
及 active 状态退出全部通过，所有 Stage HRESULT/device-removal 计数正常。

锁定 SDK 的 `dart analyze` 在真实中文路径保持仓库既有 68 条 info、0 warning、0 error。
同版本 stock `flutter analyze`（包括绕过 wrapper 直接调用官方 SDK）会因 Flutter tool 以
Dart 字符数而非 UTF-8 字节数填写 LSP `Content-Length`，在中文 workspace URI 处令
analysis server 以退出码 255 拒绝截断 JSON；这是官方 Flutter 3.44.4 工具层问题，不是
定制 Engine 回归。这里没有修改官方 SDK，也没有用 junction 掩盖它；Phase 8 规定的
`pub get`、Windows `run` 与 `build` 入口不受影响。完整 `flutter test` 保持 94 通过、
1 个既有失败：`bilibili_resolver_test.dart` 仍期待已从实际质量列表移除的 `qn=6`；本阶段
没有借机修改该业务断言。并行执行 analyze/test 时曾令一个资源抢占时序测试额外失败，
该用例单独及串行全套复跑均通过，未作为稳定回归记录。

仓库所有者随后明确该中文路径属于当前机器的特殊条件，不要求继续扩展 stock Flutter 的
兼容范围。已有 wrapper/custom Engine 的 Unicode 修复与测试继续保留；stock
`flutter analyze` 的工具缺陷只作信息记录，不作为 Phase 8 或发布退出条件。当前全套回归
因新增 LAN smoke 和 4 项 compositor-clock cadence 单测增至 102 通过、仍只有同一个
`qn=6` 既有失败。

开发态验证产生的 DLL/PDB、Engine 源码、缓存和 ready stamp 都留在 `.kfe` 或忽略的
App build 目录，不进入普通 Git。提交前还会检查 Git tracked 文件集和源码包排除规则。

## 尚需第二位协作者验证

本机已在三份互不共享 `.kfe` 的 clean clone 中完成以下首次入口，但同一 Windows 主机、
同一 VS/SDK 和同一网络环境不能替代独立协作者复现。因此仍需另一位协作者在新 clone 中
至少完整执行一轮，并建议依次覆盖：

1. `flutterw pub get` 作为第一次命令；
2. `flutterw run -d windows` 作为第一次命令；
3. `flutterw build windows` 作为第一次命令。

协作者应记录实际加载 DLL 的 SHA-256、ABI/patchset/Engine revision、第一次阶段输出、
第二次廉价复用输出、仓库外环境/SDK/Git 配置前后差异以及清理边界。若共享已有 `.kfe`，
只能算入口排列回归，不能算独立复现。当前可用的三台外部机器都曾安装 Flutter，仓库
所有者决定暂不验收；第二位协作者复现完成前，Phase 8 和总计划仍不能宣称完全结束，
但 Phase 7 不因此回退。
