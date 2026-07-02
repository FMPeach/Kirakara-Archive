import 'package:flutter/material.dart';

import '../theme/kirakara_theme.dart';

class CandidateBar extends StatelessWidget {
  const CandidateBar({
    super.key,
    required this.candidates,
    required this.onCandidateSelected,
  });

  final List<String> candidates;
  final ValueChanged<String> onCandidateSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: KiraColors.line)),
      ),
      child: Row(
        children: [
          for (final candidate in candidates)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _CandidateChip(
                text: candidate,
                onTap: () => onCandidateSelected(candidate),
              ),
            ),
        ],
      ),
    );
  }
}

class _CandidateChip extends StatelessWidget {
  const _CandidateChip({
    required this.text,
    required this.onTap,
  });

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: KiraColors.surface2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: KiraColors.line),
          ),
          child: Center(
            child: Text(
              text,
              style: const TextStyle(
                color: KiraColors.cream,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
