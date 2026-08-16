import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef CoverCacheDirectoryProvider = Future<String> Function();

Future<String> coverCacheDir() async {
  final appDir = await getApplicationSupportDirectory();
  final dir = Directory(p.join(appDir.path, 'covers'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir.path;
}

String? legacyCoverCacheDirPath() {
  final env = Platform.environment;
  final dataHome = env['XDG_DATA_HOME']?.trim();
  final home = env['HOME']?.trim();
  if (dataHome != null && dataHome.isNotEmpty) {
    return p.join(dataHome, 'dev.vesein.miaosic', 'covers');
  }
  if (home != null && home.isNotEmpty) {
    return p.join(home, '.local', 'share', 'dev.vesein.miaosic', 'covers');
  }
  return null;
}

Future<int> migrateLegacyCoverCache({
  String? currentDirPath,
  String? legacyDirPath,
}) async {
  final currentPath = currentDirPath ?? await coverCacheDir();
  final legacyPath = legacyDirPath ?? legacyCoverCacheDirPath();
  if (legacyPath == null) {
    return 0;
  }

  final current = Directory(currentPath);
  final legacy = Directory(legacyPath);
  if (!await legacy.exists()) {
    return 0;
  }
  if (_normalizedAbsolutePath(current.path) ==
      _normalizedAbsolutePath(legacy.path)) {
    return 0;
  }
  if (!await current.exists()) {
    await current.create(recursive: true);
  }

  var moved = 0;
  await for (final entity in legacy.list(followLinks: false)) {
    if (entity is! File || !_isPrunableCoverFile(entity.path)) {
      continue;
    }
    final target = File(p.join(current.path, p.basename(entity.path)));
    if (await target.exists()) {
      await entity.delete();
      continue;
    }
    try {
      await entity.rename(target.path);
    } on FileSystemException {
      await entity.copy(target.path);
      await entity.delete();
    }
    moved += 1;
  }

  try {
    final leftover = await legacy.list(followLinks: false).isEmpty;
    if (leftover) {
      await legacy.delete();
    }
  } catch (_) {}
  return moved;
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
