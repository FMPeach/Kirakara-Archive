# 跨子网 DLNA Renderer 手动发现

Kirakara 保留原有 `239.255.255.250:1900` SSDP multicast 发现，并为 multicast
无法穿过 VLAN 的环境增加显式 Renderer 回退。两条发现路径最终都生成同一个
`DlnaDevice`，继续复用既有 `CastService` 与 `DlnaControlPoint`，没有独立的投屏实现。

## 使用方式

1. 打开“显示输出”，启用“无线投屏”。
2. 选择“手动添加 DLNA 设备”。
3. 跨 VLAN 时优先输入完整 description URL，例如：
   `http://192.168.254.7:49152/description.xml`。
4. 也可以只输入 IPv4 地址。此时 App 会向该地址的 UDP 1900 发送一次有界的
   unicast M-SEARCH；若设备不响应，界面会要求改用完整 description URL，不会扫描
   端口或尝试把 multicast 强行扩散到其他子网。
5. 设备加入列表后，点击设备行即可进入原有 Cast 流程。

在纯K网络完成官方二维码授权后，可以在“设置 → 投屏”中启用
“深度搜索（慎用）”。该设置默认关闭；启用后，App 会在保留原有 SSDP 发现的同时，
仅探测以下固定范围：

```text
http://192.168.254.1:49152/description.xml
...
http://192.168.254.254:49152/description.xml
```

扫描使用 24 个并发请求和 400 ms 单请求总时限，不访问其他网段或端口。扫描阶段只
执行 description XML 的 HTTP GET，不会向任何候选设备发送 Play、Stop 或
SetAVTransportURI。所有合法 Renderer 都先加入列表，仍需由用户明确选择投屏目标。

手动添加只保留在当前 App 进程内，不写入设置。关闭再开启无线投屏或刷新设备时，
本次进程中已添加的设备仍会参与合并；重启 App 后需要重新添加。

## 去重与日志

设备优先按 description 中的 UDN/UUID 去重；缺少 UDN 时依次按规范化后的
description URL 和 Renderer IP 去重。显式设备在与 multicast 结果相同时保留显式
路径，避免刷新后重新出现两条记录。

纯K扫描在当前进程内记住成功地址，并在下一次扫描时优先探测；不会把网络探测结果
写入设置或跨进程持久化。

每个成功解析的 Renderer 会输出一条 `[dlna-discovery]` 日志，字段包括：

- `discoverySource`：`ssdp`、`purek-http` 或 `manual-url`；
- `source`：SSDP 的细分来源 `ssdp-multicast` / `ssdp-unicast`，或其他发现来源；
- `sourceInterface`：本机接口名称与 IPv4；
- `rendererIP`、`descriptionURL`、`friendlyName`、`UDN`；
- `manufacturer`、`modelName`；
- `avTransport`：解析后的 AVTransport control URL。

## Pure K 现场验收

在 Pure K 网络中完成官方投屏二维码授权后，先在“设置 → 投屏”启用
“深度搜索（慎用）”，再打开“显示输出”并启用“无线投屏”。等待扫描完成后，预期
无需输入 IP 即可在列表中看到当前可达的“纯K-K07”“纯K-K08”等设备。日志中应出现
`discoverySource=purek-http`、对应 UDN 和 AVTransport control URL。随后由用户点击
目标设备，验证与普通 SSDP 设备相同的投屏启动、停止和重复连接行为；多台设备同时
可达时不得自动选择，若同一设备也被 SSDP 找到，列表仍只能显示一条。

若需要单独验证此前的手动回退，也可输入完整 URL，例如：

```text
http://192.168.254.7:49152/description.xml
```

开发环境也可执行：

```powershell
& 'D:\Program Files\Flutter\bin\dart.bat' run .\tool\dlna_probe.dart `
  'http://192.168.254.7:49152/description.xml'
```

该探针只读取 description 并查询 ConnectionManager，不会启动 Cast 播放。

扫描固定纯K范围可执行：

```powershell
& 'D:\Program Files\Flutter\bin\dart.bat' run .\tool\dlna_probe.dart --purek
```
