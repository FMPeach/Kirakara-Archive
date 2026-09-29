int parseCompositorSoakSeconds(String? raw) {
  final normalized = raw?.trim();
  if (normalized == null || normalized.isEmpty) {
    return 0;
  }
  final value = int.tryParse(normalized);
  if (value == 0) {
    return 0;
  }
  if (value == null || value < 30 || value > 14400) {
    throw StateError(
      'KIRAKARA_COMPOSITOR_SOAK_SECONDS must be between 30 and 14400.',
    );
  }
  return value;
}
