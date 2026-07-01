# Kirakara-App Plan

## 原则

- 房间实时状态只归本机 App 管理：队列、当前播放、Key、原唱/伴奏、暂停、切歌、音量都不写入云端。
- 服务器负责 catalog 权威数据：歌曲索引、歌曲分类、歌手分类、排行榜、子榜、资源版本和拉流地址。
- 本地负责执行体验：缓存服务器下发的 manifest，做本地搜索、队列和播放控制。
- Controller Screen、Stage Screen、Phone Screen 保持解耦，Stage Output 不能依赖点歌 UI。
- 开发阶段可以 mock，但 mock 数据必须走未来真实 API 的结构，避免 UI 写死分类和榜单。

## Phase 1: 仓库和原型基线

- 初始化 Git 仓库并推送到 `git@github.com:FMPeach/Kirakara.git`。
- 保留 Windows / Android 平板可运行的 Flutter 项目结构。
- 固定当前 Controller UI、Stage Screen、DisplayManager、CastService、StageRenderer 的基础抽象。
- 继续用 mock 曲库和 mock 播放状态跑通 Windows exe。

验收：

- `dart analyze` 通过或明确记录当前遗留问题。
- Windows debug / release exe 可以从 ASCII 路径构建。
- 第一版 commit 不包含 build、IDE、本地 Codex 工作目录和临时备份文件。

## Phase 2: 点歌页面和输入面板

- 将歌名点歌、歌手点歌、分类点歌、排行榜页面整理成共享页面框架。
- 抽出 `KaraokeInputPanel`、`CandidateBar`、`TouchKeyboardLayout` 和输入模式切换。
- 硬件键盘继续走系统 IME；触屏和鼠标点击走 Kirakara 自己的输入面板。
- 歌手详情页、分类详情页不再写死分类列表。

验收：

- 歌名、歌手、分类、排行榜页面都可以从服务器 mock manifest 渲染。
- 输入面板能驱动页面搜索 query。
- 候选栏只承载输入法候选，不放无效装饰文字。

## Phase 3: Catalog API 与本地搜索

- 定义 `taxonomy manifest`：歌曲分类、歌手分类、分类顺序和分类归属。
- 定义 `ranking manifest`：榜单、子榜、展示顺序和排序规则。
- 定义 `catalog index manifest`：歌曲、歌手、作品 tag、资源版本、hash、URI。
- 先用 mock JSON / 内存索引，后续按数据量接 SQLite FTS。
- 本地派生拼音、假名、罗马音、简繁转换和 token，不要求服务器维护大规模别名。

验收：

- 替换服务器下发的分类 manifest 后，分类页和歌手页自动变化。
- 替换 ranking manifest 后，排行榜和子榜自动变化。
- 本地搜索可以命中歌名、编号、歌手、社团、声库、角色、作品 tag 和服务器分类 tag。

## Phase 4: 资源拉取与缓存

- 选歌后按 catalog asset URI 请求媒体、封面和 KRL。
- 支持本地服务器和云端服务器两种来源，API 结构保持一致。
- 引入 `CacheService` 的真实缓存策略：版本、hash、大小、过期和清理。
- 播放状态仍由 `PlaybackService` 驱动，不由服务器控制。

验收：

- 同一首歌可以从本地源或云端源取资源。
- 离线时可使用已缓存索引和已缓存资源。
- 切歌、暂停、重唱、原唱/伴奏不依赖云端实时状态。

## Phase 5: Stage Output 与 KiraKara-Show 接入

- 将 `StageRenderer` mock 输出替换为 KiraKara-Show C++ / native texture 宿主。
- `Stage Screen` 只显示 16:9 KTV 演唱画面，不显示点歌 UI。
- `DisplayManager` 负责主控屏、副屏、单屏预览和用户偏好。
- `CastService` 只投 StageRenderer 合成后的画面，不镜像 Controller UI。

验收：

- 单屏模式能显示 Controller UI 和 Stage Preview。
- 双屏模式能将 Stage Screen 输出到第二屏。
- 投屏路径输出 Stage Output，而不是主控界面。

## Phase 6: LAN 点歌和发布

- `LanServer` 提供手机浏览器点歌和遥控 API。
- Phone Screen 只走局域网，队列写入本机 `QueueService`。
- 增加 Windows 打包脚本和 Android 平板构建说明。
- 建立最小自动检查：格式化、分析、核心服务测试、Windows 构建。

验收：

- 手机扫码后可以通过局域网加入队列。
- 云端不保存房间队列和当前播放状态。
- Windows exe 可用于包厢/家用主机调试。
