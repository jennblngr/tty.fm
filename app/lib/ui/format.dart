String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// "12 titres · 48 min"
String formatCountDuration(int count, int durationMs) {
  final mins = (durationMs / 60000).round();
  final dur = mins >= 60 ? '${mins ~/ 60} h ${mins % 60} min' : '$mins min';
  return '$count titre${count > 1 ? 's' : ''} · $dur';
}
