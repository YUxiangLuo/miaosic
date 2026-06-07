import 'dart:io';

import 'package:path/path.dart' as p;

Future<String> coverCacheDir() async {
  final env = Platform.environment;
  final dataHome =
      env['XDG_DATA_HOME'] ??
      (env['HOME'] == null
          ? p.join(Directory.systemTemp.path, 'miaosic')
          : p.join(env['HOME']!, '.local', 'share'));
  final dir = Directory(p.join(dataHome, 'dev.vesein.miaosic', 'covers'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir.path;
}

Future<int> pruneCoverCacheFiles(
  Set<String> referencedPaths, {
  String? cacheDirPath,
}) async {
  final dirPath = cacheDirPath ?? await coverCacheDir();
  final dir = Directory(dirPath);
  if (!await dir.exists()) {
    return 0;
  }

  final referenced = referencedPaths.map(_normalizedAbsolutePath).toSet();
  var deleted = 0;
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File || !_isPrunableCoverFile(entity.path)) {
      continue;
    }
    final path = _normalizedAbsolutePath(entity.path);
    if (referenced.contains(path)) {
      continue;
    }
    await entity.delete();
    deleted++;
  }
  return deleted;
}

String _normalizedAbsolutePath(String path) {
  return p.normalize(File(path).absolute.path);
}

bool _isPrunableCoverFile(String path) {
  return switch (p.extension(path).toLowerCase()) {
    '.jpg' || '.jpeg' || '.png' => true,
    _ => false,
  };
}
