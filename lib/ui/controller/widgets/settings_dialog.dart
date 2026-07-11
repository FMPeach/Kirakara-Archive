part of '../../screens/controller_screen.dart';

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.settingsService,
    required this.assetCache,
    required this.lanServer,
  });

  final SettingsService settingsService;
  final PlaybackAssetCache assetCache;
  final LanServer lanServer;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final TextEditingController _announcementController;
  late Future<int> _cacheSize;
  bool _savingAnnouncement = false;
  bool _startingLan = false;

  @override
  void initState() {
    super.initState();
    _announcementController = TextEditingController(
      text: widget.settingsService.customAnnouncement,
    );
    _cacheSize = widget.assetCache.cacheSizeBytes();
  }

  @override
  void dispose() {
    _announcementController.dispose();
    super.dispose();
  }

  Future<void> _saveAnnouncement() async {
    setState(() => _savingAnnouncement = true);
    await widget.settingsService.setCustomAnnouncement(
      _announcementController.text,
    );
    if (mounted) setState(() => _savingAnnouncement = false);
  }

  Future<void> _startLanServer() async {
    setState(() => _startingLan = true);
    try {
      await widget.lanServer.start();
    } finally {
      if (mounted) setState(() => _startingLan = false);
    }
  }

  void _refreshCacheSize() {
    setState(() => _cacheSize = widget.assetCache.cacheSizeBytes());
  }

  @override
  Widget build(BuildContext context) {
    return _KiraDialog(
      title: '设置',
      width: 760,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 720),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SettingsSectionTitle(
                icon: Icons.campaign_outlined,
                title: '报幕文字',
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _announcementController,
                      maxLength: 120,
                      minLines: 1,
                      maxLines: 2,
                      onSubmitted: (_) => _saveAnnouncement(),
                      decoration: const InputDecoration(
                        hintText: '留空则不显示自定义文字',
                        filled: true,
                        fillColor: KiraColors.surface2,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _savingAnnouncement ? null : _saveAnnouncement,
                      icon: _savingAnnouncement
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: const Text('应用'),
                    ),
                  ),
                ],
              ),
              const _SettingsDivider(),
              const _SettingsSectionTitle(
                icon: Icons.router_outlined,
                title: '手机点歌服务',
              ),
              const SizedBox(height: 12),
              _SettingsValueRow(
                label: widget.lanServer.isRunning
                    ? '已启动：${widget.lanServer.localUri}'
                    : '未启动',
                trailing: widget.lanServer.isRunning
                    ? const Icon(Icons.check_circle, color: KiraColors.teal)
                    : TextButton.icon(
                        onPressed: _startingLan ? null : _startLanServer,
                        icon: _startingLan
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        label: const Text('重试'),
                      ),
              ),
              const _SettingsDivider(),
              const _SettingsSectionTitle(
                icon: Icons.storage_outlined,
                title: '媒体缓存',
              ),
              const SizedBox(height: 12),
              _SettingsValueRow(
                label: '队列预缓存范围',
                trailing: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('1 首')),
                    ButtonSegment(value: 2, label: Text('2 首')),
                    ButtonSegment(value: 3, label: Text('3 首')),
                  ],
                  selected: {widget.settingsService.prefetchLookahead},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) async {
                    await widget.settingsService
                        .setPrefetchLookahead(value.first);
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const SizedBox(height: 10),
              _SettingsValueRow(
                label: '本次运行占用',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FutureBuilder<int>(
                      future: _cacheSize,
                      builder: (context, snapshot) {
                        return Text(
                          snapshot.hasData
                              ? _formatSettingBytes(snapshot.data!)
                              : '计算中…',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '刷新缓存用量',
                      onPressed: _refreshCacheSize,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _SettingsValueRow(
                label: '缓存目录',
                trailing: Expanded(
                  child: SelectableText(
                    widget.assetCache.cacheDirectoryPath,
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: KiraColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const _SettingsValueRow(
                label: '退出应用自动清理',
                trailing: Icon(Icons.check, color: KiraColors.teal),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatSettingBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: KiraColors.amber),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _SettingsValueRow extends StatelessWidget {
  const _SettingsValueRow({required this.label, required this.trailing});

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: KiraColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 18),
          const Spacer(),
          trailing,
        ],
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Divider(height: 1, color: KiraColors.line),
    );
  }
}
