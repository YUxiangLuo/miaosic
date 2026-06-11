import 'dart:io';

import 'package:path/path.dart' as p;

List<String> musicCoreLibraryCandidates() {
  if (!Platform.isLinux) {
    return const [];
  }

  final executableDir = p.dirname(Platform.resolvedExecutable);
  final cwd = Directory.current.path;
  return [
    'libmusic_core.so',
    p.join(executableDir, 'lib', 'libmusic_core.so'),
    p.join(cwd, 'native', 'music_core', 'target', 'debug', 'libmusic_core.so'),
    p.join(
      cwd,
      'native',
      'music_core',
      'target',
      'release',
      'libmusic_core.so',
    ),
    p.join(
      cwd,
      'build',
      'linux',
      'x64',
      'debug',
      'bundle',
      'lib',
      'libmusic_core.so',
    ),
    p.join(
      cwd,
      'build',
      'linux',
      'x64',
      'release',
      'bundle',
      'lib',
      'libmusic_core.so',
    ),
  ];
}
