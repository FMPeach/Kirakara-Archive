# Kirakara Catalog API v1

## 总体设计

Kirakara-App 是 local-first KTV 主机。服务器对 App 只提供 catalog
权威索引和资源文件；App 拉取索引后写入本地 IndexCache / SQLite /
FTS，自行完成搜索、过滤、歌手页、分类页和排行榜 join。

```text
Server catalog/resource API            Kirakara-App
┌──────────────────────────┐          ┌──────────────────────────────┐
│ GET /api/catalog/artists  │ ──全量──→ │ IndexCache (SQLite / FTS)    │
│ GET /api/catalog/songs    │          │   songs / artists / category │
│ GET /api/catalog/categories│          │   local join / search        │
│ GET /api/catalog/rankings │          ├──────────────────────────────┤
│ GET /media/**             │ ─点歌时→ │ PlaybackAssetCache           │
└──────────────────────────┘          │   current-cycle assets only   │
                                      └──────────────────────────────┘
```

核心边界：

- 服务器是 dumb data source，App 是 smart cache + search engine。
- App 默认歌曲展示只使用 `title` 和 `artistLine`。
- `artists` 只表示服务器已经归一的 canonical entity；不是每个文本歌手名都必须进入 `artists`。
- `credits` 可以保存未归一的人名、角色名、原曲名等文本信息。
- 媒体、封面、KRL 只进入 `PlaybackAssetCache`，不是本地离线曲库。
- 房间实时状态仍只由本机 App 管理。

## 基础约定

- `$BASE` = 服务器地址，本地服务器、NAS、云端都使用同一套 API。
- JSON 端点返回 `Content-Type: application/json; charset=utf-8`。
- URI 使用相对路径，例如 `/media/songs/20001/vocal.wav`，App 用 `$BASE + uri`。
- App 可能附加 `?r=<random>` 破缓存，服务端应忽略未知 query 参数。
- 返回可以是裸数组。若包一层，只保留有实际用途的字段，例如 `schemaVersion`、`revision`、`items`。
- 不要求服务器提供 `duration`。播放时长、进度和自动切歌以 App 打开的原唱音频实际时长为准。
- 公开关联 ID 使用服务器分配的数字字符串，不携带名称、罗马音、分类语义。
- 歌曲 ID 是点歌编号，也使用数字字符串。

## 端点一览

| # | 方法 | 路径 | 说明 |
|---|------|------|------|
| 1 | `GET` | `/api/catalog/artists` | 已归一歌手 / 组合 / 社团 / 角色 / 声优 / 声库等实体 |
| 2 | `GET` | `/api/catalog/songs` | 歌曲全量索引 |
| 3 | `GET` | `/api/catalog/categories` | 歌曲分类和歌手分组 |
| 4 | `GET` | `/api/catalog/rankings` | 榜单，只引用 `songId` |
| - | `GET` | `/media/**` | 静态资源文件 |

## 1. `GET /api/catalog/artists`

`artists` 是已归一实体表。它用于搜索、歌手页和关系 join，不要求覆盖
所有歌曲署名文本。排序名、拼音、罗马音、假名等搜索 token 由 App 或
服务器内部生成，不作为公开必填字段。

### JSON 示例

```json
[
  {
    "id": "3",
    "name": "ナナツカゼ",
    "type": "solo",
    "categoryIds": ["201"],
    "note": "本地 KRL / 实机测试",
    "avatarUri": null
  },
  {
    "id": "10",
    "name": "Alstroemeria Records",
    "type": "circle",
    "categoryIds": ["203"],
    "note": "东方同人社团",
    "avatarUri": null
  },
  {
    "id": "20",
    "name": "平沢唯",
    "type": "character",
    "categoryIds": ["204"],
    "note": "けいおん！",
    "avatarUri": null
  },
  {
    "id": "21",
    "name": "豊崎愛生",
    "type": "voice_actor",
    "categoryIds": ["205"],
    "note": null,
    "avatarUri": null
  },
  {
    "id": "30",
    "name": "初音ミク",
    "type": "vocal_synth",
    "categoryIds": ["202"],
    "note": null,
    "avatarUri": "/media/artists/30/avatar.jpg"
  }
]
```

### 字段表

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | `string` | yes | 服务器分配的数字字符串，不携带语义 |
| `name` | `string` | yes | 展示名 |
| `type` | `string` | yes | `solo` / `group` / `circle` / `character` / `voice_actor` / `vocal_synth` / `creator` / `other` |
| `categoryIds` | `string[]` | no | 指向 `categories.type = "artist"` 的分组，数字字符串 |
| `note` | `string?` | no | 一行备注 |
| `avatarUri` | `string?` | no | 相对路径 |

## 2. `GET /api/catalog/songs`

歌曲索引面向 App 展示和本地搜索。`artistLine` 是默认 UI 的唯一歌手行；
App 不需要根据 `artistRefs` 或 `credits` 拼接默认署名。

### JSON 示例

```json
[
  {
    "id": "20001",
    "title": "七ツ風",
    "artistLine": "ナナツカゼ",
    "primaryArtistId": "3",
    "artistRefs": [
      { "id": "3", "role": "vocal", "display": true }
    ],
    "categoryIds": ["199"],
    "tags": ["日文", "KRL"],
    "searchHints": ["Nanatsukaze", "七风"],
    "coverColor": "14bfd0",
    "assets": [
      { "type": "video", "uri": "/media/songs/20001/background.mp4", "version": 1, "hash": "sha256:a1b2c3...", "size": 52428800 },
      { "type": "vocal", "uri": "/media/songs/20001/vocal.wav", "version": 1, "hash": "sha256:b2c3d4...", "size": 4194304 },
      { "type": "inst", "uri": "/media/songs/20001/inst.wav", "version": 1, "hash": "sha256:c3d4e5...", "size": 4194304 },
      { "type": "cover", "uri": "/media/songs/20001/cover.jpg", "version": 1, "hash": "sha256:d4e5f6...", "size": 102400 },
      { "type": "krl", "uri": "/media/songs/20001/lyrics.krl", "version": 3, "hash": "sha256:e5f6a7...", "size": 12800 }
    ]
  },
  {
    "id": "20002",
    "title": "怒り[VOCALOID ver.] (feat. Noz.)",
    "artistLine": "カンザキイオリ feat. 初音ミク, 鏡音リン",
    "artistRefs": [
      { "id": "5", "role": "creator", "display": false },
      { "id": "30", "role": "vocal_synth", "display": true },
      { "id": "31", "role": "vocal_synth", "display": true }
    ],
    "credits": [
      { "name": "Noz.", "role": "featured", "entityId": null, "display": true }
    ],
    "categoryIds": ["103"],
    "tags": ["VOCALOID", "初音ミク", "鏡音リン", "KRL"],
    "searchHints": ["ikari"],
    "coverColor": "e95895",
    "assets": [
      { "type": "video", "uri": "/media/songs/20002/background.mp4", "version": 1, "hash": "sha256:f6a7b8...", "size": 62914560 },
      { "type": "vocal", "uri": "/media/songs/20002/vocal.wav", "version": 1, "hash": "sha256:a7b8c9...", "size": 5242880 },
      { "type": "inst", "uri": "/media/songs/20002/inst.wav", "version": 1, "hash": "sha256:b8c9d0...", "size": 5242880 },
      { "type": "cover", "uri": "/media/songs/20002/cover.jpg", "version": 1, "hash": "sha256:c9d0e1...", "size": 81920 },
      { "type": "krl", "uri": "/media/songs/20002/lyrics.krl", "version": 2, "hash": "sha256:d0e1f2...", "size": 9600 }
    ]
  },
  {
    "id": "20003",
    "title": "Bad Apple!!",
    "artistLine": "nomico",
    "primaryArtistId": "11",
    "artistRefs": [
      { "id": "11", "role": "vocal", "display": true },
      { "id": "10", "role": "circle", "display": false }
    ],
    "circleIds": ["10"],
    "credits": [
      { "name": "ZUN", "role": "original_composer", "entityId": "13", "display": false },
      { "name": "Bad Apple!!", "role": "original_track", "entityId": null, "display": false },
      { "name": "東方幻想郷", "role": "original_work", "entityId": "501", "display": false }
    ],
    "categoryIds": ["104"],
    "workIds": ["501"],
    "tags": ["東方", "Touhou", "同人", "经典"],
    "searchHints": ["Bad Apple", "nomico", "Alstroemeria Records"],
    "coverColor": "4c36b8",
    "assets": [
      { "type": "video", "uri": "/media/songs/20003/background.mp4", "version": 1, "hash": "sha256:e1f2a3...", "size": 73400320 },
      { "type": "vocal", "uri": "/media/songs/20003/vocal.wav", "version": 1, "hash": "sha256:f2a3b4...", "size": 6291456 },
      { "type": "inst", "uri": "/media/songs/20003/inst.wav", "version": 1, "hash": "sha256:a3b4c5...", "size": 6291456 },
      { "type": "cover", "uri": "/media/songs/20003/cover.jpg", "version": 1, "hash": "sha256:b4c5d6...", "size": 122880 },
      { "type": "krl", "uri": "/media/songs/20003/lyrics.krl", "version": 1, "hash": "sha256:c5d6e7...", "size": 11200 }
    ]
  },
  {
    "id": "20004",
    "title": "ふわふわ時間",
    "artistLine": "平沢唯 (CV: 豊崎愛生)",
    "primaryArtistId": "20",
    "artistRefs": [
      { "id": "20", "role": "character_vocal", "display": true },
      { "id": "21", "role": "voice_actor", "display": false }
    ],
    "categoryIds": ["102", "105"],
    "workIds": ["502"],
    "tags": ["けいおん！", "K-ON!", "角色歌", "日文"],
    "coverColor": "f2b84b",
    "assets": [
      { "type": "video", "uri": "/media/songs/20004/background.mp4", "version": 1, "hash": "sha256:d6e7f8...", "size": 41943040 },
      { "type": "vocal", "uri": "/media/songs/20004/vocal.wav", "version": 1, "hash": "sha256:e7f8a9...", "size": 4718592 },
      { "type": "inst", "uri": "/media/songs/20004/inst.wav", "version": 1, "hash": "sha256:f8a9b0...", "size": 4718592 },
      { "type": "cover", "uri": "/media/songs/20004/cover.jpg", "version": 1, "hash": "sha256:a9b0c1...", "size": 94208 },
      { "type": "krl", "uri": "/media/songs/20004/lyrics.krl", "version": 1, "hash": "sha256:b0c1d2...", "size": 8500 }
    ]
  }
]
```

### 字段表

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | `string` | yes | 点歌编号，数字字符串 |
| `title` | `string` | yes | 歌曲标题 |
| `artistLine` | `string` | yes | UI 默认显示的歌手行 |
| `primaryArtistId` | `string?` | no | 主要 canonical artist ID，可空，数字字符串 |
| `artistRefs` | `object[]?` | no | 已归一 artist entity 关系 |
| `credits` | `object[]?` | no | 松散 credit，可只保存 `name` |
| `circleIds` | `string[]?` | no | 东方 / 同人社团快捷关系 |
| `categoryIds` | `string[]` | yes | 歌曲分类 ID，可为空数组，数字字符串 |
| `workIds` | `string[]?` | no | 作品 ID，例如动画、游戏、东方原作，数字字符串 |
| `tags` | `string[]` | no | 结构化 tag |
| `searchHints` | `string[]?` | no | 少量人工召回词，不承担大规模别名库 |
| `coverColor` | `string?` | no | 6 位 hex，无 `#` 前缀 |
| `assets` | `object[]` | yes | 播放资源 |

### `artistRefs`

`artistRefs` 只引用已归一 `artists.id`。如果某个名字无法归一，不要硬塞进
`artists`，放入 `credits` 即可。

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | `string` | yes | 指向 `artists.id`，数字字符串 |
| `role` | `string` | yes | 关系角色 |
| `display` | `bool` | no | 是否适合在完整 credits 中默认展开 |

常见 role：

| 值 | 含义 |
|----|------|
| `vocal` | 人声演唱 |
| `character_vocal` | 角色名义演唱 |
| `voice_actor` | 声优 / CV |
| `vocal_synth` | 声库 / 虚拟歌手 |
| `circle` | 同人社团 |
| `creator` | 创作者 |
| `featured` | feat. / guest |
| `composer` | 作曲 |
| `arranger` | 编曲 |

### `credits`

`credits` 用于保留松散文本关系。它可以有 `entityId`，也可以没有。
App 搜索时可索引 `name`；如果 `entityId` 存在，也可 join 到 artist 或 work。

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | `string` | yes | credit 文本 |
| `role` | `string` | yes | credit 类型 |
| `entityId` | `string?` | no | 已归一实体 ID，可空，数字字符串 |
| `display` | `bool` | no | 是否适合在完整 credits 中默认展开 |

常见 role：

| 值 | 含义 |
|----|------|
| `voice_actor` | 声优 / CV |
| `featured` | feat. / guest |
| `lyricist` | 作词 |
| `composer` | 作曲 |
| `arranger` | 编曲 |
| `original_composer` | 原曲作曲 |
| `original_track` | 原曲曲名 |
| `original_work` | 原作 / 作品 |

### `assets`

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `type` | `string` | yes | `video` / `vocal` / `inst` / `cover` / `krl` |
| `uri` | `string` | yes | 相对路径 |
| `version` | `int` | yes | 服务器控制的资源版本 |
| `hash` | `string` | yes | 例如 `sha256:<hex>` |
| `size` | `int` | yes | 字节数 |

`inst` 是伴奏音轨的短名。App 下载后应按 `version` / `hash` / `size`
校验，校验失败即丢弃。

## 3. `GET /api/catalog/categories`

分类是服务器下发的展示/筛选维度，关联使用稳定 `id`，不要使用 `name`。

### JSON 示例

```json
[
  { "id": "101", "type": "song", "name": "热门", "note": "最近常点与推荐曲目", "order": 1 },
  { "id": "102", "type": "song", "name": "动画", "note": "番剧 OP / ED / 插曲", "order": 2 },
  { "id": "103", "type": "song", "name": "VOCALOID", "note": "术力口与创作者曲目", "order": 3 },
  { "id": "104", "type": "song", "name": "东方", "note": "东方同人与社团作品", "order": 4 },
  { "id": "105", "type": "song", "name": "角色歌", "note": "角色名义演唱曲目", "order": 5 },
  { "id": "199", "type": "song", "name": "本地实机", "note": "开发测试曲目", "order": 99 },
  { "id": "201", "type": "artist", "name": "日本歌手/组合", "note": null, "order": 1 },
  { "id": "202", "type": "artist", "name": "VOCALOID 声库", "note": null, "order": 2 },
  { "id": "203", "type": "artist", "name": "同人社团", "note": null, "order": 3 },
  { "id": "204", "type": "artist", "name": "ACG 角色", "note": null, "order": 4 },
  { "id": "205", "type": "artist", "name": "声优", "note": null, "order": 5 }
]
```

### 字段表

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | `string` | yes | 服务器分配的数字字符串，不携带语义 |
| `type` | `string` | yes | `song` / `artist` |
| `name` | `string` | yes | 展示名 |
| `note` | `string?` | no | 一行备注 |
| `order` | `int?` | no | 排序权重，越小越前 |

## 4. `GET /api/catalog/rankings`

排行榜由服务器计算，但结果只引用 `songId`。App 用本地 songs 表 join 展示。

### 请求

```text
GET /api/catalog/rankings
GET /api/catalog/rankings?category=102
```

### JSON 示例

```json
[
  {
    "categoryId": null,
    "name": "总榜",
    "entries": [
      { "rank": 1, "songId": "20004", "playCount": 12580 },
      { "rank": 2, "songId": "20003", "playCount": 9800 }
    ]
  },
  {
    "categoryId": "103",
    "name": "VOCALOID",
    "entries": [
      { "rank": 1, "songId": "20002", "playCount": 6400 }
    ]
  }
]
```

### 字段表

| 字段 | 类型 | 说明 |
|------|------|------|
| `categoryId` | `string?` | `null` 表示总榜 |
| `name` | `string` | 榜单展示名 |
| `entries[].rank` | `int` | 排名 |
| `entries[].songId` | `string` | 指向歌曲 ID |
| `entries[].score` | `number?` | 服务器计算分数，可选 |
| `entries[].playCount` | `int?` | 播放次数，可选 |

## 5. 静态资源 `GET /media/**`

普通文件下载，不返回 JSON。`assets[].uri` 和 `avatarUri` 指向这里。

```text
/media/songs/20001/background.mp4
/media/songs/20001/vocal.wav
/media/songs/20001/inst.wav
/media/songs/20001/cover.jpg
/media/songs/20001/lyrics.krl
/media/artists/30/avatar.jpg
```

App 下载后写入 `PlaybackAssetCache`，并按 `version` / `hash` / `size`
校验。服务端资源更新、删除、校验失败、播放结束、切歌、App 退出或缓存压力
出现时，本地临时资源可以被清理。

## App 同步和本地导入

推荐导入流程：

```text
GET /api/catalog/artists
GET /api/catalog/songs
GET /api/catalog/categories
GET /api/catalog/rankings
  -> replace IndexCache transactionally
  -> rebuild FTS
  -> browse/search/join locally
  -> request /media/** only when playback needs assets
```

JSON 中的数组字段可以保留，但导入 SQLite 时建议拆成关系表，不要用字符串
`LIKE` 搜 JSON，也不要把 `json_extract` 当作主路径。

推荐表：

| 表 | 说明 |
|----|------|
| `songs` | 歌曲基础字段，含 `title`、`artist_line`、`primary_artist_id` |
| `artists` | 已归一 artist entity |
| `categories` | 分类 |
| `song_artists(song_id, artist_id, role, display)` | 已归一 artist 关系 |
| `song_credits(song_id, name, role, entity_id, display)` | 松散 credit |
| `song_categories(song_id, category_id)` | 歌曲分类 |
| `song_assets(song_id, type, uri, version, hash, size)` | 资源 |
| `song_tags(song_id, tag)` | tag |
| `song_search_hints(song_id, value)` | 少量召回词 |
| `songs_fts` | FTS 索引 |

本地查询示例：

```sql
-- 某分类下的歌曲
SELECT s.*
FROM songs s
JOIN song_categories sc ON sc.song_id = s.id
WHERE sc.category_id = ?;

-- 某 canonical artist 相关歌曲
SELECT s.*
FROM songs s
JOIN song_artists sa ON sa.song_id = s.id
WHERE sa.artist_id = ?;

-- 某声优参与的角色歌
SELECT s.*
FROM songs s
JOIN song_credits c ON c.song_id = s.id
WHERE c.entity_id = ? AND c.role = 'voice_actor';
```

## A(CV:B) 与东方同人的约定

动画角色歌：

- 默认展示只看 `artistLine`，例如 `平沢唯 (CV: 豊崎愛生)`。
- A 的页面只展示 A 名义下的歌。
- B 的页面可以展示 B 作为声优 / 演唱者参与的相关歌曲。
- 这种关系通过 `artistRefs` 或 `credits` 表达，不要求 App 自己拼默认署名。

东方 / 同人：

- 社团可以是 `artists.type = "circle"`，也可以通过 `circleIds` 快速索引。
- 原曲、原作、ZUN、arranger 等信息放入 `credits` 或 `workIds`。
- 点歌列表默认仍只显示 `title` + `artistLine`。
- 如果歌曲有明确演唱者，`artistLine` 优先写演唱者；社团用于搜索、
  详情扩展和 `circleIds` 关联。

## PlaybackAssetCache

`PlaybackAssetCache` 是播放周期缓存：

- 缓存当前播放或即将播放所需的 video / vocal / inst / cover / krl。
- 不承诺离线长期播放已经缓存过的媒体资源。
- 服务端资源版本或 hash 变化时，旧缓存失效。
- App 退出、切歌、缓存压力或校验失败时可以清理。

## 不做的事

| 不做 | 原因 |
|------|------|
| 服务端搜索端点 | App 已有全量索引和 FTS |
| `/artists/{id}` | 本地 artists 表可直接查询 |
| `/songs/{id}` | 本地 songs 表可直接查询 |
| `/categories/{id}/songs` | 本地 `song_categories` join |
| 分类用显示名做关联键 | 显示名会变，关联必须用稳定 ID |
| App 根据 credits 拼默认歌手行 | 默认展示由 `artistLine` 决定 |
| 要求每个文本歌手名都进入 artists | UGC/来源数据无法保证完全归一 |
| 排行榜内嵌完整歌曲对象 | App 本地 join 即可 |
| 服务器传 `duration` | 以实际打开的原唱音频时长为准 |
| 服务器维护大规模别名库 | 搜索靠本地 token、tag、searchHints 和 FTS |
| 媒体资源做本地离线曲库 | `PlaybackAssetCache` 是临时缓存 |
