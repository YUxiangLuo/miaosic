import 'models.dart';

Map<String, List<Track>> tracksByFolderMap(List<Track> tracks) {
  final grouped = <String, List<Track>>{};
  for (final track in tracks) {
    grouped.putIfAbsent(track.folderPath, () => []).add(track);
  }
  return grouped;
}

String formatDate(int ms) {
  final date = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${date.year}-${_two(date.month)}-${_two(date.day)}';
}

String formatElapsed(int? ms) {
  if (ms == null) {
    return '-';
  }
  return '${(ms / 1000).toStringAsFixed(1)}s';
}

String formatDurationMs(int? durationMs) {
  if (durationMs == null || durationMs <= 0) {
    return '-';
  }
  return formatDuration(Duration(milliseconds: durationMs));
}

String formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _two(int value) => value.toString().padLeft(2, '0');
