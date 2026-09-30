# 给另一台 Windows 机器上 AI 的部署提示词

把下面整段复制给另一台机器上的 AI。先把尖括号中的路径和可选代理改成真实值。

```text
请在这台 Windows 机器上部署并验证 Kirakara 的仓库本地定制 Flutter Engine 开发环境。

源码只从 GitHub 获取，不要把网络盘当源码仓库：
- App：https://github.com/FMPeach/Kirakara.git
- Show：https://github.com/FMPeach/Kirakara-Show.git

期望目录：
- App：<APP_REPO_PATH>
- Show：<SHOW_REPO_PATH>
- 可选进程级代理：<PROXY_URL；不需要时留空>

先完整阅读：
1. App/docs/windows_custom_flutter_engine_deployment.md
2. App/engine/README.md
3. App/engine/engine.lock.json
4. App/docs/windows_compositor/phase8_repository_bootstrap.md

工作规则：
- 先做只读预检，再修改或安装任何内容。
- 若仓库已存在，检查分支、HEAD、remote、git status，并只用 git pull --ff-only 更新。
- 保护所有现有改动；不得 git reset --hard、git clean 或覆盖用户文件。
- 源码仓库只走 GitHub。网络盘只允许读取已打好的 Release 包，不得向其中复制仓库。
- 普通 App 开发必须使用仓库根目录的 flutterw 和忽略的 .kfe 工作区。
- 不要复刻旧机器的 D:\Program Files\Flutter、E:\Kirakara-Flutter-Engine 或 ASCII junction。
- 不要修改系统 Flutter SDK，不要向其 cache 复制 DLL，不做二进制 patch/hook。
- 不要提交 .kfe、Engine 源码、构建缓存、DLL 或 PDB。
- 不要放宽 engine.lock.json 的版本、工具链、ABI 或哈希检查。
- 不要自动更新锁文件；任何 relock 必须先得到用户明确同意。
- 只在安装锁定 MSVC/ATL 确实需要时触发 UAC；其余步骤用普通 PowerShell 7。
- 环境不满足时报告准确差异，不要猜测成功，也不要用回退掩盖错误。

按以下顺序执行：

A. 只读预检
- 确认 Windows x64、磁盘剩余空间至少 64 GiB。
- 记录 pwsh、Git、CMake、Ninja、Visual Studio、MSVC 与 Windows SDK 版本。
- 从 engine.lock.json 读取当前真实锁值；不要只信提示词里的版本摘录。
- 确认 Visual Studio 产品/版本、MSVC 14.34.31933、ATL 和 Windows SDK 10.0.22621.0。
- 如果只缺锁定 MSVC/ATL，可使用 engine/scripts/install_pinned_msvc_toolset.ps1；如果基础 VS 产品或精确版本不匹配，先停下并报告，不要改锁绕过。

B. 获取或更新源码
- clone 两个 GitHub 仓库，或在现有干净仓库上 checkout main 后 pull --ff-only。
- 记录两个 HEAD。App 至少包含 65641f1；Show 至少包含 405dd76。
- 用 git merge-base --is-ancestor 验证，不要强行切走用户分支上的工作。

C. 构建 Show
- 在 Show 仓库用 Ninja Release 配置：
  cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
  cmake --build build
  ctest --test-dir build --output-on-failure
- 确认 build/bin/libshow_host.dll 存在并记录 SHA-256。
- 不修改 Show 的歌词解析、时钟、物理 Stage 或 Cast 语义。

D. 绑定正确的 Show DLL
- 在准备构建 App 的同一个 PowerShell 进程中设置：
  $env:KIRAKARA_SHOW_HOST_DLL = (Resolve-Path '<SHOW_REPO_PATH>\build\bin\libshow_host.dll').Path
- 在 App 仓库执行：
  .\engine\scripts\verify_show_host_stage_visual_abi.ps1 -ShowHostDll $env:KIRAKARA_SHOW_HOST_DLL
- ABI 失败立即停止，不要使用仓库内旧兼容 DLL 继续。

E. 部署仓库本地 Engine
- 只从 App 仓库根目录执行 .\flutterw，不要使用裸 flutter 命令完成 Windows 构建。
- 若提供了代理，只在当前 PowerShell 进程设置 KIRAKARA_ENGINE_PROXY，结束后删除该环境变量；不得持久化代理或凭据。
- 先执行：
  .\flutterw engine status
  .\flutterw engine doctor
  .\flutterw engine prepare debug
  .\flutterw pub get
- debug 成功后执行运行 smoke：
  .\flutterw run -d windows
- 然后按可用时间继续准备并验证：
  .\flutterw engine prepare profile
  .\flutterw run -d windows --profile
  .\flutterw engine prepare release
  .\flutterw build windows --release
- 首次自举可能需几十分钟到数小时。持续查看真实进程和 .kfe/logs，不要因为短暂无输出就删除 .kfe 或重开多个并行 bootstrap。
- 第二次相同命令应复用 ready stamp；若全量重建，查清指纹不匹配原因。

F. 验证实际 bundle
- 比较 KIRAKARA_SHOW_HOST_DLL 与 build/windows/x64/runner/Release/libshow_host.dll 的 SHA-256，必须一致。
- 记录 bundle 中 flutter_windows.dll 与 libshow_host.dll 的路径和 SHA-256。
- 执行 .\flutterw test、git diff --check、git status --short。
- 如 bilibili_resolver_test.dart 仅因既有 qn=6 期望失败，要单独如实记录；不得把它忽略后宣称零失败，也不得借部署任务修改业务断言。
- 启动 App，验证默认 composed Stage 路径、未播放黑底、第一首歌加载、小窗口缩放对齐、窗口缩放/最小化恢复，以及静止 Flutter 不随 Stage 帧泵持续 present。
- 能接触真实环境时再验证物理双屏和 Cast；无法实测的项目明确列为未验证。

G. 打包边界
- 本任务首先要求开发环境和运行 smoke，不因“能编译”就宣告完成。
- 仅在用户明确要求正式打包时运行 package_windows_release.ps1。
- 若严格 Release 哈希不匹配，保留候选报告并停止；不要自动 relock、跳过校验或手工散装 DLL。
- 如果用户只是要运行现成版本，让其从网络盘取 *-portable.zip 到本地解压；不要把 engine-artifacts.zip 当开发环境安装包。

最后用中文给出一份证据化报告，包含：
1. 两个仓库路径、remote、分支、HEAD、工作区状态；
2. 主机工具链与锁值逐项对照；
3. .kfe 路径、占用空间、完成的 Engine 模式与 ready stamp；
4. Show CTest、Stage Visual ABI、Show DLL SHA-256；
5. App 测试、运行 smoke、bundle DLL SHA-256；
6. 已验证、未验证、需要实体机继续验证的项目；
7. 任何失败的第一处真实错误和对应日志路径。

除非遇到确实会改变结果的缺失选择，否则请持续推进到当前机器可靠可验证的最远阶段；不要反复向用户询问普通实现细节。
```

如果另一台机器只需体验成品，不要使用这份完整提示词；直接复制并解压 Release 的
`*-portable.zip`，运行其中的 `kirakara_app.exe` 即可。
