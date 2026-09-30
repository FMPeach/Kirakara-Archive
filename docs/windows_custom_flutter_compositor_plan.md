# Kirakara Windows 定制 Flutter 合成器计划

## 当前状态

- Phase 0 已完成；源码/工具链/官方 Engine 校验值、stock 三种模式构建、Show
  CTest、真实 external texture integration smoke 与 20 秒 Show texture-only soak
  已冻结，详见 `docs/windows_compositor/phase0_baseline.md`。标准 Clipboard Unicode
  smoke 作为独立轨道冻结在 `docs/windows_clipboard/phase0_baseline.md`。
- Show 与 App 的同 QPC、带 generation/frame ID 的 ETW provider、有时长上限的
  WPR 脚本和源码离线分析器已实现。180 Hz 管理员有效 ETL 的稳定区间闭合了 1097
  条 `StagePublish -> texture callback -> acquire -> 主窗口 DXGKRNL Present ->
  displayed` 链，0 dropped；全窗口唯一未直接归属的 source/present 位于 WPR 启动
  扰动。PresentMon 在 warm-up 后解析 1210 次窗口 Present。该结论使用 raster acquire、
  kernel Present 和 DWM displayed 证据，不以异步 callback 计数代替真实边界。
- 同一 i5-12600K + RTX 4060 Ti、1920×1080 输出随后切换到 60 Hz 采集对照。
  1149 个稳定源帧中，180 个在 notification 之后、advanced acquire 之前被后续
  latest frame 取代，另有 51 个已进入 Present 的唯一源帧被 DWM drop；Show publish
  周期均值 16.6668 ms、最大 20.1034 ms。该样本支持“两个 60 Hz 调度相位使帧被
  合并”的判断，不支持 Show producer 本身长停顿。具体 frame 1315/1316 事件链及
  源帧/窗口 Present 的独立统计见 `phase0_baseline.md`。
- 第二份同场景 60 Hz 样本中，Show 周期均值仍为 16.6666 ms、最大 20.5714 ms；
  1100 个稳定源帧改为 46 个 acquire 前合帧、243 个 DWM drop、811 displayed。
  两次各自缺失的显示周期都精确等于这两类具体 frame ID 之和，但损失发生位置明显
  转移，说明不能把单次掉帧百分比当成稳定性能指标；后续门槛是 Stage 更新不再驱动
  Flutter raster/present。
- 180 Hz 稳定区间仍为 1097 个源帧全部 acquire、全部 displayed；其 displayed
  interval 分布在约 5.56/11.11/16.67/22.22/27.78 ms。三份样本证明刷新模式会改变
  当前路径的 cadence，但不能外推为 Iris Xe 的观感或热稳定结论。
- Phase 0 的静止端到端基线已经冻结，打开/关闭面板、全屏预览、物理双屏、Cast、
  59.94 Hz 与 Iris Xe 留在兼容矩阵，不再阻塞后续阶段。
- Phase 1 已完成：外部工作区中的未修改 Engine 与 Flutter `3.44.4`、Framework
  `ad70ec4617166f1c38e5d2bfd388af71fda14f06`、Engine
  `a10d8ac38de835021c8d2f920dbf50a920ccc030` 精确匹配；空补丁栈、depot_tools、
  GN 参数、MSVC 14.34/ATL 和 debug/profile/release 产物已写入
  `engine/engine.lock.json`。官方/本地三模式 DLL 均为 102 个导出且零差异，严格
  产物校验通过。stock Windows Engine 不是 bit-for-bit 可重建，锁中 SHA-256
  绑定本次已验证分发候选；重建必须走候选报告、人工重锁和完整门槛。
- 官方/本地 debug 与 profile 都通过真实 Show external texture A/B 和 bundle 文件
  校验；60 Hz 的短窗口会在 60/60 与 60/53～55 callback/acquire 之间相位波动，
  与 Phase 0 结论一致。Phase 1 当时官方/本地 release 的烟测都曾被记录为标准 close
  后 20 秒未退出；Phase 7 已证明这是测试脚本在超时 `WaitForExit` 后没有刷新变化过的
  主窗口句柄，而不是 App/Engine 生命周期差异。修正后官方与 custom Release 均在约
  170 ms 内退出、退出码 0 且无需强制清理。Phase 1 原始报告保留为历史，当前结论见
  `docs/windows_compositor/phase7_compatibility_release.md`。
- Phase 2 实现与当前硬件门槛完成：已加入锁定的 `windows-dcomp-synthetic` v2 源码补丁、版本化 ABI、
  单顶层 HWND 双 Visual DirectComposition、预乘 Alpha Flutter 上层、独立合成 D3D
  Stage producer、自动计数门槛和人工检查 harness。定制 debug Engine 的源码树、
  产物、官方导出兼容性与 31 项常规测试加 2 项 adapter 独立测试均已通过；stock
  与 patched 源码/产物切换也已闭环验证。
- 显示器点亮后连续两次自动探针均通过：两秒静止 UI 内 Stage `+120`、Flutter `+0`；
  750 ms platform-thread stall 内 Stage `+45`、Flutter `+0`，证明下层更新不重泵
  Flutter，且 Flutter 短暂卡顿不阻塞 Stage producer。屏幕关闭样本则明确返回
  `STATUS_GRAPHICS_PRESENT_OCCLUDED`，探针按设计失败且未进入轮询。100% DPI 下的
  Alpha 透明孔、圆角、半透明遮罩、独立页面、窗口缩放、焦点、Unicode 输入和原生
  中文 IME 组合/候选/提交均已完成实机复测。125% 与 150% 的 Per-Monitor V2 样本曾
  完整通过，但 2026-09-30 按产品决定恢复原有 `dpiAwareness=false`，由 Windows 对最终
  HWND 做 bitmap scaling；旧 PMv2 样本仅作为历史证据，当前构建与运行时门槛改为要求
  `windowDpi=96`、awareness `0`。用户明确决定不再用当前 1080p 单屏模拟
  175%～200%，而是在功能完成后用真实高分屏复测；不同 DPI 多屏迁移也因当前只有一个
  显示器而无法执行。这两项当时作为未验证的 Phase 7 实机兼容门槛保留；后续真实
  高分屏或跨 DPI 移动已由用户现场确认通过。详见
  `docs/windows_compositor/phase2_synthetic_dcomp.md`。真实 Show 管线仍未修改。
- 2026-09-30 当前发布策略已复验：最终 EXE 的嵌入 manifest 精确为
  `dpiAwareness=false`；synthetic 报告 awareness `0` / window DPI `96`，双 Visual、
  resize、遮罩、页面与静止帧泵门槛全通过。真实 Show 在未设置 backend 环境变量时
  自动选择 `composed / custom-engine-default`，两秒样本 Show/Stage/Flutter 为
  `120 / 120 / 0`；显式 `external_texture` A/B 也再次通过。注入经 ABI 校验且哈希匹配
  Show 仓库的 DLL 后，custom Release bundle 也通过启动、响应和正常退出烟测；本地重链
  Engine 的非确定性哈希未写回锁文件，因此不冒充严格 RC 产物。
- 首次人工拖动窗口发现旧 resize 路径会在重建 surface 时提交空 DComp root，造成白闪。
  已改为保留同一 target/Visual tree 并原位 `ResizeBuffers`；修复后自动缩放/恢复门槛
  通过，tree commit 全程保持 1；用户实机复测确认白闪和缩放后整窗 Stage 穿透均已
  消失，Flutter 控件保持可见。
- 2026-09-30 修复主线合并后发现的首曲前白底与预览 viewport 不跟随问题。patchset 5
  在 Show 第一帧前只提交一次不透明黑色 Stage placeholder；App 未选歌时另有黑色上盖。
  播放后统一 Stage 画布以 `fill` 映射到实际预览 viewport，布局或 paint transform 变化
  才事件式重报物理矩形，无定时器或轮询。真实 Show 门槛在零 callback/零 frame submit
  时确认 placeholder Present 为 1，随后静止样本仍为 Show/Stage/Flutter
  `121 / 120 / 0`，窗口几何更新与全部同步/HRESULT 门槛通过。
- Phase 3 已完成：Show 在独立分支/提交中增加版本化 NT handle + keyed mutex 的
  latest-frame Stage Visual API，App/Runner/Engine v3 将真实 Show GPU 帧接入下层
  DirectComposition Visual。两秒静止 Flutter 样本为 Show submit `+120`、Stage
  Present `+120`、Flutter Present `+0`；750 ms platform-thread stall 为 Stage
  `+45`、Flutter `+0`。真实门槛已覆盖无标题/带标题、暂停/恢复、重唱、12 秒自然
  EOF、视频主时钟下音频先 EOF 与视频先 EOF、失配后恢复、预准备后的 seamless
  自然切歌、generation、fit/clip、遮罩/页面、resize 和 detach/reattach；
  没有 callback 拒绝、handle/resource 失败、stale frame 或 device removal。
- 官方 debug Engine 与 `host_debug_kirakara_v3` 都通过强制 external texture 的同一
  真实 Show integration smoke；定制合成器失败不会静默落入回退掩盖 Bug。当前原始
  Win32 枚举还会看到 Show 既有的离屏 `WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE`
  MediaEngine 时钟宿主，但可交互顶层窗口精确为 1，没有恢复 Stage 子 HWND/叠加 HWND
  方案。协议、所有权、复现命令与未验证矩阵见
  `docs/windows_compositor/phase3_real_show_stage.md`。
- Phase 4 的当前环境实现与自动门禁已完成：Runner 独立持有 Show DLL、composed 与
  external texture 均可显式 detach，Show source 事务式替换；最小化、会话锁定和系统
  挂起将“请求激活”保留在内存中但停止预览生产并 detach 下层 Visual，恢复后在同一
  HWND 自动续接。真实 Show probe 已覆盖最小化/恢复、最大化、模拟 session/power/
  display 消息、快速导航、Show 同进程重建和 Stage 活跃退出；最小化 900 ms 只剩 1
  个边界帧，模拟 lock/suspend 的 Stage 增量均为 0，恢复分别重新前进 47/51 帧，
  最终两秒 Stage
  `+120` 而 Flutter `+0`。真实锁屏、睡眠、热插拔、混合 DPI 和 device removal 当时
  保留为 Phase 7 实机门槛；最终验收中高/混合 DPI 已通过，睡眠/热插拔由所有者延期，
  device removal 留作扩展兼容项。session notification 注册状态已由运行时门槛确认。详见
  `docs/windows_compositor/phase4_lifecycle_recovery.md`。
- Phase 5 的当前环境实现与自动门禁已完成：composed backend 现在以
  `requestedActive && windowAvailable && geometryVisible` 决定实际预览 activity，
  external texture 回退也使用相同的事件驱动窗口 lifecycle，不增加轮询或 timer。
  geometry 隐藏 750 ms 内 Show/Stage 均 `+0`，恢复均 `+42`；暂停稳定 500 ms 为
  `+0/+0`；Flutter 1.4 秒淡入淡出期间 Stage `+84`、Flutter Present `+99`；前后两次
  静止样本仍为 Stage `+120`、Flutter `+0`。官方与定制 debug Engine 的 external
  texture 窗口隐藏 A/B 均为 `0 callback / 0 acquire` 并能恢复、重建。Show 既有
  30/20/15 fps 可选预览 cadence 与静态 frame scheduler 聚焦测试通过，且不改变物理
  Stage/Cast。锁定的上游 Windows compositor 没有 dirty-rect Present 接口，因此没有
  伪称局部 damage 已实现；本阶段的可证收益是 Stage-only 更新不产生 Flutter frame。
  Iris Xe 长时间热测试、真实高分屏、物理双屏/Cast 和不同 GPU 当时保留 Phase 7；
  最终核心实机验收已覆盖 Iris Xe / 1130G7 稳态、高/混合 DPI、物理双屏和 Cast。详见
  `docs/windows_compositor/phase5_vfr_damage_thermal.md`。
- Phase 6 的当前环境实现与自动门禁已完成：独立 Engine patch 仅在
  `OpenClipboard` 返回 `ERROR_ACCESS_DENIED` 时用临时 16 ms 消息窗口 timer 异步
  重试，最多 16 次或 250 ms；无 platform-thread Sleep、常驻 timer、监听、启动读取、
  历史、持久化、上传或内容日志。Unicode/CRLF、Ctrl+C/X/V、Shift+Insert、右键
  Paste、120 ms 外部占用和析构取消均通过；官方 Engine 的标准行为也通过同一回归。
  Bilibili 外链页增加显式粘贴并只清理该字段，Widget 测试确认光标与焦点可继续输入。
  Engine 19 项剪贴板聚焦测试和 365 项全量门禁通过既定判定；v4 synthetic、真实
  Stage 及官方/定制 external texture A/B 均未退化。真实触屏、RDP、第三方富文本和
  Windows 10 最终保留为 Phase 7 完成后的扩展兼容项。详见
  `docs/windows_clipboard/phase6_reliability.md`。
- Phase 7 已按仓库所有者确认的核心验收范围完成：custom Engine debug/profile/release
  三模式及 AOT patched SDK 全部锁定；官方/custom Release 对称正常关闭；三模式 ABI
  错配明确拒绝；Portable、无 UAC 当前用户安装包和补丁源码包可确定性重建，并通过
  解包运行、安装、运行、卸载与会话数据排除。2026-09-29 的补充实机验收确认 Intel
  Iris Xe / 1130G7 非 NVIDIA 活动路径、真实 Show 约 30 分钟稳态、真实高分屏/跨 DPI
  移动、物理双屏与 Cast 模式切换通过。真实睡眠/恢复和显示器热插拔由所有者决定暂缓；
  Windows 10、AMD/WARP、触屏/RDP/第三方富文本、生产签名和项目级许可证作为后续扩展
  兼容或公开发布事项，不再阻塞 Phase 7。详见
  `docs/windows_compositor/phase7_compatibility_release.md`。
- Phase 7 发布输入随后进一步收紧：普通构建默认使用仓库内既有 Show DLL 并保持
  external texture 兼容，不再硬编码本机 Show checkout；真实 composed probe/发布必须
  显式选择或解析当前 Show DLL，并在构建/打包前验证 Stage Visual ABI 1、能力 `0xF`、
  `nt-keyed-latest-v1`、保留位、函数表和设备绑定导出。仓库本地 Unicode-safe Release
  Engine 以独立候选锁定，四归档打包、Portable/Installer locked smoke、无 UAC 安装卸载
  与旧 Show 明确拒绝均已通过。二进制、PDB 和 ZIP 仍只在忽略目录或 Release 资产中。
- Phase 8 在当前主机可可靠执行的实现与自动门禁已完成：根目录 `flutterw.ps1` /
  `flutterw.cmd` 会在被忽略的 `.kfe/` 内准备锁定源码、补丁、三模式输出、缓存、日志、
  互斥锁和 ready stamp，并自动注入 local-Engine 参数。debug/profile/release Engine、
  ABI、App build、GUI 正常退出、并发等待、二次廉价复用、代理中断续跑、普通
  `flutterw clean` 边界和进程/用户/系统环境隔离均通过；移除 PATH 中已安装 Flutter 后，
  `.kfe/sdk` 的真实自动获取、锁定 revision checkout、Windows precache 和无代理二次复用
  也已通过，没有修改官方 SDK、全局 Git、PATH 或注册表。随后在真实物理路径
  `D:\仓库\Kirakara-App`（无 junction/全局 alias）补齐 vpython、GN、Ninja、
  `shader_archiver` 和内嵌 Dart `gen_snapshot` 的 Unicode 边界：锁定源码构建的 GN/Ninja
  通过 736/736 与 396/396 项测试，主仓库和依赖补丁可精确反向/重放，三模式 Engine、
  App build 和 GUI smoke 全部重跑通过。随后在当前主机的三份独立 clean clone 上，分别以
  首次 debug `run`、首次 `pub get` 和首次默认 release `build windows` 完成冷自举、实际
  DLL 加载、ABI、二次廉价复用、隔离与清理边界门禁；该过程还修复了全新 vpython 缓存、
  PowerShell 短参数 `-d` 和 Engine 工具链环境泄漏三个只在干净入口暴露的问题。第二位
  协作者复现仍未完成。旧的双击构建/启动批处理也已移除固定盘符与裸 `flutter` 调用，
  统一从自身位置解析仓库并经过同一个 `flutterw.cmd` 门禁。精确发布候选哈希不属于开发
  Engine 构建输入；指纹排除候选/产物哈希，但继续覆盖 revision、源码树、补丁、GN、ABI、
  工具链和构建脚本，避免 relock 造成无意义的三模式失效。因此 Phase 8 和总计划仍不能
  宣称全部完成。详见
  `docs/windows_compositor/phase8_repository_bootstrap.md`。
- Phase 7 长稳态门禁新增 `-SoakSeconds` 有界模式：只在起点、半程和终点采样，使用两次
  有限等待而非轮询/timer，并检查两段及全程 Stage cadence、Flutter 静止、事件唤醒、
  HWND/Visual Tree、HRESULT、device removal、occluded 和资源失败计数。synthetic producer
  跟随 DComp 时钟，所以门禁先用两段静止样本建立 30～360 Hz 的实测参考，再要求两半和
  全程保持 ±10%（至少 5 Hz），不再错误假设固定 60 Hz；真实 Show 生产时钟没有改动。
  前台安全窗口导致的 30 秒 occluded 负例仍保留。桌面恢复后的正确 synthetic 30 秒样本
  已通过：参考 140.680 Hz、两半 138.924 / 138.448 Hz，Stage present/wake 都为 4161，
  Flutter present 增量 0，全部运行门为真。随后 1800 秒完整样本也通过：参考 139.430 Hz、
  两半 137.362 / 137.475 Hz、全程 137.419 Hz，Stage present/wake 都为 247,354，Flutter
  present 增量为 1（后半为 0），RSS 差值 -2,011,136 字节，全部运行门为真。DComp 频率
  不凭枚举列表硬归因到某一 GPU/输出；Iris Xe、真实 Show/物理 Stage/Cast 与热数据仍需
  目标机实测。
- 只读进程追查确认当前 9 个 `PickerHost / Windows 安全中心` 实例均为旧版发布烟测触发的
  `FirewallNotificationDialogServer`，而不是 compositor 崩溃。Phase 7 的 GUI smoke 已升级
  为 schema v4：仅对测试子进程把 LAN 点歌服务绑定到 loopback，普通 App 仍保持全部 IPv4
  接口；烟测前后审计安全提示 PID 和精确 executable path 的 application-rule ID，任何新增
  提示或规则都令门禁失败，不自动操作安全窗口或修改防火墙。schema v4 的 bundle、全新
  解压、Portable 与 Installer 门禁均已正常退出，提示/规则增量为 0；历史 64 条规则保持
  原样，没有由脚本删除或修改。

## 为什么要做这件事

当前 Windows 主控预览通过 DXGI shared handle 向 Flutter 提供外部纹理。
KiraKara Show 每发布一帧 Stage，Runner 都会调用
`FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable`，随后 Flutter
调度一个新帧。Windows 默认 Flutter 合成器再把完整的 Flutter backing store
复制到窗口表面并执行一次 present。

这条路径能够自然维持 Flutter 的界面层级，但也把 60 Hz Stage 预览和 Flutter
的 raster/present 循环绑在了一起。即使主控 UI 完全静止，只要 Stage 画面变化，
Flutter 仍然需要为整窗提交付出成本。在低功耗、散热受限的核显上，这会与视频
解码、Video Processing、物理 Stage 输出以及 DWM 抢占同一套 GPU 与封装功耗
预算。

恢复旧的 Stage 子 HWND 路径可以避开一部分 Flutter 开销，但也会重新引入已经
遇到过的 z-order、DPI、裁切、圆角、输入、焦点和模态面板遮盖问题，因此不作为
目标方案。

本计划的目标是在一个 HWND 内建立一棵 DirectComposition 树，让 Stage 和
Flutter 成为可以独立更新的两个 Visual。

## 总体目标

1. 主控程序只保留一个顶层 HWND。打开页面、对话框、抽屉、菜单或全屏预览
   控件时，不改变窗口大小，也不通过改变窗口形状来避让内容。
2. 让 KiraKara Show 可以独立更新 Stage Visual，不再依赖 Flutter 的帧调度器。
3. 普通 Flutter Widget，包括半透明模态遮罩和播放控件，必须可以正常显示在
   实时 Stage 预览之上。
4. 不做 CPU 像素回读，并避免每个 Stage 帧都强制触发一次完整 Flutter 窗口
   present。
5. 保留现有 external texture 实现，作为同进程兼容回退路径；使用官方未修改
   Flutter 引擎构建时也继续走该路径。
6. Show 的歌词解析、字幕渲染、播放时钟、物理 Stage 输出和 Cast 管线不属于
   本计划的修改范围。
7. 定制引擎必须可复现、可锁定、可测试、可替换。不直接手改已安装的 Flutter
   SDK，也不对编译好的 DLL 做二进制补丁。
8. 顺带改善 Windows 文本剪贴板体验，但不加入轮询、剪贴板历史、持久化或内容
   日志。

## 明确不做的事情

- 不增加 `show_host_worker.exe` 或第二个主控进程。
- 不恢复 Stage 子 HWND 预览路径。
- 不重写 Flutter 的 Dart Framework，也不重写现有 Kirakara Widget 树。
- 不改变物理双屏 Stage 窗口和 Cast 输出的既有语义。
- 不承诺 Flutter `BackdropFilter` 能直接采样原生 Stage Visual 的像素。
- 第一阶段不做剪贴板监听、启动时自动读取、图片剪贴板或文件剪贴板。
- 在定制合成器完成兼容性测试和长时间稳定性测试之前，不删除现有 external
  texture 路径。

## 目标合成架构

```text
主控顶层 HWND
└─ DirectComposition Target
   └─ Root Visual
      ├─ Stage Visual
      │  ├─ Show 当前输出的 Stage GPU 纹理
      │  ├─ 预览区域位置与缩放变换
      │  └─ 矩形或圆角裁切
      └─ Flutter Visual
         ├─ 预乘 Alpha 的 Flutter backing store
         ├─ 预览区域外不透明的主控界面
         ├─ 未被遮挡时透明的预览窗口
         ├─ 普通 Flutter 播放控件
         └─ 页面、抽屉、菜单、对话框和模态遮罩
```

Stage Visual 被裁切在预览区域内，并按照生产者实际节奏更新。Flutter Visual
覆盖整个客户区，但在没有遮挡的预览区域保留透明像素。这样，DWM 可以复用静止
的 Flutter 表面，同时让下方的 Stage 独立刷新。

打开面板时，不修改 HWND，也不重新挂载 Stage。Flutter 只需要在上层 Visual
中绘制面板和遮罩。面板关闭后，相应位置重新变为透明，仍在持续运行的 Stage
便会重新露出。Flutter 动画只会在动画持续期间产生 Flutter 帧，不会永久把
Stage 更新节奏绑定到 Flutter。

### 已知视觉限制

- 普通 Alpha 叠加和暗化遮罩可以自然工作。
- Flutter `BackdropFilter` 无法采样位于下层的原生 Stage Visual。如果未来必须
  对实时视频做背景模糊，应当使用原生 Composition Effect，或明确在该效果显示
  期间切换到 external texture 回退路径。
- Flutter Widget 截图和 `RepaintBoundary` 不会包含下层原生 Stage Visual。
  App 内截图或录制必须向 Show 请求对应帧，或额外建立专用合成捕获路径。
- 不能让 Stage 从预览区域外意外透明的 Flutter 像素中泄露出来。原生 Stage
  裁切与 Flutter 外围不透明背景必须同时存在。

## 职责边界

### KiraKara Show

- 负责播放时钟、媒体解码、字幕与 Overlay 渲染，以及最终 Stage 帧。
- 发布 GPU 帧标识、尺寸、generation 和适合“只取最新帧”消费者使用的同步
  原语。
- 不感知 Flutter Widget 状态、面板状态或主控布局。

### 定制 Windows Flutter Embedder/Compositor

- 负责绑定到 Flutter 主控 HWND 的 DirectComposition device、target 与 visual
  tree。
- 将 Flutter 输出提交到支持 Alpha 的上层 Visual。
- 在 Flutter 下方提供一个外部 Stage Visual 槽位。
- 将 Flutter 提供的预览区域转换为物理像素，并原子提交位置与裁切变化。
- 在窗口尺寸变化、跨 DPI 显示器移动、显示器变化、最小化/恢复和图形设备丢失
  后恢复合成资源。
- 保留上游原始窗口 Present 路径，作为失败时的兼容回退。

### Windows Runner Bridge

- 只在当前进程中快速协商定制合成器能力。
- 连接或断开 ShowHost，并传递预览矩形、可见状态、圆角、fit 模式和 generation
  变化。
- Debug 构建可暴露诊断信息和失败原因，但不持久化硬件能力判断结果。
- 不通过 MethodChannel 传输逐帧像素，也不使用 MethodChannel 泵送 Stage 帧。

### Flutter App

- 负责页面导航、面板、控件、命中测试、无障碍和焦点管理。
- 在布局完成后提供预览区域；只有 composed backend 生效时，才将 Stage 占位区
  绘制为透明。
- 通过 `StagePresentationBackend` 抽象选择实现，避免在 Widget 中散落 Windows
  平台判断。
- composed backend 不可用时，回退到现有 `Texture` Widget。

## Stage 纹理与同步策略

1. 优先使用同一显卡适配器上的 GPU 资源。在不把 Show 与 Flutter 内部实现强
   耦合的前提下，优先考虑同设备消费。
2. 无法同设备时，使用可共享的 D3D11 texture/NT handle，并定义明确的 fence
   或 keyed synchronization 协议，不能靠时间推测纹理已经写完。
3. 预览端只消费最新一张已完成帧，并丢弃过时预览帧。主控预览绝不能对 Show 的
   物理 Stage 或 Cast 管线形成反压。
4. 避免无条件逐帧 `Flush`。只有测量证明某个驱动或跨设备同步场景确实需要时，
   才在最小范围加入。
5. 第一阶段统一使用 SDR BGRA8 和预乘 Alpha。HDR 与广色域主控预览另行规划。
6. 对较新的 raw composition texture API 做运行时能力检测，并保留兼容更多
   Windows 版本和显卡驱动的 composition swapchain 路径。
7. 对 4K、1080p、720p、576p、540p、480p、360p 以及非标准分辨率保持宽高比
   和现有 Stage fit 语义。合成区域布局不能依赖素材原始分辨率。

## Flutter Engine 定制策略

采用源码级定制引擎，并以“小型补丁栈”管理。它不是永久手改 Flutter 安装目录，
也不是运行时 DLL Hook。

Dart Framework 和普通 Flutter Package 保持原版。第一批修改只应触及 Windows
Embedder/Compositor，以及 Runner 使用能力所必需的最小接口。

建议拆成以下补丁：

1. `0001-windows-custom-compositor-build-id.patch`
   - 暴露 Kirakara compositor 能力与版本查询；
   - Debug 诊断中包含精确上游 Engine revision 和 Kirakara patchset revision；
   - 官方 DLL、定制 DLL 与 App 不匹配时清晰报错，不能直接崩溃。
2. `0002-windows-dcomp-flutter-surface.patch`
   - 将 Flutter 渲染到预乘 Alpha 的 composition surface 或 swapchain；
   - 将该表面放入 DirectComposition 上层 Visual；
   - 保留 damage 信息和上游 backing-store cache。
3. `0003-windows-external-stage-visual.patch`
   - 增加一个通用下层 external visual slot；
   - 暴露 attach、detach、geometry、clip、opacity 和 generation 操作；
   - 引擎补丁内不出现 Show 专用数据类型。
4. `0004-windows-compositor-lifecycle.patch`
   - 处理窗口缩放、混合 DPI 显示器迁移、最小化/恢复、遮挡、显示器热插拔和
     device removal；
   - 以原子方式重建资源，失败时回退到上游 Present 路径。
5. `0005-windows-damage-and-idle.patch`
   - 确保只有 Stage 更新时不会调度 Flutter 帧；
   - Flutter UI 真正变化时继续保留 damage/VFR 行为；
   - App 被遮挡或主动关闭预览时停止 Stage 合成工作，但不停止播放。
6. `0006-windows-clipboard-contention.patch`
   - 保持 Flutter 对外剪贴板 API 不变；
   - 针对短暂 `OpenClipboard` 占用增加有时间上限的异步重试；
   - 保留 Unicode 文本行为和上游错误返回；
   - 与所有合成器补丁独立，可以单独移除。

如果第 6 个补丁难以维护、难以上游化或与新版 Flutter 冲突，则将重试逻辑移动到
小型 Runner clipboard bridge 中，不把它与合成器代码纠缠在一起。

### 源码与构建产物管理

实现阶段增加以下结构：

```text
engine/
├─ engine.lock.json
├─ patches/
│  ├─ 0001-....patch
│  └─ ...
├─ scripts/
│  ├─ fetch_engine.ps1
│  ├─ apply_patches.ps1
│  ├─ build_windows_engine.ps1
│  └─ verify_engine_bundle.ps1
└─ README.md
```

规则如下：

- `engine.lock.json` 锁定 Flutter Framework revision、Engine revision、构建
  模式、目标架构、GN 参数、patchset revision 和构建产物校验值。
- 在并列的独立源码和构建目录中工作，不直接修改
  `D:\Program Files\Flutter`。
- App 仓库保存脚本、锁文件和可审查的补丁。大型 Engine 二进制和符号文件放在
  CI Artifact 或版本化 Release，不进入普通 Git 历史。
- Release 包必须携带匹配的 `flutter_windows.dll`、必要的 import library、ICU
  数据、App 资源、补丁版本说明、许可证；符号文件保留在构建服务器或 Release
  调试资产中。
- 升级 Flutter 必须作为明确任务执行：更新 lock、rebase 补丁、构建全部模式、
  跑完整测试矩阵，全部通过后才能替换正式构建产物。
- 保留一条官方 stock engine 构建任务，避免回退路径长期无人使用后悄悄失效。

## App 层接口建议

增加与具体后端无关的接口，例如：

```dart
abstract interface class StagePresentationBackend {
  Future<StagePresentationCapability> initialize(int showHostHandle);
  Future<void> setGeometry(StagePresentationGeometry geometry);
  Future<void> setVisible(bool visible);
  Future<void> setActive(bool active);
  Future<void> detach();
}
```

具体实现：

- `WindowsComposedStageBackend`：定制引擎与 DirectComposition 路径。
- `WindowsExternalTextureStageBackend`：现有 shared-handle Flutter texture 路径。
- `FallbackStageBackend`：现有非 Windows 或 Mock 行为。

`KirakaraStageRenderer` 在一次主控会话中完成选择，并把所选模式暴露给 Widget。
能力协商必须快速且只保存在内存，不把 GPU 型号、驱动或探测结果写入磁盘。
运行中发生 device loss 时可以尝试重建 composed backend；结构性初始化失败则在
本次进程内回退到 external texture。

几何更新只由布局、DPI、窗口尺寸、全屏模式或导航变化触发，不能逐帧轮询。

## 面板、导航与全屏行为

- 普通页面和面板继续作为 Flutter Widget，位于上层 Visual。
- Stage 被面板覆盖时仍保持连接和运行；只有预览被完全隐藏并持续足够时间时，
  才考虑将其设置为 inactive。
- 模态遮罩和淡入淡出仍然是普通 Flutter Alpha 内容。
- 打开面板时不重新挂载 Stage，也不改变 HWND 大小。
- 全屏预览只改变 Stage clip/transform 和 Flutter 布局。
- 所有指针、键盘、焦点、Semantics 和无障碍行为均由 Flutter 负责；Stage Visual
  本身不参与输入。
- composed backend 失败时，Flutter 将预览占位区恢复为不透明，并在不改变当前
  导航状态的前提下切换到现有 `Texture` Widget。

## Windows 剪贴板分支计划

### 当前情况

Flutter Windows 原生实现通过 `CF_UNICODETEXT` 提供 `Clipboard.getData`、
`Clipboard.hasStrings` 和 `Clipboard.setData`。当前实现只尝试打开一次剪贴板；
如果某个程序正在短暂占用，调用会立即失败。

外链输入目前是普通 `TextField`，没有面向触屏和 KTV 主控场景的显式粘贴按钮，
App 内也没有统一的 `ClipboardService` 抽象。

### 目标行为

1. 保留正常的 `Ctrl+C`、`Ctrl+X`、`Ctrl+V`、`Shift+Insert`、文本选择和 Flutter
   文本编辑语义。
2. 在 Bilibili 外链输入框增加明确的粘贴操作，适合鼠标、触屏和 KTV 大按钮
   场景。
3. 用户主动粘贴时读取 Unicode 文本，清理首尾空白与换行，并提取受支持的
   Bilibili URL、BV 号或 AV 号；不能把这种自动清理扩散到普通自由文本输入框。
4. 只对短暂剪贴板占用做短时异步重试，并设置很短的总截止时间。不能通过
   `Sleep` 长时间阻塞 Flutter platform thread。
5. 剪贴板只能由用户操作触发读取。不监听剪贴板变化、不在启动时读取、不保留
   历史、不持久化、不上传服务器，也不打印内容到日志。
6. 文本送入 Dart 之前设置保守的长度上限。对不支持的格式和异常大的内容给出
   用户可理解的错误。
7. Engine 级剪贴板测试、外链解析测试和 Widget 测试必须相互独立。

App 侧增加一个小型 `ClipboardService`，让显式粘贴行为可测试、可跨平台替换。
标准 Flutter Clipboard API 仍然是默认协议；使用定制引擎时，Windows 特有的
短暂占用重试放在该 API 下层。

## 实施阶段

### Phase 0：冻结并测量当前基线

- 记录准确的 App、Show、Flutter、Engine、Windows 和显卡驱动版本。
- 采集包含 frame ID 的 `Show publish -> external texture callback -> Flutter
  acquire -> Flutter present` 时间戳。
- 使用 PresentMon/ETW 记录以下场景：静止 UI、1080p60 预览、打开/关闭面板、
  全屏预览、物理双屏和 Cast。
- 修改引擎前，先把现有 external texture 回退路径和剪贴板行为固化成可重复测试。

退出条件：

- 已有书面基线和可重复执行的 Trace 步骤。
- 可以从锁定的 App 与 Show commit 重新构建当前版本。

### Phase 1：构建完全未修改的本地 Flutter Engine

- 建立并列的 Flutter Engine 源码目录与构建目录。
- 构建与锁定 revision 完全匹配、但没有任何 Kirakara 补丁的 Windows Engine。
- 使用该本地引擎构建并运行 Kirakara 的 debug、profile 和 release 模式。
- 建立 lock、补丁应用、产物校验和干净环境构建脚本。

退出条件：

- 本地构建的未修改 Engine 与官方产物行为一致。
- 官方产物与定制产物之间可以通过有文档记录的一次操作切换。

完成结论（2026-09-28）：两项退出条件均已满足。debug/profile 的真实 Show A/B、
release 启动/响应对照、三模式 ABI/哈希校验和 stock Engine 单测结果见 Phase 1
文档；release 优雅退出仍是明确记录的共同缺口，不是 Engine 差异。

### Phase 2：双 Visual DirectComposition 技术验证

- 先用合成的 D3D 动画纹理作为下层 Visual，不立即接入真实 Show。
- 将支持 Alpha 的 Flutter 内容作为上层 Visual。
- 验证透明预览孔、外围不透明 UI、视频上方控件、模态遮罩、页面切换、圆角裁切、
  窗口缩放和 100%～200% DPI。
- 测量下层 Visual 更新时 Flutter raster/present 是否保持静止。

进展（2026-09-28）：源码、构建、ABI、单测、自动探针和人工 harness 已就绪。显示器
点亮后的自动探针稳定通过，静止 Flutter 和 750 ms platform-thread stall 期间 Stage
都保持约 60 fps，Flutter Present 增量均为 0；屏幕关闭样本也准确命中
`STATUS_GRAPHICS_PRESENT_OCCLUDED`。自动门槛现还覆盖遮罩与页面开关，验证它们不改变
HWND、尺寸或 DComp tree，且显示期间 Stage 仍独立推进。100% DPI 下的 Alpha、圆角、
遮罩、独立页面、有限动画停止、焦点/Unicode 输入、原生中文 IME 组合/候选/提交和
连续缩放已经实机复测；空 DComp root 导致的白闪改为原位 `ResizeBuffers` 后，用户确认
  白闪与控件消失均已修复。探针会枚举进程可见的显示器 DPI；在多屏环境若能分辨
  不同 DPI 则优先选择该目标，随后自动移动过去再移回，并核对 DPI、HWND、尺寸、DComp tree 和 Stage
  推进。单屏样本明确记录为 skipped；严格档位与 mixed-DPI 负向门槛已证明错误环境不会
  被误报为通过。125% 与 150% 的 Per-Monitor V2 样本曾通过；2026-09-30 按产品决定
  恢复 `dpiAwareness=false`，当前探针改为要求虚拟化的 96 DPI 和 awareness `0`，并在
  多屏移动时保持该契约。旧 PMv2 实测保留为历史证据，不代表当前发布配置。用户于
  2026-09-28 明确决定停止在当前
  1080p 单屏上模拟 175%～200%，待功能完成后用真实高分屏复测；混合 DPI 迁移也需要
  第二台显示器。这些未验证项转入 Phase 7 实机兼容矩阵，不能据此宣称兼容性已经通过，
  但不再阻塞 Phase 2 的实现提交。

退出条件：

- 下层动态 Visual 持续流畅，而静止 Flutter 不调度新帧。
- 所有测试面板都可以覆盖在动态画面上方，不需要增加 HWND。
- 未观察到窗口缩放、焦点、输入和 DPI 回归。

完成结论（2026-09-28）：在当前可用的 100%、125% 和 150% 单屏环境，三项退出条件
均已满足，Phase 2 可以原子提交。175%～200% 真正高分屏和不同 DPI 多屏迁移是用户
明确接受的延后实机门槛，保留到 Phase 7，不得把“延后”写成“通过”。

后续策略变更（2026-09-30）：上述 DPI 结论针对当时的 PMv2 配置。当前产品恢复
`dpiAwareness=false`；合成器独立帧泵和覆盖关系不变，但高分屏 bitmap scaling 的视觉
质量需按当前发布配置重新烟测。

### Phase 3：接入真实 Show Stage 纹理

- 定义生产者与消费者之间的同步协议。
- 通过通用 external visual slot 连接 Show。
- 实现最新帧选择、generation 切换、fit、clip 和 detach。
- 保留现有 external texture 后端，支持即时 A/B 测试。

进展（2026-09-28）：Show commit `40e51d8` 定义了
`nt-keyed-latest-v1` 协议，生产者 callback 只提交带 resource/content generation、
frame ID、NT handle 和 keyed mutex key 的最新帧描述符，不等待 Flutter/DComp，也不
调用 Dart。Engine consumer 由 event 唤醒，先以零超时 `AcquireSync` 探测；若生产者
已经 `ReleaseSync`、但跨设备 GPU 工作仍未完成，则只在专用 consumer thread 上等待
这一次已发布帧完成，不能丢弃描述符并把 mutex 永久留在 consumer key。取得帧后以
GPU `CopyResource` 写入独立 composition swapchain；过期 mailbox 帧直接覆盖，无 CPU
readback、常驻 timer 或 composed 路径逐帧 Flush。App 通过
`StagePresentationAttachment` 明确区分 composed 透明孔与 external Texture。
Show follow-up `7a822b2` 同步修正 GPU smoke 的慢驱动等待语义，避免测试消费者在
首次 `WAIT_TIMEOUT` 后丢弃已发布 key 并误报失败。

真实探针在 96 DPI / RTX 4060 Ti 上通过所有门槛：静止 UI 2 秒 Stage `+120` /
Flutter `+0`，平台线程阻塞 750 ms Stage `+45` / Flutter `+0`；暂停稳定窗口漂移
0.000 秒，恢复 750 ms 推进 0.744 秒，重唱从 1.222 秒回到 0.718 秒，12 秒自然 EOF
精确进入 stopped，随后预准备曲目以 seamless 模式自然接续。补充的真实失配门槛中，
6 秒视频配两条 2 秒音轨在 2.348 秒仍为 playing 并最终于 6.099 秒停止；2 秒视频配
两条 6 秒音轨于 2.090 秒停止，两者都非 buffering，随后普通节目恢复 playing。detach/reattach
和静止样本仍正常。官方与定制 debug
Engine 的 external texture A/B 均通过。标题门槛验证标题 KRL 真实加载；逐像素标题
正确性由 Show renderer tests 覆盖，不从无截图样本外推。

退出条件：

- composed backend 与回退路径的 Stage 画面和时间表现一致。
- composed 预览不会反压物理 Stage 或 Cast。
- 已覆盖切歌、带标题/无标题、重唱、暂停/恢复和自然切歌的长时间测试。

完成结论（2026-09-28）：在当前单屏环境，三项 Phase 3 退出条件均已满足并有自动
计数/运输状态证据。composed preview 的两种视频主时钟音视频 EOF 失配已于
2026-09-29 补测通过；后续核心实机验收补充覆盖了 Iris Xe、物理双屏和 Cast 模式切换。
物理 Stage/Cast 并行时的刻意失配 EOF、真实热插拔/睡眠/device removal 仍未验证或已
明确延期，不能据当前结果宣称完整兼容矩阵完成。

### Phase 4：生命周期与失败恢复

- 覆盖混合 DPI 显示器迁移、显示器热插拔、最小化/恢复、锁屏/解锁、睡眠/恢复、
  全屏、快速导航、graphics device removal、Show 重建和 App 退出。
- 初始化与恢复必须是事务式操作：要么完整的新 Visual Tree 一次性可见，要么旧
  路径或回退路径继续有效，不能暴露半初始化状态。
- 增加 Debug 计数器，但 Release 不输出高频日志。

退出条件：

- 恢复流程结束后，不残留黑色透明孔、过期的顶层 Visual、孤立 composition
  target 或主控进程崩溃。
- 失败时可以在同一进程内回退，并保持基本可用。

### Phase 5：VFR、Damage、遮挡与热限制优化

- 确保纯 Stage 更新不再调用 Flutter texture frame notification。
- Flutter UI 更新继续保留 dirty region/damage 信息。
- 不使用轮询，在预览不可见或窗口被遮挡时停止无意义预览工作。
- 只有在新拓扑稳定后，才引入可选预览分辨率和 VFR 策略。
- 在 Iris Xe 1130G7 上重新执行降频和长期热负载测试。

进展（2026-09-28）：Runner 已用事件驱动状态机统一 composed/external texture 的
窗口可用性；composed 另将 geometry visibility 纳入实际 Stage activity。真实 Show
报告在 geometry 隐藏和暂停稳定窗口内均记录 Show publish/Stage Present `+0`，恢复
后继续 latest frame；1.4 秒 Flutter 动画中 Stage `+84`、Flutter `+99`，最终静止
两秒回到 Stage `+120`、Flutter `+0`。官方与定制 debug Engine 的 external texture
隐藏/恢复和 Show rebuild A/B 均通过。Show 已有的静态 frame scheduler、物理 Stage
活跃时 30 fps 预览 publication，以及压力下 20/15 fps 的缓降/慢恢复策略通过聚焦
CTest；这些策略只影响可选预览 consumer，不反压物理 Stage 或 Cast。

Damage 边界经锁定上游源码确认：当前 Windows `Compositor::Present` 不接收 dirty
rectangle，OpenGL present 路径会整帧 blit + swap。没有为宣称局部 damage 而引入额外
高风险补丁；Flutter 自身真正产生帧时保留上游行为，Stage-only 路径则完全不调度
Flutter。后续核心实机验收已覆盖 Iris Xe 1130G7 约 30 分钟稳态及物理双屏/Cast；
AMD、Windows 10 和真实遮挡等扩展矩阵仍不能由 RTX 4060 Ti 或 Intel 结果外推。

退出条件：

- 静止主控 UI 不存在由 Stage 驱动的 Flutter 帧泵。
- Flutter 短暂动画或卡顿时，Stage 节奏保持独立。
- 超负载时丢弃过期预览帧，不能阻塞播放、物理 Stage 或 Cast。

完成结论（2026-09-28）：当前单屏 Windows 11 / RTX 4060 Ti 环境的三项退出条件均
已有自动计数证据，且 Phase 4 生命周期回归未退化。热限制与跨硬件兼容性当时保留为
Phase 7 实机门禁；最终核心验收补充了 Iris Xe 稳态证据，其余矩阵延期。

### Phase 6：剪贴板可靠性与交互体验

- 增加 Engine 或 Runner 独立测试，覆盖临时占用、Unicode、空剪贴板、不支持格式、
  过大文本、重试期间退出和复制后的内存所有权。
- 增加 `ClipboardService`，并在外链输入框加入显式粘贴按钮。
- 增加粘贴文本清理与受支持链接提取的 Widget 测试。
- 验证键盘快捷键、鼠标右键菜单、触屏和 IME 焦点。

退出条件：

- 短暂剪贴板锁定不会把一次正常粘贴变成永久 UI 故障。
- 不存在剪贴板轮询、持久化、内容日志和启动时读取。
- 官方 stock engine 构建仍保留可用的标准剪贴板行为。

完成结论（2026-09-28）：当前 Windows 11 实机的三项退出条件均已满足。定制
Engine 对 120 ms 外部占用的标准 Clipboard 调用成功恢复，官方 Engine 的标准
Unicode/快捷键/菜单行为保持可用；实现和测试未引入监听、持久化或内容日志。
触摸屏、RDP、第三方富文本来源和 Windows 10 最终作为 Phase 7 之后的扩展兼容项保留，
不从当前自动测试推断为已通过。

### Phase 7：兼容性门禁与发布打包

- 在条件允许时测试 Windows 10 和 Windows 11。
- 测试 Intel Iris Xe/UHD、AMD 核显或独显、NVIDIA 独显，并检查 Microsoft Basic
  Render/WARP 下的失败回退行为。
- 测试 SDR 下常见素材与桌面分辨率、混合刷新率，以及 100%、125%、150%、
  175%、200% 缩放。
- 构建 debug/profile/release，并验证安装包与 Portable 包。
- 发布补丁源码、锁文件、构建说明、许可证、产物校验值、符号策略和回滚说明。

进展（2026-09-28）：custom v4 的 debug/profile/release 三模式已从同一锁定源码树
构建；profile/release 显式包含 `gen_snapshot` 与 `flutter_patched_sdk`，并锁定 AOT
工具链。严格校验确认三模式保留全部 102 个官方导出且只增加一个版本化 Kirakara
导出。官方与 custom Release 均通过不允许强制清理的启动/响应/正常关闭门禁；早期
同时失败的原因是烟测缓存旧 HWND，修正后分别约 163/168 ms 退出、退出码 0。

新增的 ABI gate 对三模式 stock DLL 确认无 custom export，对 custom DLL 确认错误
ABI 和错误结构大小都明确返回 version mismatch，只有 ABI 2、patchset 4、补丁 revision
和 Engine revision 精确匹配才返回函数表。发布脚本从 CMake 安装清单生成 Portable、
无 UAC 的当前用户安装包、补丁源码包和独立 Engine 产物包，拒绝未知文件并排除
settings、会话数据库和日志；解包运行、逐文件哈希校验、隔离安装、运行和卸载均通过。
同一输入连续两次生成的四份 ZIP 哈希逐项一致，PDB 只进入单独 Engine Release 资产，
不进入运行包或普通 Git。

发布烟测随后升级为 schema v4：仅测试子进程使用 loopback LAN 绑定，避免新路径的
Portable/Installer 为生产 LAN 监听触发 Windows Firewall 授权；普通 App 默认监听语义不变。
脚本对比启动前后 `FirewallNotificationDialogServer` PID 和当前 executable path 的规则 ID，
新增安全提示或规则都是硬失败，不会被自动关闭或用防火墙配置掩盖。提交 `1ea696f` 的
完整 Portable/Installer schema v4 门禁已通过：正常退出、没有强制清理，提示和规则增量均
为 0；A/B 四归档 SHA-256 逐项一致且 `sourceDirty=false`。

当前主机证明 Windows 11 23H2 / RTX 4060 Ti 活动路径。随后由仓库所有者补充确认：
Intel Iris Xe / 1130G7 非 NVIDIA 活动路径、真实 Show 约 30 分钟稳态、真实高分屏或
跨 DPI 移动、物理双屏和 Cast 的至少一次模式切换均通过。该批结果是现场人工验收，
未附加新的自动报告或 ETL，不应改写为自动门禁证据；其中 DPI 结果来自 PMv2 配置，
恢复 `dpiAwareness=false` 后需补当前 bitmap-scaling 视觉烟测。Windows 10、AMD、WARP、
完整
175%/200% 档位、graphics device removal、触屏/RDP/第三方富文本仍作为扩展兼容矩阵；
真实睡眠/恢复和显示器热插拔由所有者明确暂缓。项目级许可证和生产签名身份仍是正式
公开发布事项，但不阻塞本阶段的内部 Release Candidate 验收。

退出条件：

- 定制构建和官方构建都通过 Release 冒烟测试。
- 另一位协作者可以根据文档和补丁复现定制 DLL。
- Flutter 升级时，不可能静默加载一个 ABI 或版本不匹配的定制 DLL。

当前退出条件判定（2026-09-29）：第一项和第三项已通过。原第二项“独立协作者复现”
归入新增 Phase 8 的独立自举验收，不再重复阻塞 Phase 7。结合上述补充实机结果和仓库
所有者对睡眠/热插拔等低频矩阵的延期决定，Phase 7 标记为完成；这不等同于宣称所有
Windows 版本、GPU、显示拓扑和输入环境均已认证。

### Phase 8：仓库内自举与项目隔离的定制 Engine

目标是让开发者克隆 App 仓库后，不再手工创建外部 Engine 工作区，也不需要安装一份
“Kirakara 专用 Flutter SDK”。开发者只需具备普通的 Windows C++ 构建前置条件；
Engine 补丁、下载内容、源码树、构建目录、状态、日志和最终供本项目使用的 DLL 都由
本仓库管理，并且删除仓库即可移除全部 Kirakara 专属 Engine 数据。

#### 8.1 唯一入口与命令语义

提供根目录下的仓库入口（暂定 `flutterw.cmd` 与 `flutterw.ps1`，PowerShell 推荐使用
`./flutterw`），透传 Flutter 的其余参数：

```powershell
.\flutterw pub get
.\flutterw run -d windows
.\flutterw run -d windows --profile
.\flutterw build windows
```

- 上述三个命令中的任意一个都可以成为全新克隆后的第一次命令，并自动触发自举。
- 首次 `pub get` 默认准备 debug Engine，方便紧接着执行日常 `run`；它仍须完成正常的
  Dart/Flutter 依赖解析，Engine 失败时整条命令明确失败，不能留下“依赖成功但 Engine
  未就绪”的假完成状态。
- `run` 根据 `--debug`、`--profile`、`--release` 推导所需模式，未指定时为 debug。
- `build windows` 根据 Flutter 原有模式规则推导所需模式，未指定时为 release。
- 没有使用过的模式不提前构建；后续首次请求另一模式时只补建该模式。
- Engine 就绪后，入口自动传入锁定的 `--local-engine`、`--local-engine-host` 与
  `--local-engine-src-path`，调用者不再手工拼接参数。
- 非 Windows 命令可以原样交给官方 Flutter，但不能因此触发或携带 Windows 定制
  Engine 参数。

这里刻意不劫持裸的全局 `flutter` 命令。Flutter 本身没有“按项目执行的 pre-command
hook”可以同时覆盖 `pub get`、`run` 和 `build`，而修改 PATH、全局 alias 或已安装 SDK
会污染同一台电脑上的其他仓库。仓库入口是隔离边界，也是“不影响其他项目”的保证。
IDE 的 Run/Build 配置也必须调用同一个入口或等价的仓库任务，不能另造第二套状态机。

#### 8.2 仓库内工作区

所有 Kirakara 专属的未跟踪数据固定放在仓库根目录下短路径 `.kfe/`，并由
`.gitignore` 整体排除：

```text
.kfe/
├─ sdk/                 # 必要时下载的、未修改的锁定官方 Flutter SDK
├─ depot_tools/         # 锁定 revision
├─ engine/              # 锁定 Engine 源码及 gclient/CIPD 内容
├─ out/                 # debug/profile/release 的定制构建输出
├─ pub-cache/           # 仅本仓库命令使用的 PUB_CACHE
├─ cache/               # CIPD、vpython 等项目级缓存
├─ tmp/                 # 进程级 TEMP/TMP
├─ logs/                # 有界、无隐私内容的构建日志
├─ locks/               # 并发自举互斥锁
└─ state/               # 构建指纹与 ready stamp
```

- 不再要求 `E:\Kirakara-Flutter-Engine` 一类外部工作区；现有脚本的
  `-WorkspaceRoot` 只保留为底层调试入口，仓库命令默认且只认 `.kfe/`。
- 若 PATH 中的官方 Flutter 与 `engine.lock.json` 完全匹配，则只读使用它；若不存在或
  revision 不匹配，入口把锁定的**官方原版** Flutter SDK 放进 `.kfe/sdk/`，不会覆盖、
  patch 或注册为系统 Flutter。
- 入口以进程级环境变量把 `PUB_CACHE`、CIPD/vpython cache、`TEMP`、`TMP` 和
  depot_tools 相关缓存定向到 `.kfe/`；进程退出后不保留用户/系统环境变量。
- 禁止写入 `%USERPROFILE%`、`%LOCALAPPDATA%`、`ProgramData` 等位置作为本阶段的
  持久状态，禁止创建服务、计划任务、后台守护进程、注册表项、junction 或全局 alias。
- 不修改官方 Flutter cache，不把定制 DLL 复制到官方 SDK，也不自动安装/卸载全局
  Visual Studio 或 Windows SDK 组件。缺失的系统编译前置条件只做一次明确的预检并给出
  精确错误；项目专属内容仍全部留在仓库内。
- `.kfe/` 不得进入发布包、源码包或 Git；发布给最终用户的 Portable/Installer 继续只
  携带已经验证的运行时产物，不携带源码树与构建缓存。

#### 8.3 自举状态机与复用规则

仓库入口依序执行，并复用 Phase 1～7 已有脚本，不复制出第二套 Engine 构建逻辑：

1. 读取并校验 `engine/engine.lock.json`、补丁哈希和仓库根目录。
2. 检查磁盘空间、长路径、网络、Git、Visual Studio/MSVC/ATL 与 Windows SDK；在开始
   大下载前失败。
3. 在 `.kfe/locks/` 获取跨进程锁；等待过程只响应文件锁/子进程退出，不加入轮询帧泵。
4. 获取锁定的官方 Flutter、depot_tools 和 Engine revision；下载、解包与 sync 都写入
   `.kfe/`，支持安全续传，但不接受来源或哈希不明的缓存。
5. 将 Engine 源码恢复到锁定 stock tree，按顺序应用仓库补丁，核对结果 source tree。
6. 仅构建当前命令所需模式，并执行产物完整性、官方导出保留、custom export、ABI、
   patchset revision、Engine revision、GN 参数和工具链校验。
7. 全部校验通过后才原子写入该模式的 ready stamp，然后执行原始 Flutter 子命令。

复用指纹至少包含：Framework/Engine revision、Engine source tree、补丁文件及顺序、
ABI/patchset version、GN 参数、目标架构、构建模式、MSVC/Windows SDK 身份和关键脚本
版本。任一项变化都只能令相应模式失效并重建，不能静默沿用旧 DLL。普通 Dart、资源或
业务代码改动不得触发 Engine 重建。

本地开发构建不能因为 PE 时间戳或 PDB identity 的非确定性而自动改写
`engine.lock.json`。开发态门禁校验锁定源码、参数、工具链、导出和 ABI；Phase 7 的
发布候选仍使用人工审核并锁定的精确产物哈希。两类门禁不能混为一谈。

#### 8.4 失败、并发与清理

- 中断、断网或编译失败只能留下未就绪的 `.kfe/` 中间数据；没有 ready stamp 的 DLL
  永远不能传给 Flutter。再次执行同一命令应安全续跑或重建，不要求用户手工清目录。
- 两个终端、IDE 与命令行同时启动时只允许一个进程 fetch/patch/build；其他调用等待
  同一模式就绪后复验，不重复下载或并行写同一 `out`。
- 默认的 `flutter clean` 只清 App 产物，不删除耗时的 Engine 工作区。另提供明确的
  `./flutterw engine clean` 与 `./flutterw engine purge`：前者清选定构建模式，后者只
  删除仓库内 `.kfe/`，二者都不得触及官方 SDK 或其他项目。
- 输出应区分“首次下载”“应用补丁”“构建 Engine”“校验”“复用缓存”和“执行 Flutter”
  阶段，并给出真实子进程进度；不伪造百分比，不启动常驻状态轮询。
- 网络代理或镜像只能通过本次命令参数/进程环境显式提供，不写入 Git、全局配置或本地
  持久设置。

#### 8.5 文档、IDE 与兼容入口

- `engine/README.md` 改为以 `./flutterw ...` 为首选流程；现有逐步脚本保留为诊断和
  Engine 开发者入口，不再要求普通 App 开发者理解外部工作区。
- 提供使用同一入口的 VS Code tasks/launch 配置示例；IDE 不得绕过 ABI gate，也不能
  直接拾取官方 cache 中的 `flutter_windows.dll`。
- 仓库已有的双击构建/启动批处理必须从脚本位置解析当前 clone，并调用同一个 wrapper；
  不得硬编码仓库盘符、Flutter SDK 路径或通过裸 `flutter` 绕过门禁。
- 原有直接调用 `engine/scripts/build_windows_app.ps1` 的 CI/诊断脚本可继续使用，但必须
  能显式选择仓库 `.kfe/`，并与 wrapper 共享同一布局、锁和指纹实现。
- 文档明确首次构建所需空间和时间、离线复用条件、可安全删除的目录，以及为什么裸
  `flutter` 不会也不应该被仓库静默劫持。

退出条件：

- 在一份全新 clone 上，分别以首次 `pub get`、首次 debug `run`、首次 release
  `build windows` 作为入口，均可在无人手工拼接 Engine 参数的情况下得到并实际加载
  与锁文件 ABI 匹配的定制 `flutter_windows.dll`。
- 同一命令第二次执行不再 fetch、gclient sync、GN 或 Ninja 构建；只做廉价指纹/产物
  门禁并进入 Flutter。切换到未构建模式时仅补建目标模式。
- 构建中断、补丁哈希错误、错误 Flutter revision、ABI 错配、并发调用和磁盘空间不足
  都会明确失败，且不能运行半成品或官方 DLL 来掩盖问题。
- 在同机相邻的普通 Flutter 仓库执行裸 `flutter pub get/run/build`，其 SDK、cache、
  参数、输出和运行时 DLL 均不受影响；执行前后用户/系统 PATH、注册表、全局 Git 配置
  与 Flutter SDK 文件无变化。
- 删除 App 仓库后，不在仓库外遗留 Kirakara Engine 源码、构建产物、项目级缓存、
  ready stamp、后台进程或持久配置。
- 第二位协作者能够仅凭普通官方 Flutter/Windows 编译前置条件和本仓库，从 clean clone
  完成以上流程。该证据是 Phase 8 的独立验收门槛；Phase 7 已按所有者确认的核心实机
  范围单独完成。

当前退出条件判定（2026-09-29）：当前主机能够执行的实现、真实中文路径三模式构建、
运行门禁、二次复用、故障恢复、并发、隔离、清理边界和聚焦 Unicode 工具测试均已通过。
三种“第一次命令”也已分别在三份真正独立的 clean clone 中完成：首次 debug `run`、首次
`pub get` 和首次默认 release `build windows` 都从空 `.kfe` 冷自举成功，实际加载的 DLL
与各自 ready stamp 一致，ABI 2 / patchset 4 / Engine revision 门禁通过；相同命令第二次
没有 fetch、sync、GN、Ninja 或 Engine build。至少一轮仍必须由第二位协作者从 clean clone
复现，同一主机的三份证据不能替代该门槛。当前可用的三台外部机器都曾安装 Flutter，
仓库所有者决定暂不进行该验收，因此 Phase 8 和总计划保持未完成；这不回退已完成的
Phase 7。另已确认 stock Flutter 3.44.4 的
`flutter analyze` 在中文 workspace URI 上存在 LSP `Content-Length` 字符数/字节数缺陷；
直接 `dart analyze` 通过，且 Phase 8 规定的三个 Windows 自举入口不受影响。本计划不通过
修改官方 SDK 或创建路径 alias 掩盖该独立工具问题。

仓库所有者已明确把中文路径视为当前机器的特殊环境，不要求继续扩展 stock Flutter 的路径
兼容工作。已有 custom Engine/wrapper 的 Unicode 修复与真实路径证据保留，但 stock
`flutter analyze` 的上述工具缺陷只作为信息记录，不列为 Phase 8 或发布阻塞项。

Phase 7 之后新增的发布闭环也已在本机验证：仓库内 Release 候选从真实中文路径生成，
当前 Show DLL 经过独立 ABI gate 后进入 bundle，Portable 与当前用户安装包都以严格候选
哈希启动并正常退出，Engine DLL/PDB/AOT/Dart 产物进入单独 Release 归档而不进入 Git。
默认 clean-clone 构建仍只携带既有 external-texture 兼容 DLL，真实 composed 输入必须由
调用者显式提供或由探针从相邻 Show checkout 解析，且进程覆盖撤销后 CMake cache 会恢复
默认值。最终两轮四归档打包逐项 SHA-256 一致；真实 Show 复验中 2 秒 Stage
submit/present 各推进 120 帧而 Flutter present 增量为 0，750 ms 观察窗 Stage 继续推进
45 帧且 Flutter present 增量仍为 0，生命周期门禁全部通过。以上补强不替代第二位协作者
或剩余实体硬件矩阵。

## 必要的可观测能力

Debug 构建应提供带时间戳的计数器，而不是逐帧刷控制台：

- Show frame ID、generation 和 publish QPC。
- compositor latch QPC，以及已显示/已丢弃预览帧数量。
- Flutter frame request、raster 和 present 次数。
- DirectComposition commit 次数和资源重建原因。
- 当前后端与回退原因。
- device removal HRESULT 和恢复次数。
- 剪贴板尝试次数、重试总耗时和错误码，绝不包含文本内容。

需要支持有时长上限的 Trace 捕获，以便关联 Show、定制 compositor、Flutter 与
DWM/PresentMon；不能留下永久后台日志器。

## 兼容性与稳定性规则

- 依赖能力检测和 HRESULT 驱动回退，不建立 GPU 厂商白名单。
- 不跨 App 启动缓存能力探测结果。
- 明确所有 COM/D3D/DXGI 对象所有权，并按照依赖关系的逆序释放。
- Show 回调中不能等待 Flutter 或 DComp。
- 预览呈现永远不能成为播放时钟或播放状态的权威来源。
- generation 变化必须原子废弃旧纹理和旧 fence 状态。
- 图形驱动回调中不能同步调用 Flutter/Dart。
- 不提交只构建了一半的 Visual Tree。
- 补丁应尽量保持通用，以便与上游 Flutter 行为对照审查。
- 每一个补丁都必须拥有聚焦测试，并可以独立进行 Git bisect。

## 测试矩阵

功能测试：

- 第一首和后续歌曲、带标题和不带标题；
- 暂停/恢复、重唱、切歌、自然切歌、音视频 EOF 不一致和缓冲状态；
- 实时预览上打开并关闭所有面板；
- 全屏预览控件和快速页面切换；
- 单屏、物理双屏和 Cast 启用/关闭切换；
- 主控窗口最小化/恢复，以及跨显示器和 DPI 迁移；
- 从浏览器、记事本、富文本程序和远程桌面复制/粘贴，以及空剪贴板和剪贴板被
  占用场景。

性能测试：

- 没有 Stage 时的静止 UI；
- Stage 静止帧下的静止 UI；
- 1080p60 Stage 预览；
- 4K 素材缩小到预览区域；
- 低分辨率素材放大到预览区域；
- 1130G7 长时间热负载；
- 实时 Stage 上执行面板淡入淡出和短暂 Flutter 动画；
- 在各模式允许的情况下，同时进行下载、视频解码/处理、物理 Stage 和主控预览。

正确性测试：

- 不发生逐帧 CPU 像素回读；
- composed 模式下纯 Stage 更新不产生 Flutter frame request；
- 预览区域外不存在意外透明像素；
- Show generation 变化后不显示旧帧；
- 退出和 device loss 时不存在 use-after-free；
- 剪贴板内容不会进入 App 主动输出的日志、设置、诊断或持久化数据。

## 回滚策略

定制 DLL 必须保留或能共存于上游 Windows Present 路径。composed backend 无法
初始化或恢复时，App 在本次进程中选择现有 external texture 后端。正式版本也
应当能够在不修改应用领域逻辑和导航代码的前提下，重新使用官方 Flutter 产物
构建。

回退路径不是隐藏正确性 Bug 的借口。初始化和运行时失败必须在 Debug 诊断与测试
中保持可见。回退用于兼容性与持续可用，不用于静默接受崩溃、资源破坏、错误同步
或错误 Stage 语义。

## 完成标准

- 主控只使用一个 HWND，任意 Flutter 面板都能正确覆盖实时 Stage 预览。
- Stage 预览帧不再强制触发 Flutter raster/present。
- Flutter 静止内容可以保持静止，Stage 仍按照生产者节奏更新。
- 物理 Stage 与 Cast 路径维持原有时钟和行为。
- 其他协作者可以复现定制 Engine 的源码、补丁栈、构建、版本锁定、产物和回滚。
- 混合 DPI、窗口变化、生命周期、device loss、Intel/AMD/NVIDIA 兼容性和热限制
  环境都有明确测试证据。
- Windows 文本剪贴板可靠、由用户主动触发、支持 Unicode、保护隐私，并适合
  外链输入使用。

## 参考资料

- Flutter Windows Runner：
  <https://docs.flutter.dev/platform-integration/windows/building>
- Flutter 自定义 Embedder：
  <https://docs.flutter.dev/embedded>
- DirectComposition 概览：
  <https://learn.microsoft.com/windows/win32/directcomp/directcomposition-portal>
- DirectComposition HWND 层级：
  <https://learn.microsoft.com/windows/win32/api/dcomp/nf-dcomp-idcompositiondesktopdevice-createtargetforhwnd>
- App 当前桥接实现：`windows/runner/stage_texture_bridge.cpp`
- App 当前 Flutter Widget 路径：`lib/engine/kirakara_stage_renderer.dart`
- Flutter 当前 Windows 合成器：
  `flutter/shell/platform/windows/compositor_opengl.cc`
- Flutter 当前 Windows 剪贴板实现：
  `flutter/shell/platform/windows/platform_handler.cc`
