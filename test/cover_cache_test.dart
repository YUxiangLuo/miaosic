import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/cover_cache.dart';

void main() {
  test('prunes only unreferenced generated cover image files', () async {
    final dir = await Directory.systemTemp.createTemp('miaosic_cover_prune_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final kept = File('${dir.path}/keep.jpg');
    final removed = File('${dir.path}/remove.png');
    final ignored = File('${dir.path}/notes.txt');
    await kept.writeAsBytes([1]);
    await removed.writeAsBytes([2]);
    await ignored.writeAsString('not a cover');

    final deleted = await pruneCoverCacheFiles({
      kept.path,
    }, cacheDirPath: dir.path);

    expect(deleted, 1);
    expect(await kept.exists(), isTrue);
    expect(await removed.exists(), isFalse);
    expect(await ignored.exists(), isTrue);
  });
}
