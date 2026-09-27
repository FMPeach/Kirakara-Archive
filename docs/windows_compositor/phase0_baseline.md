# Windows 定制合成器 Phase 0 基线

采集日期：2026-09-27（Asia/Shanghai）

## 锁定源码与工具链

| 项目 | 已验证值 |
| --- | --- |
| App 基线 | `5cbc7bf61ca0ae336b417d54094f919806c6f719`，原分支 `Unified-stage-dev`，采集前工作区干净且与 `origin/Unified-stage-dev` 为 `0/0` |
| Show 基线 | `f1c9a3162ddab8c264e03c4ee2f4813ef213f58c`，原分支 `Unified-stage-dev`，采集前工作区干净且与远端为 `0/0` |
| Flutter | 3.44.4 stable，Framework `ad70ec4617166f1c38e5d2bfd388af71fda14f06` |
| Engine | `a10d8ac38de835021c8d2f920dbf50a920ccc030`，content hash `700aebeca4c0e610f109a3979ee3e71b69d666bc` |
| Dart / DevTools | 3.12.2 / 2.57.0 |
| Windows | Windows 11 专业版 23H2，`10.0.22631.6199`，x64 |
| Visual Studio | Community 2026 18.6.11806.211 |
| Windows SDK | 10.0.26100.0 |
| WPR / WPA | WPR 10.0.22621.5624 / WPA 11.7.395.0 |

官方 Flutter Engine DLL 的 SHA-256：

| 模式 | 字节数 | SHA-256 |
| --- | ---: | --- |
| debug | 45,550,592 | `9A9B638AC057DB6FCBF33C4B75B4D36FD99077E77E8AEE71D2E3020741492425` |
| profile | 21,868,032 | `A9EF249453BC960B06FBCAC4A9D2BDA9AA57260EC9D75C2BADED6AE6ED42F384` |
| release | 21,284,864 | `61B77BC881F5C57AF5F3EEAC4A96FFD9FD87E35B77565F44C678DE105C92C2ED` |

仓库中历史遗留的 `windows/runner/libshow_host.dll` 为 4,298,970 字节，SHA-256
`E85562225F79F27E1C0688012395814CB811E965D610E78760B6B1753CFDEF09`。
当前 CMake 构建实际从 Show 的 `build/bin/libshow_host.dll` 复制 DLL；本阶段没有改动
或重新提交仓库内的 DLL。

## 本机图形基线

- Intel Core i5-12600K。
- NVIDIA GeForce RTX 4060 Ti，驱动 `32.0.15.9186`。首份样本为 1920×1080 @
  180 Hz，随后在同一 App 会话中把同一输出切到 60 Hz 采集对照样本。
- Intel UHD Graphics 770，驱动 `32.0.101.7088`。
- 另有 GameViewer、Oray 和 Virtual Display 虚拟显示适配器；60 Hz 对照仍走
  RTX 4060 Ti 的实体输出，不是目标 Iris Xe 1130G7 环境。
- 本记录只用于这次基线对照。应用运行时不得把 GPU、驱动或能力探测结果写入配置。

## 改动前验证结果

### App

- `flutter build windows --debug`：通过，运行产物为
  `build/windows/x64/runner/Debug/kirakara_app.exe`。
- `flutter build windows --profile`：通过；JNI 插件有既存的 C4022/C4047 警告。
- `flutter build windows --release`：通过。
- 聚焦测试 `stage_texture_service_test.dart` 与 `stage_preview_host_test.dart`：3 项通过。
- Windows 实机 integration baseline：external texture 使用真实 Show fixture 完成
  attach，挂载 Flutter `Texture` 并持续播放到 250 ms；该测试不把“成功挂载且无
  Flutter 异常”夸大为像素级画面校验。
- stock Clipboard API 的 Unicode/CRLF round-trip 已在独立轨道通过，详见
  [Windows 剪贴板 Phase 0 基线](../windows_clipboard/phase0_baseline.md)。
- 全量 `flutter test`：失败集合仍只有 2 项既存失败：
  `bilibili_resolver_test.dart` 仍期望已删除的 240P 质量；
  `widget_test.dart` 仍期望旧的“登录哔哩哔哩”文案。
- `flutter analyze`：既存 68 条 info，无 error/warning；主要是 collection 类型、
  const 建议和 `tool/` 下调试脚本 lint。

### Show

- 现有 37 项 CTest 全部通过，耗时 20.64 秒。
- 使用真实 fixture 执行 20 秒 `--texture-only --stage-diagnostics` soak：
  `59.9771 fps`，最差 5 秒窗口 `59.898 fps`，`dropped=0`；publish gap
  `15.1138–18.0799 ms`，大于 20/25/33 ms 的 gap 均为 0。
- 同一次 soak 中 preview copy 的典型 P95 不超过 0.02 ms，preview flush 的典型
  P95 不超过 0.075 ms，callback 的典型 P95 不超过 0.01 ms。
- 这些结果证明本机当前 Show producer 吞吐稳定，但不能代替 Flutter/DWM 端到端
  cadence 结论。

## Trace 接入后的回归

- App 的 debug/profile/release 构建均通过；真实 Stage texture integration test
  通过；三个 Stage 聚焦测试文件共 7 项通过。三种 App 产物携带的
  `libshow_host.dll` 均与本地 Show 构建一致，SHA-256 为
  `88BAD2D476B38A714E4A460467E954152EBFCF53B80C00F7BC12C1B7839118E3`；DLL
  仅存在于被忽略的构建目录，没有进入 Git。
- Show 全量构建与 37 项 CTest 通过，CTest 耗时 20.61 秒。
- 再次执行 20 秒 texture-only soak：`59.9412 fps`，最差 5 秒窗口
  `59.7953 fps`，`dropped=0`；大于 20/25/33 ms 的 publish gap 为 `2/1/0`。
  provider 未启用时所有逐帧事件在字段格式化前返回。本次单次回归证明功能路径
  未退化，不把两次短样本之间的抖动解释为统计性能结论。
- `flutter analyze` 仍只有相同的 68 条既存 info；全量 `flutter test` 仍只有上述
  两个既存失败。

显式诊断模式还通过 stock embedder 的一次性 next-frame callback 计数成功
`SwapBuffers` 后的 Flutter frame。真实 Stage 活跃的 1 秒窗口内，本机记录到：

| 事件 | 增量 |
| --- | ---: |
| Show texture callback | 60 |
| advanced Flutter texture acquire | 60 |
| Flutter frame presented callback | 60 / 61 |
| present 前出现新 acquire | 60 |

表中的 present 为两次连续诊断运行；第二次多出的 1 帧没有新 Stage acquire。
两次运行随后都关闭 Stage texture source，跳过 250 ms 排空窗口后再观察 750 ms，
texture callback 与 Flutter present 增量均为 0。这证明当前 external texture 后端
确实把 Stage 的 60 Hz 帧泵传递成 Flutter 整窗 present，而不是仅凭画面观感推断。
由于 stock callback 在 `SwapBuffers` 后还要投递到 platform thread，这组计数不能
代替 GPU/DXGI/DWM ETL 的精确 present/displayed 时间戳。

自动门禁要求 1 秒内至少 45 个 callback，callback、advanced acquire 和带新 acquire
的 present 三者差值不超过 2，总 present 最多额外 3 帧；停用后的窗口允许最多 1 个
尾部 callback 和 2 个尾部 present。该门禁只在基线脚本临时设置诊断环境变量时启用，
普通 App 路径不会持续注册 next-frame callback。

### 180 Hz 有效 ETW / PresentMon 样本

管理员会话已在静止 Flutter UI、1080p60 Stage 持续更新的场景中完成 20 秒采集：

| 项目 | 实测值 |
| --- | --- |
| ETL | `static-ui-1080p60.etl`，784,334,848 字节 |
| SHA-256 | `A4618395ACF548E79C998C0F120DD5E4798E269AF77408B08B226FE796F2F6BB` |
| Trace 时间 | 20.7793385 秒，0 lost buffer，0 lost event |
| App | `kirakara_app.exe`，PID 58692，profile + 显式 compositor diagnostics |
| Stage generation / frame | generation 4，frame 6788～8001 |
| 分析工具 | WPT TraceProcessing + PresentMon 2.6.0 x64 |

离线使用的官方 PresentMon 单文件程序不进入仓库；本次文件为 980,320 字节，
SHA-256 `B2A706BC6AD475749E3B7E3409263AA1E6906D45BDCF993F6DBC0F660188F1AF`，
Authenticode 状态为 Valid，签名者为 Intel Corporation。分析报告位于被忽略的
`build/diagnostics/static-ui-1080p60-a4618395-analysis.json`，可由源码分析脚本重建。

1214 个 Stage frame 的自定义事件链全部完整、顺序正确：

| 事件 | 数量 |
| --- | ---: |
| StagePublish / PreviewPublication / PreviewCallback | 1214 / 1214 / 1214 |
| TextureCallback / FrameAvailable | 1214 / 1214 |
| TextureAcquire / advanced / repeated | 1215 / 1215 / 0 |
| FlutterFramePresented callback | 1215 |
| 主窗口 DXGKRNL Present | 1214 |

多出的 acquire 与 callback 属于 Trace 开始前已在途的 frame 6787。以发生在 raster
路径上的 `TextureAcquire` 向后配对 5 ms 内最近的 kernel Present 后，1213 个
StagePublish 一对一关联到主窗口 `HWND 0x15112e`；frame 6789 的 acquire 位于 WPR
启动扰动中，约 100 ms 后才出现带相同 frame ID 的异步 presented callback，因此
分析器刻意不借助延迟 callback 把它强行归属给较晚的 kernel Present。所有主窗
Present 均来自 context `0x40000140`、`FlipInterval=1`、`ReturnStatus=0`。裁掉首尾后
1097 个稳定 Stage frame 则全部与新的 acquire、主窗 Present 和 displayed 结果闭合。
由此可以确认稳定状态下 stock external texture 每发布一帧，当前路径都会驱动一次
真实的 Flutter 主窗口 Present，并非只有诊断 callback 在计数。

PresentMon 在离线状态机建立前省略了最初四个主窗 Present；其后 1210 个
`Composed: Copy with GPU GDI` 均与 DXGKRNL 主窗 Present 匹配，匹配误差 P50
0.0874 ms、P99 0.4349 ms、最大 0.9127 ms。其中 1209 个 displayed，唯一 dropped
为 WPR 启动扰动中的 frame 6793。按首尾 StagePublish 各裁掉 1 秒后，稳定区间为
1097 帧 displayed、0 dropped。

稳定区间的关键时延如下；单位均为 ms：

| 区间 | P50 | P95 | P99 | Max |
| --- | ---: | ---: | ---: | ---: |
| StagePublish 间隔 | 16.6609 | 18.3962 | 19.4494 | 20.8400 |
| StagePublish → DXGKRNL Present | 5.5679 | 7.6781 | 8.5349 | 9.9925 |
| TextureAcquire → DXGKRNL Present | 1.0772 | 1.7124 | 2.3355 | 2.8377 |
| DXGKRNL Present → displayed | 8.0432 | 10.9148 | 11.0862 | 16.5458 |
| StagePublish → displayed | 11.8355 | 17.2400 | 17.5197 | 22.6860 |

全窗口最大 109.1271 ms 的 Stage gap 与 100.4070 ms 的 acquire→callback 延迟都发生
在 WPR 启动区；裁掉首尾后不再出现。`FlutterFramePresented` 是 SwapBuffers 成功后
投递到 platform thread 的 callback；稳定状态通常只与 kernel Present 相差亚毫秒，
但 platform thread 受阻时可以晚很多，且执行时读取的 current frame 已可能改变。
分析器因此只用它做计数/延迟诊断，以同步的 texture acquire、DXGKRNL 与 PresentMon
确定 source/present/displayed 边界。

这台机器的 180 Hz displayed 间隔在稳定区间并非全部为 16.67 ms：1096 个间隔按
180 Hz refresh period 分桶为 1/2/3/4/5 个周期各 `4/214/657/220/1` 次，即约
5.56/11.11/16.67/22.22/27.78 ms，均值 16.6662 ms。高刷新率把误差量化到更短的
刷新周期，不能据此判断目标 60 Hz 输出上的视觉掉帧或顿挫；这份样本只作为因果、
计数与时延基线。

### 60 Hz 对照：源时钟稳定，Flutter acquire 前发生合帧

在不重启 App、保持同一 profile + compositor diagnostics 进程的条件下，将 NVIDIA
输出切换为 1920×1080 @ 60 Hz，并再次采集静止 Flutter UI + 1080p60 Stage：

| 项目 | 实测值 |
| --- | --- |
| ETL | `static-ui-stage-1080p60-display-60hz.etl`，675,282,944 字节 |
| SHA-256 | `849B9431648D939790CADA9E82A669469EA20D9B807ECDC103D4113878A39CF6` |
| App | `kirakara_app.exe`，PID 58692，profile + 显式 compositor diagnostics |
| Stage generation / frame | generation 9，frame 1253～2516 |
| 显示模式 | NVIDIA GeForce RTX 4060 Ti，1920×1080 @ 60 Hz |

从 Show 发布到 Flutter frame notification 的五个边界仍然严格一对一，均为 1264 次：

| 事件 | 数量 |
| --- | ---: |
| StagePublish / PreviewPublication / PreviewCallback | 1264 / 1264 / 1264 |
| TextureCallback / FrameAvailable | 1264 / 1264 |
| TextureAcquire / advanced / repeated | 1105 / 1074 / 31 |
| FlutterFramePresented / 带新 acquire / 不带新 acquire | 1108 / 1073 / 35 |
| 主窗口 DXGKRNL Present | 1109 |

因此第一处显著少帧不在 Show、preview copy、callback 或 frame notification，而在
`FrameAvailable -> TextureAcquire(Advanced=true)`。分析器以同步发生在 raster
路径上的 `TextureAcquire` 配对 kernel Present，不使用异步 callback 的当前 frame ID
决定归属：全窗口 1109 次主窗 Present 中，1071 次带新 acquire、31 次带重复
acquire、7 次没有调用 external texture acquire。首尾各裁掉 1 秒后的稳定区间结果为：

| 源帧/窗口结果 | 数量 | 占 1149 个稳定源帧 |
| --- | ---: | ---: |
| Show 稳定源帧 | 1149 | 100% |
| advanced acquire 并进入主窗 Present | 969 | 84.33% |
| acquire 前被后续 latest frame 取代 | 180 | 15.67% |
| 源帧最终 displayed | 918 | 79.90% |
| 已进入 Present、但所有对应窗口 Present 均被 DWM drop | 51 | 4.44% |

180 个未 acquire 的 frame ID 全部是单帧、没有连续两帧以上的缺口。这不像 producer
停住后成串缺帧，而更像两个同频但不同相位的调度循环在边界附近反复越线。
PresentMon 对稳定区间记录到 1004 次窗口 Present，其中 945 displayed、59 dropped；
36 次窗口 Present 没有取得新 Stage frame（包括重复 acquire 和未调用纹理 acquire
的 UI frame），不能把这些 Present 误算成新的 Show frame。

稳定区间的关键时序为：

| 区间 | P50 | P95 | P99 | Max | Mean |
| --- | ---: | ---: | ---: | ---: | ---: |
| StagePublish 间隔 | 16.6680 | 18.1817 | 19.1307 | 20.1034 | 16.6668 |
| TextureCallback → advanced acquire | 8.0212 | 16.5359 | 17.1637 | 17.9929 | 8.4314 |
| acquire → DXGKRNL Present | 1.0022 | 1.5108 | 2.0557 | 3.3402 | 1.0688 |
| StagePublish → displayed | 39.5927 | 40.4936 | 40.7811 | 41.0157 | 35.2316 |

Show 的平均周期仍为 16.6668 ms，稳定区间最大 publish gap 仅 20.1034 ms，没有
大于 25 ms 的 producer stall。相反，callback 到 acquire 的 P95 已接近一个完整
60 Hz 周期；只要 acquire 落到下一次 producer publication 之后，latest-frame 语义
就会直接跳过旧帧。

frame 1315/1316 给出了不依赖统计推断的具体例子，以下均为 Trace 相对时间：

1. frame 1314 在 1287.876 ms 进入 `TextureCallback`，1296.078 ms 被 acquire，
   1296.931 ms 收到 presented callback；
2. frame 1315 在 1304.297 ms 完成 callback/notification，但没有任何对应 acquire
   或 present；
3. frame 1316 在 1321.249 ms 到达，1321.549 ms 被 acquire，1322.489 ms present；
4. 随后 1324.947 ms 又 acquire 同一个 frame 1316，`Advanced=false`，并在
   1325.781 ms 产生一次不带新 Stage frame 的 present。

可见 frame 1315 已成功交付通知，并非 Show 没生成；Flutter 真正取纹理时 latest
descriptor 已变为 1316，所以 1315 是在 consumer 调度边界被“合掉”的。稳定区间
918 个 displayed 源帧的相邻显示间隔按 60 Hz 分桶为 1/2/3 个刷新周期各
`688/227/2` 次，即 16.67/33.33/50.00 ms；多出的 231 个刷新周期恰好等于
180 个未 acquire 源帧加 51 个 DWM-dropped 源帧。

这份对照实质支持“帧被调度相位吃掉”的怀疑，但不支持“Show producer 时钟本身
不稳”。目前可以把问题定位到 notification 之后、Flutter acquire/DWM displayed
之前；还不能仅凭一份样本断言根因只在 Flutter Animator、DWM vsync 或某一条 GPU
队列。180 Hz 对照的 1097 个稳定源帧则全部 acquire、全部 displayed，说明显示刷新
模式会显著改变该现象；下述 60 Hz 复测用于判断稳定不变量，Iris Xe 则留待兼容矩阵。

### 60 Hz 复测：损失边界随相位转移

同一 App PID、同一 NVIDIA 1920×1080 @ 60 Hz 模式下完成第二份静止场景采集：

| 项目 | 实测值 |
| --- | --- |
| ETL | `static-ui-stage-1080p60-display-60hz-repeat.etl`，732,954,624 字节 |
| SHA-256 | `E690ED3E9A639D90EE13B9CA10DF5C640D4021DCB7ACA8BCFA4022B38F571037` |
| Stage generation / frame | generation 13，frame 3620～4833 |
| 完整上游边界 | StagePublish / publication / preview callback / texture callback / notification 均为 1214 |
| 主窗口 DXGKRNL Present | 1177 |

裁掉首尾各 1 秒后，两份 60 Hz 样本的唯一源帧 disposition 为：

| 指标 | 首份 60 Hz | 60 Hz 复测 |
| --- | ---: | ---: |
| 稳定源帧 | 1149 | 1100 |
| acquire 前被 latest frame 取代 | 180（15.67%） | 46（4.18%） |
| acquire 后最终被 DWM drop | 51（4.44%） | 243（22.09%） |
| displayed 源帧 | 918（79.90%） | 811（73.73%） |
| displayed 源帧间隔均值 | 20.8644 ms | 22.6125 ms |

复测的 Show publish 间隔均值仍为 16.6666 ms，P50 16.6633 ms，P95
18.1845 ms，最大 20.5714 ms；1214 个源帧仍逐个到达 texture callback 与
notification。producer 没有出现能解释显示缺口的长停顿。

复测稳定区间的 810 个 displayed 源帧间隔只落在 1/2 个 60 Hz 周期：
`521/289` 次。289 个额外缺失周期再次精确等于 46 个 acquire 前合帧加 243 个
DWM-dropped 源帧。窗口维度为 815 displayed、251 dropped；同一源帧可能被重复
Present，因此不能与唯一源帧计数混用。

两份样本没有复现相同的百分比：首份主要在 Flutter acquire 前合帧，复测主要在
DWM displayed 前丢弃。这正是需要记录完整链而不能只看 FPS 的原因。能够复现的是：

1. Show producer 以稳定 60 Hz 完整交付每个 notification；
2. 缺失全部发生在 `FrameAvailable -> acquire -> Present -> displayed` 下游；
3. 每个可见缺失刷新周期都能由未 acquire 或 DWM drop 的具体 frame ID 解释；
4. 180 Hz 对照没有这两类稳定区间损失。

因此 Phase 0 不把某一个掉帧百分比写成性能门槛，而把“下层 60 Hz producer 不应再
驱动 Flutter raster/present”作为后续架构门槛。静止 60 Hz 基线至此冻结，不再用
第三次相同采集拖延 Phase 1；59.94 Hz、Iris Xe、交互场景和多输出留在后续兼容矩阵。

此前另有一份 21.1197568 秒管理员 WPR 冒烟 ETL（356,515,840 字节，SHA-256
`3DDECD9DC6C99DA191AF806D5FC3495A4016017F4DE5C667FB0A2A0B3B84BE5D`）。其捕获
窗口没有 `kirakara_app.exe`，只验证权限和 profile，不计入 compositor 基线，也不
提交 Git。采集脚本现会预检 App 进程，并绕开 WPR 10.0.22621 对 Junction 结果路径
返回 `0xc5600600` 的问题。

## 可重复命令

采集机器、源码、Flutter 与官方 Engine 校验值：

```powershell
.\tool\windows_compositor\capture_baseline.ps1 `
  -ShowRepository 'D:\仓库\Kirakara Show' `
  -OutputPath '.\build\diagnostics\phase0-baseline.json'
```

执行真实 external texture 与标准剪贴板基线：

```powershell
.\tool\windows_compositor\run_windows_stage_texture_baseline.ps1 `
  -ShowRepository 'D:\仓库\Kirakara Show'
```

ETW/WPR 采集与分析见 [phase0_trace_method.md](phase0_trace_method.md)。

## 尚需实体机验证

- 1130G7 Iris Xe 与热稳定状态；RTX 4060 Ti 已有同一输出 180/60 Hz 对照，但不能
  代替目标核显上的视觉、cadence、功耗与热限制验证。
- 59.94 Hz（若输出支持）可作为后续 cadence 矩阵项；两份固定 60 Hz 静止样本已经
  证明损失边界会随相位转移，因此不再要求复现某一个固定百分比。
- 打开/关闭面板、全屏预览的独立 ETL；不能从静止 UI 样本外推遮盖与动画行为。
- 物理双屏及 Cast 同时启用时的完整 WPR/PresentMon 样本。
- 100%～200% 混合 DPI、跨显示器、最小化/恢复和显示器热插拔。
- 剪贴板人工交互覆盖在独立轨道中维护，不与合成器改动混合。

在这些样本完成前，不把本机 RTX 4060 Ti 的 180/60 Hz 结果外推为目标实体机结论。
