# Kirakara-App IME Plan

## 目标

Kirakara-App 的输入法不是系统级 IME，而是一个服务于点歌屏的内置搜索输入器。它只负责 App 内的歌名、歌手、分类、外链解析等搜索输入，不接管其他应用。

核心目标：

- 硬件键盘输入继续走系统 IME。
- 触屏和鼠标点击输入走 Kirakara 自己的输入 UI。
- 候选栏成为正式 UI，不再作为装饰或搜索建议区。
- 中文、日文、手写都复用同一套候选栏和提交流程。
- 先用 mock 引擎跑通状态机，再逐步接入 Rime、Mozc、Zinnia 等开源引擎。
- IME 只负责输入法候选和提交文本，不读取、不查询、不匹配曲库。

非目标：

- 不做系统输入法安装包。
- 不控制 Windows / Android 系统软键盘的位置、大小或候选窗。
- 不在第一阶段实现完整公网词库或云端输入服务。
- 不把搜索建议、历史记录、热门歌曲混进 IME 候选栏。
- 不把曲库命中、歌曲 ID、歌手 ID 或 catalog tag 混进 IME 候选栏。
- 不要求服务器维护每首歌的大规模民间别名、译名和错拼变体。

## 当前实现状态

- 输入面板、候选栏、A-Z 输入、数字键盘、模式切换和手写板 UI 已进入 Flutter 原型。
- Windows 版 Rime 已作为 App 自带 runtime 接入，用户不需要安装第三方输入法。
- Windows 版 Zinnia 已静态链接进 runner，并随 App 打包日文和中文手写模型。
- Windows 版 Mozc 已作为 App 自带 helper runtime 接入，用户不需要安装系统日语输入法。
- 所有 App 自带引擎都通过统一 `ImeEngine` 返回输入候选，不直接访问 `SearchService`、Catalog API 或页面结果。
- release 路径不再包含 mock fallback。原生引擎不可用时，候选栏显示错误并保留原始输入，不伪造候选字。

## 输入通道划分

### 硬件键盘通道

硬件键盘输入由系统决定：

- Windows 上使用系统 IME。
- Android 平板接外置键盘时使用系统 IME。
- Flutter 只维护正常文本焦点和搜索 query。
- 不拦截系统候选，不替系统生成候选。

这个通道适合有实体键盘的调试、包厢主机维护、后台配置。

### 触控通道

触控或鼠标点击屏幕键盘时，进入 Kirakara 输入面板：

- A-Z / 九宫格 / 手写区域由 Flutter 绘制。
- 候选栏由 Flutter 绘制。
- 输入模式切换由 Flutter 控制。
- 输入事件送到内置 `ImeEngine`。
- 引擎返回 preedit 和 candidates。
- 选中候选后写入统一的搜索 query。
- 页面搜索由 Search / Catalog 层消费 query，IME 不知道当前页面有多少首歌。

这个通道是 KTV 点歌屏的主路径。

## UI 分层

当前页面中的输入区域应拆成独立组件：

```text
KaraokeInputPanel
  SearchTabs
  SearchDisplayField
  CandidateBar
  TouchKeyboardLayout
  ImeModeSwitch
```

### SearchTabs

用于切换搜索范围：

- 歌名
- 歌手
- 分类
- 页面内局部搜索，比如歌手详情内搜索

这不是输入法模式。它决定 query 被哪个页面消费。

### SearchDisplayField

显示当前搜索文本。

触控模式下它应该像输入框，但不主动弹系统软键盘。可以使用只读 TextField 或自绘显示框。

硬件键盘模式下允许真实 TextField 获得焦点，让系统 IME 处理输入。

### CandidateBar

候选栏是正式输入法 UI。

职责：

- 展示当前输入法候选字、词、假名、汉字转换结果。
- 支持分页或横向滚动。
- 支持候选编号。
- 点击候选后 commit。
- 手写识别结果也显示在这里。

限制：

- 不显示装饰文本。
- 不显示热门歌曲。
- 不显示搜索历史。
- 不显示 catalog 搜索建议。

如果以后要做歌曲搜索建议，需要单独设计 `SearchSuggestionBar`，不要混进 `CandidateBar`。

### TouchKeyboardLayout

第一阶段保留当前 A-Z 键帽。

后续可以增加：

- QWERTY
- 九宫格拼音
- 日语 12-key
- 手写板
- 笔画/部首输入

布局切换不应该影响引擎接口。所有布局都只产生 `ImeKeyEvent`。

### ImeModeSwitch

模式先保留：

- 英文
- 拼音
- 日语罗马音
- 手写

模式切换后，`KaraokeInputPanel` 只更换当前 `ImeEngine` 和键盘布局，不改变搜索页面。

## 状态模型

需要新增输入法状态模型：

```dart
enum ImeMode {
  english,
  pinyin,
  japaneseRomaji,
  handwriting,
}

class ImeCandidate {
  const ImeCandidate({
    required this.text,
    this.annotation,
    this.score,
  });

  final String text;
  final String? annotation;
  final double? score;
}

class ImeComposition {
  const ImeComposition({
    required this.mode,
    required this.rawInput,
    required this.preedit,
    required this.candidates,
    this.pageIndex = 0,
    this.hasPreviousPage = false,
    this.hasNextPage = false,
  });

  final ImeMode mode;
  final String rawInput;
  final String preedit;
  final List<ImeCandidate> candidates;
  final int pageIndex;
  final bool hasPreviousPage;
  final bool hasNextPage;
}
```

搜索框文本和输入法组字状态要分开：

```text
SearchQueryController.text    已提交到搜索的文本
ImeComposition.rawInput       当前按键串
ImeComposition.preedit        正在组字的显示文本
ImeComposition.candidates     当前候选
```

这样可以避免“用户正在输入拼音”时立即污染搜索文本。

## 引擎接口

建议先定义统一接口：

```dart
abstract class ImeEngine {
  ImeMode get mode;

  Future<void> activate();
  Future<void> deactivate();

  Future<ImeComposition> inputKey(String key);
  Future<ImeComposition> backspace();
  Future<ImeComposition> clear();
  Future<ImeComposition> nextPage();
  Future<ImeComposition> previousPage();

  Future<ImeCommitResult> commitCandidate(int index);
  Future<ImeCommitResult> commitRaw();
}

class ImeCommitResult {
  const ImeCommitResult({
    required this.text,
    required this.composition,
  });

  final String text;
  final ImeComposition composition;
}
```

手写引擎额外提供 stroke API：

```dart
abstract class HandwritingImeEngine implements ImeEngine {
  Future<ImeComposition> beginStroke(double x, double y);
  Future<ImeComposition> appendStrokePoint(double x, double y);
  Future<ImeComposition> endStroke();
  Future<ImeComposition> recognize();
}
```

## 引擎选择

### 英文

第一阶段自研即可。

规则：

- A-Z 直接追加到 raw input。
- 空格直接 commit 或追加空格，按页面需要决定。
- 候选栏通常为空。

### 中文拼音

推荐目标：Rime / librime。

原因：

- librime 是跨平台 C++ 输入法核心。
- 支持多种中文输入方案，包括拼音和形码。
- 支持 schema 配置和 OpenCC。
- 许可证为 BSD-3-Clause，分发压力相对小。

接入策略：

1. 先做 `MockPinyinImeEngine`，用固定词表模拟候选。
2. 再做 Windows 上的 librime FFI spike。
3. 跑通 `inputKey -> candidates -> commitCandidate`。
4. 再处理 Android native library 打包。
5. 保持 Rime 作为语言输入引擎，不从曲库 catalog 自动注入歌曲、歌手或别名。

注意：

- Rime 适合中文，不负责日语主转换。
- schema、用户词典、部署目录要由 App 管理。
- 候选结果进入 CandidateBar，不直接进搜索建议。
- `qilixiang -> 七里香` 如果来自 Rime 通用词库是输入法行为；如果是为了召回歌曲，则应由本地搜索索引的拼音字段完成。

### 日语

推荐目标：Mozc。

原因：

- Mozc 是 Google Japanese Input 的开源项目。
- 支持 Windows、Android、macOS、Linux 等多平台。
- 主体代码为 BSD-3-Clause，但 third-party 和 dictionary 目录需要逐项确认。
- 日语转换复杂，歌名、艺名、专名和外来语很难靠轻量自研补齐。

接入策略：

1. 先做 `MockJapaneseImeEngine`，模拟 romaji 到候选。
2. 做一个独立 native spike，不接 UI：
   - 输入 `zankokunatenshi`
   - 验证是否能拿到合理候选
   - 验证 session lifecycle、candidate paging、commit
3. 如果 spike 成功，再封装成 `MozcImeEngine`。
4. Flutter 只调用统一 `ImeEngine`，不感知 Mozc 内部。
5. Android 端单独评估 Mozc build 和 native library 打包。

风险：

- Mozc 是完整 IME 工程，不是小 SDK。
- 构建系统复杂，Android 构建尤其要单独验证。
- 没有稳定 release 概念，需要锁定 commit。
- 第三方词典和数据许可证需要审计。

备选：

- Anthy Unicode：更轻，但转换质量和现代词库可能弱于 Mozc。
- OpenWnn：Android 方向可参考，但不适合作为 Windows + Android 共用主引擎。
- libkkc / libskk：技术方向可参考，但 GPL 许可证会增加分发限制。

### 手写

推荐目标：Zinnia。

原因：

- Zinnia 接收笔画坐标，输出 n-best 字符候选。
- 它不负责渲染，正好适合 Kirakara 自己画手写板。
- 提供 C/C++ API，适合 native bridge。
- 支持 Windows 和 POSIX 风格构建，模型需要单独打包。

接入策略：

1. 先做 Flutter 手写板 UI：
   - 采集 pointer down / move / up
   - 存储 stroke 点
   - 支持清空、撤销一笔、识别
2. 用 mock handwriting engine 返回固定候选。
3. 接 Zinnia C API spike：
   - 加载日文模型
   - 加载中文模型
   - 输入 stroke 坐标
   - 返回候选字符
4. 候选统一进入 CandidateBar。
5. 选中候选后写入 SearchQueryController。

风险：

- 模型来源和许可证需要确认。
- 中文简体、繁体、日文汉字模型可能质量不同。
- 手写识别结果通常是单字候选，需要和搜索 query 的追加逻辑配合。

## Catalog 索引与本地搜索

IME 解决“怎么输入”，Catalog 索引解决“本地怎么搜到”，资源服务解决“选中后从哪里播放”。

设计目标：

- 服务器提供完整索引包、分类配置、榜单配置和资源描述。
- 本地导入索引包后用 SQLite FTS 或同类本地索引搜索。
- 点歌队列、当前播放、Key、原唱/伴奏、暂停、切歌仍然只由本机管理。
- 选中歌曲后，本机再按资源描述向服务器请求媒体、封面、KRL 或拉流。
- 服务器可以是本地 NAS / 本机资源服务，也可以是后续云端曲库；两者遵循同一套 Catalog API。
- 云端服务器一定需要数据库；App 本地是否使用 SQLite 是缓存和搜索实现细节，不改变服务器作为 catalog 权威的定位。
- 服务器可以随时增删媒体、封面和 KRL；本机缓存的资源文件只是播放周期临时副本。

推荐流程：

```text
CatalogServer / LocalCatalogServer
  -> taxonomy manifest / ranking manifest / index manifest / delta updates
  -> Kirakara persistent index cache or SQLite + FTS
  -> local search result
  -> queue item
  -> media asset request / stream request
  -> temporary playback asset cache
  -> playback engine
```

索引包应优先包含稳定结构化字段：

- 歌曲原名
- 歌曲编号
- 歌手 / 社团 / 声库 / 角色
- 番剧 / 游戏 / 企划 / 作品 tag
- 服务器定义的歌曲分类 ID / tag
- 服务器定义的歌手分类 ID / tag
- 榜单 ID、子榜 ID 和排序信号
- 语言
- 年代或热度等排序信号
- 媒体资源描述，如 video、accompaniment、vocal、cover、krl
- 资源版本、hash、大小和可拉取 URI
- 索引缓存策略和资源临时缓存策略

Catalog 权威边界：

- 歌曲分类列表由服务器下发，例如动画、东方、VOCALOID、华语、欧美、经典。
- 歌手分类列表由服务器下发，例如华语男歌手、华语女歌手、日本歌手/组合、ACG 特别分类、VOCALOID 声库、Vtuber / 虚拟主播、同人社团。
- 歌曲属于哪些分类、歌手属于哪些分类，都由服务器下发的关系表决定。
- 排行榜和子榜由服务器下发，例如总榜、新歌榜、动画榜、VOCALOID 榜、包厢热唱榜。
- App 不硬编码分类数量、分类名称、分类顺序、歌手分类归属和榜单结构。
- App 只缓存最近一次成功同步的 taxonomy / ranking / index manifest；离线时继续使用缓存。
- App 不把媒体、封面和 KRL 缓存视为离线曲库；这些资源必须按服务器版本/hash 校验，播放周期结束后可以删除。
- 开发阶段可以使用 mock manifest，但 mock 数据也要走同样的数据结构，避免 UI 写死。

资源缓存边界：

- 持久缓存只保留 catalog / taxonomy / ranking / FTS 所需索引和本地用户数据。
- 媒体、封面、KRL 和解码准备文件属于 `PlaybackAssetCache`，默认在当前应用周期或当前播放链路内有效。
- 服务器删除资源、修改 KRL、资源版本/hash 变化、校验失败、缓存压力或 App 退出时，本地临时资源可以被清理。
- 离线状态下可以继续使用已缓存索引做搜索和排队规划，但不承诺播放已经被缓存过的资源文件。
- 播放时长、自动切歌和进度基准来自 App 打开的原唱音频实际时长，不要求服务器下发 duration。

本地可派生或维护的搜索字段：

- 拼音
- 假名
- 罗马音
- 简繁转换
- 分词 token
- 用户本地搜索历史
- 用户本地自定义别名

别名策略：

- 不把大规模别名作为云端必填字段。
- 不要求服务器维护每首歌的民间译名、简称、梗名和错别字。
- 允许极少量高频、稳定、低争议 alias，例如 `EVA`、`东方`、`初音`。
- 包厢或个人常用叫法应优先作为本地用户自定义别名，不上传为全局 catalog 负担。

这样服务器只负责“这首歌是什么、属于什么、资源在哪里”，本机负责“怎么输入、怎么搜、当前房间怎么播放”。

## IME 与搜索的边界

IME 不负责替服务器补别名库。
IME 也不负责替本地搜索做曲库匹配。

它只帮助用户更容易输入：

- 中文拼音候选。
- 日文假名 / 汉字转换候选。
- 英文原文。
- 手写识别候选。

IME 输出的数据只能是：

- raw input
- preedit
- 候选文本
- 候选注释和分页状态

IME 不输出：

- song id
- artist id
- category id
- ranking id
- 搜索结果数量
- catalog tag 命中信息

本地 FTS 负责在已下载索引里召回：

- 原文歌名
- 歌手名
- 社团名
- 番剧 / 作品 tag
- 分类 tag
- 声库 / 角色
- 社团名
- 作品名
- 歌曲编号

例子：

```text
用户输入: eva
IME: 英文 raw input，候选栏可为空
FTS: 命中作品 tag: EVA / 新世纪福音战士
结果: 返回该作品下的歌曲

用户输入: zankokunatenshi
IME: Mozc 只负责把 romaji 转成日文文本，可能分段提交 残酷 / 天使
FTS: 用原文歌名、假名、罗马音或作品 tag 索引召回歌曲
结果: 返回 残酷な天使のテーゼ

用户输入: qilixiang
IME: Rime 可能返回通用词库里的 七里香，也可能只提交拼音 raw input
FTS: 用歌曲标题、拼音字段或编号字段召回曲库条目
结果: 返回 七里香

用户手写: 残
IME: Zinnia 候选栏返回 残 / 歯 / ...
FTS: 用户选择 残 后继续搜索或追加输入
```

这个边界可以避免把服务器拖入无止境的别名维护，同时保留触控输入体验。

## 文件与模块规划

建议新增目录：

```text
lib/
  ime/
    ime_mode.dart
    ime_candidate.dart
    ime_composition.dart
    ime_engine.dart
    ime_controller.dart
    search_query_controller.dart
    engines/
      english_ime_engine.dart
      rime_ime_engine.dart
      mozc_ime_engine.dart
      zinnia_handwriting_engine.dart
    native/
      ime_native_bridge.dart
  ui/
    widgets/
      karaoke_input_panel.dart
      candidate_bar.dart
      touch_keyboard_layout.dart
      handwriting_pad.dart
```

release 路径只使用 App 自带 native runtime。原生组件加载或调用失败时，候选栏必须显示明确错误，不允许静默降级到固定词表或伪手写候选。

## 执行步骤

### Phase 0: 收口现有 UI

- 把 `_InputPanel` 从 browse screen 中拆成 `KaraokeInputPanel`。
- 把候选区域拆成 `CandidateBar`。
- 把键盘区域拆成 `TouchKeyboardLayout`。
- 保留当前视觉，不重新设计颜色。
- 确认触控输入和页面搜索 query 解耦。

验收：

- 歌名、歌手、分类页面都使用同一个输入面板组件。
- CandidateBar 空候选时保持固定高度。
- CandidateBar 有候选时可以点击提交。

### Phase 1: 输入状态机

- 新增 `ImeComposition`、`ImeCandidate`、`ImeEngine`。
- 新增 `ImeController`。
- 新增 `SearchQueryController`。
- 实现 `EnglishImeEngine`。
- 实现 mock 拼音、mock 日语、mock 手写。

验收：

- A-Z 键帽不直接写 TextField，而是走 `ImeController`。
- CandidateBar 显示 mock 候选。
- 点击候选后写入搜索 query。
- 退格、清空、空格、搜索按钮逻辑稳定。

### Phase 2: 硬件键盘与触控分流

- 触控面板点击时不弹系统软键盘。
- 硬件键盘输入时允许系统 IME 写入 query。
- 两个通道共用同一个 SearchQueryController。

验收：

- 鼠标/触控点击屏幕键盘时不出现系统软键盘。
- 外接键盘可以正常用系统中文/日文 IME。
- 两种通道都能触发页面搜索刷新。

### Phase 3: Rime spike

- Windows 先做 librime native bridge spike。
- 固定 schema，验证拼音候选。
- 做最小 DLL / FFI 调用。
- 不改 UI，只替换 `MockPinyinImeEngine`。

验收：

- 输入 `lv` / `lü` 类边界可处理。
- 输入拼音能返回中文候选。
- 候选分页可用。
- commit 后 SearchQueryController 更新。

### Phase 4: Mozc spike

- Windows 先做 Mozc native spike。
- 只验证 session、romaji input、candidate list、commit。
- 不接搜索页面。
- 锁定可构建 commit 和依赖。

验收：

- 输入 romaji 能拿到日语候选。
- 候选分页和 commit 可用。
- 不依赖系统日语 IME。
- 可以被 Flutter 通过统一 bridge 调用。

### Phase 5: Handwriting spike

- 先完成 Flutter 手写板。
- 接 mock handwriting engine。
- 再接 Zinnia。
- 单字候选进入 CandidateBar。

验收：

- 手写轨迹显示稳定。
- 清空、撤销一笔可用。
- 识别结果进 CandidateBar。
- 点击候选追加到搜索 query。

### Phase 6: Catalog 分类、索引包、本地 FTS 与资源拉取

- 定义服务器下发的 taxonomy manifest、ranking manifest 和 catalog index manifest。
- 支持本地服务器和云端服务器两种来源，API 结构保持一致。
- 云端服务器使用数据库管理歌曲、歌手、分类、榜单、资源版本和资源 URI。
- App 本地先允许 mock / JSON / 内存索引，后续按数据量和离线需求接 SQLite FTS。
- 本地导入 song、artist、tag、work、category、ranking、asset、version、hash 等索引字段。
- 本地搜索接入原文、编号、歌手、社团、番剧/作品 tag、服务器分类 tag、服务器歌手分类 tag。
- 本地派生拼音、罗马音、假名、简繁等辅助搜索字段。
- 选中歌曲后，通过 media asset URI 请求本地或云端资源服务。
- 媒体、封面、KRL 只进入播放周期临时缓存；索引可以持久缓存，资源字节不作为本地离线曲库。
- 播放时长由 App 打开的原唱音频实际时长决定，不把 duration 作为服务器必填字段。
- 输入法不加入曲库专名；曲库召回靠本地索引字段、派生读音字段和服务器下发的 tag。
- 歌名、歌手、分类、排行榜页面都消费服务器下发的 manifest，不在 UI 里写死列表。

验收：

- 替换服务器下发的分类 manifest 后，分类页和歌手页自动变化。
- 替换服务器下发的 ranking manifest 后，排行榜和子榜自动变化。
- 离线本地索引可搜索，不依赖公网实时查询。
- 搜番剧 / 作品 tag 可以返回对应歌曲。
- 搜歌曲编号、歌手、社团、声库、角色可召回。
- 点歌后可以从本地或云端资源 URI 拉取媒体、封面和 KRL。
- 服务器更新或删除资源后，本地临时资源不会被继续当作权威版本使用。
- 服务器无需提供每首歌的完整民间别名列表。

## 已完成的最小闭环

最小闭环先不依赖真实引擎，目标是让 UI 和状态机稳定：

1. 拆出 `KaraokeInputPanel`。
2. 新增 `ImeController` 和 `ImeEngine`。
3. 用 mock engine 填候选栏。
4. 点击候选写入搜索 query。
5. 让歌名、歌手、分类页全部走这个面板。

当前 Windows 版 Rime、Mozc 和 Zinnia 都已走真实 App 自带 runtime；运行时不再保留 mock 兜底。

## 参考

- Rime / librime: https://github.com/rime/librime
- Mozc: https://github.com/google/mozc
- Zinnia: https://taku910.github.io/zinnia/
- Anthy Unicode: https://github.com/fujiwarat/anthy-unicode
