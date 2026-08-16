import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef CoverCacheDirectoryProvider = Future<String> Function();

class CoverCacheMigration {
  const CoverCacheMigration({
    required this.currentDir,
    this.legacyDir,
    this.processedFiles = 0,
  });

  final String currentDir;
  final String? legacyDir;
  final int processedFiles;

  bool get shouldRewritePaths {
    final legacy = legacyDir;
    if (legacy == null || processedFiles <= 0) {
      return false;
    }
    return normalizedAbsolutePath(legacy) != normalizedAbsolutePath(currentDir);
  }
}

Future<String> coverCacheDir() async {
  try {
    final appDir = await getApplicationSupportDirectory();
    return _ensureCoverDir(p.join(appDir.path, 'covers'));
  } catch (_) {
    return fallbackCoverCacheDir();
  }
}

String fallbackCoverCacheDir() {
  final env = Platform.environment;
  final dataHome = env['XDG_DATA_HOME']?.trim();
  final home = env['HOME']?.trim();
  final root = dataHome != null && dataHome.isNotEmpty
      ? dataHome
      : (home != null && home.isNotEmpty
            ? p.join(home, '.local', 'share')
            : p.join(Directory.systemTemp.path, 'miaosic'));
  return _ensureCoverDirSync(p.join(root, 'dev.vesein.miaosic', 'covers'));
}

Future<String> _ensureCoverDir(String path) async {
  final dir = Directory(path);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir.path;
}

String _ensureCoverDirSync(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
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

Future<CoverCacheMigration> migrateLegacyCoverCache({
  String? currentDirPath,
  String? legacyDirPath,
}) async {
  final currentPath = currentDirPath ?? await coverCacheDir();
  final legacyPath = legacyDirPath ?? legacyCoverCacheDirPath();
  if (legacyPath == null) {
    return CoverCacheMigration(currentDir: currentPath);
  }

  final current = Directory(currentPath);
  final legacy = Directory(legacyPath);
  if (!await legacy.exists()) {
    return CoverCacheMigration(currentDir: currentPath, legacyDir: legacyPath);
  }
  if (normalizedAbsolutePath(current.path) ==
      normalizedAbsolutePath(legacy.path)) {
    return CoverCacheMigration(currentDir: currentPath, legacyDir: legacyPath);
  }
  if (!await current.exists()) {
    await current.create(recursive: true);
  }

  var processedFiles = 0;
  await for (final entity in legacy.list(followLinks: false)) {
    if (entity is! File || !_isPrunableCoverFile(entity.path)) {
      continue;
    }
    processedFiles += 1;
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
  }

  try {
    final leftover = await legacy.list(followLinks: false).isEmpty;
    if (leftover) {
      await legacy.delete();
    }
  } catch (_) {}
  return CoverCacheMigration(
    currentDir: currentPath,
    legacyDir: legacyPath,
    processedFiles: processedFiles,
  );
}

String? relocatedCoverArtPath(
  String? path, {
  required String fromDir,
  required String toDir,
}) {
  if (path == null || path.isEmpty) {
    return path;
  }
  final normalized = normalizedAbsolutePath(path);
  final from = normalizedAbsolutePath(fromDir);
  if (normalized != from && !p.isWithin(from, normalized)) {
    return path;
  }
  final relative = normalized == from ? '' : p.relative(normalized, from: from);
  return p.normalize(p.join(normalizedAbsolutePath(toDir), relative));
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

  final referenced = referencedPaths.map(normalizedAbsolutePath).toSet();
  var deleted = 0;
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File || !_isPrunableCoverFile(entity.path)) {
      continue;
    }
    final path = normalizedAbsolutePath(entity.path);
    if (referenced.contains(path)) {
      continue;
    }
    await entity.delete();
    deleted++;
  }
  return deleted;
}

String normalizedAbsolutePath(String path) {
  return p.normalize(File(path).absolute.path);
}

bool _isPrunableCoverFile(String path) {
  return switch (p.extension(path).toLowerCase()) {
    '.jpg' || '.jpeg' || '.png' => true,
    _ => false,
  };
}
