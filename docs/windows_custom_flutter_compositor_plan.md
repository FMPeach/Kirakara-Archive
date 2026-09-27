# Kirakara Windows 定制 Flutter 合成器计划

## 当前状态

- 已进入 Phase 0；源码/工具链/官方 Engine 校验值、stock 三种模式构建、Show
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
- 180 Hz 稳定区间仍为 1097 个源帧全部 acquire、全部 displayed；其 displayed
  interval 分布在约 5.56/11.11/16.67/22.22/27.78 ms。两份样本证明刷新模式会改变
  当前路径的 cadence，但不能外推为 Iris Xe 的观感或热稳定结论。打开/关闭面板、
  全屏预览、物理双屏、Cast 与 60 Hz 核显样本仍属 Phase 0 实机矩阵，步骤见
  `phase0_trace_method.md`。
- Phase 0 的核心端到端基线已闭合，但场景/硬件矩阵仍在进行；Phase 1～Phase 7
  尚未开始，尚未引入任何 Engine 行为改动。
- 编写本计划时的 App 基线：Flutter `3.44.4`、Framework revision
  `ad70ec4617`、Engine revision `a10d8ac38d`。
- 正式开始定制引擎后，实际使用的精确版本必须写入仓库内的锁定文件。
  本文档中的版本号只用于记录计划产生时的环境，不作为构建时的唯一依据。

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

### Phase 2：双 Visual DirectComposition 技术验证

- 先用合成的 D3D 动画纹理作为下层 Visual，不立即接入真实 Show。
- 将支持 Alpha 的 Flutter 内容作为上层 Visual。
- 验证透明预览孔、外围不透明 UI、视频上方控件、模态遮罩、页面切换、圆角裁切、
  窗口缩放和 100%～200% DPI。
- 测量下层 Visual 更新时 Flutter raster/present 是否保持静止。

退出条件：

- 下层动态 Visual 持续流畅，而静止 Flutter 不调度新帧。
- 所有测试面板都可以覆盖在动态画面上方，不需要增加 HWND。
- 未观察到窗口缩放、焦点、输入和 DPI 回归。

### Phase 3：接入真实 Show Stage 纹理

- 定义生产者与消费者之间的同步协议。
- 通过通用 external visual slot 连接 Show。
- 实现最新帧选择、generation 切换、fit、clip 和 detach。
- 保留现有 external texture 后端，支持即时 A/B 测试。

退出条件：

- composed backend 与回退路径的 Stage 画面和时间表现一致。
- composed 预览不会反压物理 Stage 或 Cast。
- 已覆盖切歌、带标题/无标题、重唱、暂停/恢复和自然切歌的长时间测试。

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

退出条件：

- 静止主控 UI 不存在由 Stage 驱动的 Flutter 帧泵。
- Flutter 短暂动画或卡顿时，Stage 节奏保持独立。
- 超负载时丢弃过期预览帧，不能阻塞播放、物理 Stage 或 Cast。

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

### Phase 7：兼容性门禁与发布打包

- 在条件允许时测试 Windows 10 和 Windows 11。
- 测试 Intel Iris Xe/UHD、AMD 核显或独显、NVIDIA 独显，并检查 Microsoft Basic
  Render/WARP 下的失败回退行为。
- 测试 SDR 下常见素材与桌面分辨率、混合刷新率，以及 100%、125%、150%、
  175%、200% 缩放。
- 构建 debug/profile/release，并验证安装包与 Portable 包。
- 发布补丁源码、锁文件、构建说明、许可证、产物校验值、符号策略和回滚说明。

退出条件：

- 定制构建和官方构建都通过 Release 冒烟测试。
- 另一位协作者可以根据文档和补丁复现定制 DLL。
- Flutter 升级时，不可能静默加载一个 ABI 或版本不匹配的定制 DLL。

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
