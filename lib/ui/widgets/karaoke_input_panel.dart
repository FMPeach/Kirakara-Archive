import 'package:flutter/material.dart';

import '../theme/kirakara_theme.dart';
import 'candidate_bar.dart';
import 'touch_keyboard_layout.dart';

class KaraokeInputPanel extends StatelessWidget {
  const KaraokeInputPanel({
    super.key,
    required this.activeTab,
    required this.placeholder,
    required this.controller,
    required this.imeMode,
    required this.onChanged,
    required this.onTab,
    required this.onKey,
    required this.onImeMode,
    this.tabs = const ['歌名', '歌手', '分类'],
  });

  final String activeTab;
  final String placeholder;
  final TextEditingController controller;
  final String imeMode;
  final List<String> tabs;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onTab;
  final ValueChanged<String> onKey;
  final ValueChanged<String> onImeMode;

  static const _letters = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    '退格',
    '清空',
    '空格',
    '搜索',
  ];
  static const _imeModes = ['英文', '拼音', '日语罗马音', '手写'];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: const Color(0x0EFFFFFF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x14FFFFFF)),
              ),
              child: Row(
                children: [
                  for (final tab in tabs)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Material(
                          color: activeTab == tab
                              ? KiraColors.red
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            onTap: () => onTab(tab),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              height: 50,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: activeTab == tab
                                      ? const Color(0x38FFFFFF)
                                      : Colors.transparent,
                                ),
                              ),
                              child: Text(
                                tab,
                                style: TextStyle(
                                  color: activeTab == tab
                                      ? Colors.white
                                      : const Color(0xC7FFFFFF),
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 60,
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                decoration: InputDecoration(
                  hintText: placeholder,
                  hintStyle: const TextStyle(
                    color: Color(0x8effffff),
                    fontWeight: FontWeight.w700,
                  ),
                  prefixIcon: const Icon(Icons.search, color: Color(0xccffffff)),
                  filled: true,
                  fillColor: const Color(0x18ffffff),
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: KiraColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: KiraColors.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: KiraColors.lineStrong),
                  ),
                ),
                style: const TextStyle(
                  color: KiraColors.cream,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),
            CandidateBar(
              candidates: const [],
              onCandidateSelected: onKey,
            ),
            TouchKeyboardLayout(keys: _letters, onKey: onKey),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: KiraColors.line)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final mode in _imeModes) ...[
                    TextButton(
                      onPressed: () => onImeMode(mode),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        foregroundColor: imeMode == mode
                            ? KiraColors.amber
                            : KiraColors.muted,
                      ),
                      child: Text(
                        mode,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (mode != _imeModes.last) const SizedBox(width: 4),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _panelDecoration() {
  return BoxDecoration(
    color: KiraColors.surface,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: KiraColors.line),
  );
}
