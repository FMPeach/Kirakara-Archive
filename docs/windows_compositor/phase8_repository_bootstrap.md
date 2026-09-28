# Phase 8：仓库内自举与项目隔离的定制 Engine

## 当前结论

Phase 8 已把 Phase 1～7 的底层 Engine 脚本收敛为仓库根目录的 `flutterw.ps1` /
`flutterw.cmd` 入口。Windows `pub get`、`run` 和 `build windows` 不再要求开发者手工
建立外部 Engine 工作区或拼接 local-Engine 参数；debug、profile、release 按命令语义
惰性准备，并且只有在源码、补丁、工具链、GN、ABI 和实际产物全部通过门禁后才会写入
ready stamp。

当前 Windows 11 / NVIDIA 主机已经完成仓库本地源码获取、补丁、debug/profile/release
构建、ABI 门禁、App 三模式构建和运行门禁。中途还从一次被中断的干净 App/CMake
依赖下载直接续跑成功，没有清理 `.kfe` 或 App build。该结论不替代计划要求的第二位
协作者从全新 clone 独立复现；后者仍同时是 Phase 7 和 Phase 8 未完成的发布门槛。

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

## 指纹、并发与中断恢复

每个模式的指纹包含 Framework/Engine revision、目标 OS/架构、stock 与 patched source
tree、补丁栈及哈希、ABI/patchset 版本、GN/Ninja 配置、MSVC/Windows SDK 身份、关键
脚本和 wrapper 内容。普通 Dart、资源或业务代码不在指纹中。ready stamp 还锁定本次
开发构建的实际产物集合、大小与非 PDB 文件哈希；PDB 只做存在和大小门禁，避免链接器
identity 的非确定性导致锁文件被自动改写。Phase 7 发布候选的精确哈希门禁保持不变。

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
仓库仍使用自己的 SDK、cache、参数和官方 Engine。

## 当前主机验证

下列门禁已在本机执行：

| 门禁 | 当前结果 |
| --- | --- |
| wrapper 命令推导、冲突拒绝、指纹、ready stamp 损坏 | 通过 |
| stale ephemeral Engine 检测 | 通过 |
| 有界日志及当前报告保护 | 通过 |
| 中断目录恢复、干净 checkout 续拉、dirty checkout 拒绝 | 通过 |
| 两个并发 debug prepare | 一个构建/验证，另一个等待后复用 |
| process/user/machine 环境、全局 Git、官方 SDK 隔离 | 通过 |
| debug/profile/release Engine 与 ABI | 三模式通过，错误 ABI/结构大小均返回明确 version mismatch |
| debug/profile/release App build 与 GUI smoke | 三模式均加载对应 DLL、响应、正常关闭且退出码 0 |
| 第二次命令不 fetch/sync/GN/Ninja | 通过；4.366 s / 3.719 s / 3.690 s |
| `flutterw clean` 保留 `.kfe` | 通过；App build 被清除，三模式 stamp 与 DLL 哈希不变 |

当前仓库本地开发 DLL（开发态 ready stamp 的实际哈希，不改写 Phase 7 release lock）：

| 模式 | `flutter_windows.dll` SHA-256 | 大小 |
| --- | --- | ---: |
| debug | `5E845FC14F5345660FAD7D81042457E90139044D3601F9DBBF9A3FB4F203A9EC` | 45,583,872 |
| profile | `FEA2EC410224044DC4A70B27AB9FB4795A6A308F33FC2E37AD0F2CD0ECA5287C` | 21,899,776 |
| release | `1EF827FA6ABAEBF1735DF7C72389D9178A1F4263D2D074D6FF62A83FC900DCFF` | 21,316,608 |

关键报告：

- `build/diagnostics/engine/project-bootstrap-tests-20260929-005239.json`；
- `build/diagnostics/engine/project-engine-reuse-20260929-005735.json`；
- `build/diagnostics/engine/project-app-bundles-20260929-005954.json`；
- `build/diagnostics/engine/phase8-project-abi.json`；
- `build/diagnostics/engine/flutterw-isolation-20260929-005725.json`；
- `build/diagnostics/engine/flutterw-clean-boundary-20260929-004757.json`；
- `build/diagnostics/engine/patched-engine-tests-20260929-005832.json`；
- `build/diagnostics/synthetic-compositor-20260929-005851.json`；
- `build/diagnostics/engine/app-smoke-local-patched-debug-20260929-010000.json`；
- `build/diagnostics/engine/app-smoke-local-patched-profile-20260929-005801.json`；
- `build/diagnostics/engine/app-smoke-local-patched-release-20260929-005810.json`。

Engine 聚焦回归为 compositor API 6、剪贴板 19、关键调度 2、上游 compositor 25 和
两个隔离 adapter 测试全部通过。synthetic 复验中 platform thread stall 750 ms 时
Stage 推进 45 帧而 Flutter present 增量为 0；交互后的静止 2 秒样本 Stage 推进 120
帧且 Flutter present 增量为 0，所有 Stage HRESULT/device-removal 计数正常。

`flutter analyze` 保持仓库既有 68 条 info、0 warning、0 error。完整 `flutter test`
保持 94 通过、1 个既有失败：`bilibili_resolver_test.dart` 仍期待已从实际质量列表移除的
`qn=6`；本阶段没有借机修改该业务断言。

开发态验证产生的 DLL/PDB、Engine 源码、缓存和 ready stamp 都留在 `.kfe` 或忽略的
App build 目录，不进入普通 Git。提交前还会检查 Git tracked 文件集和源码包排除规则。

## 尚需独立验证

本机一次真实的源码获取与三模式构建可以证明状态机和产物门禁，但不能冒充三份真正
独立的 clean clone，也不能替代第二位协作者。因此仍需在另一份新 clone/另一位协作者
环境分别记录以下首次入口：

1. `flutterw pub get` 作为第一次命令；
2. `flutterw run -d windows` 作为第一次命令；
3. `flutterw build windows` 作为第一次命令。

每轮都应记录实际加载 DLL 的 SHA-256、ABI/patchset/Engine revision、第一次阶段输出、
第二次廉价复用输出、仓库外环境/SDK/Git 配置前后差异以及清理边界。若共享同一
`.kfe`，只能算入口排列回归，不能算三次 clean-clone 证据。第二位协作者复现完成前，
Phase 7/8 和总计划仍不能宣称完全结束。
