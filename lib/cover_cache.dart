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
