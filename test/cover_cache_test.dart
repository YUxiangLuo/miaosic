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

  test('migrates leftover covers from the legacy XDG directory', () async {
    final root = await Directory.systemTemp.createTemp(
      'miaosic_cover_migrate_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final legacy = Directory('${root.path}/legacy');
    final current = Directory('${root.path}/current');
    await legacy.create();
    await File('${legacy.path}/art.jpg').writeAsBytes([1]);
    await File('${legacy.path}/notes.txt').writeAsString('keep');

    final moved = await migrateLegacyCoverCache(
      currentDirPath: current.path,
      legacyDirPath: legacy.path,
    );

    expect(moved.processedFiles, 1);
    expect(moved.shouldRewritePaths, isTrue);
    expect(await File('${current.path}/art.jpg').exists(), isTrue);
    expect(await File('${legacy.path}/art.jpg').exists(), isFalse);
    expect(await File('${legacy.path}/notes.txt').exists(), isTrue);
  });

  test('does not overwrite an existing cover during migration', () async {
    final root = await Directory.systemTemp.createTemp(
      'miaosic_cover_migrate_skip_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final legacy = Directory('${root.path}/legacy');
    final current = Directory('${root.path}/current');
    await legacy.create(recursive: true);
    await current.create(recursive: true);
    await File('${legacy.path}/art.jpg').writeAsBytes([1]);
    await File('${current.path}/art.jpg').writeAsBytes([9]);

    final moved = await migrateLegacyCoverCache(
      currentDirPath: current.path,
      legacyDirPath: legacy.path,
    );

    expect(moved.processedFiles, 1);
    expect(moved.shouldRewritePaths, isTrue);
    expect(await File('${current.path}/art.jpg').readAsBytes(), [9]);
    expect(await File('${legacy.path}/art.jpg').exists(), isFalse);
  });

  test('rewrites cover paths from the legacy directory', () {
    expect(
      relocatedCoverArtPath(
        '/old/covers/art.jpg',
        fromDir: '/old/covers',
        toDir: '/new/covers',
      ),
      '/new/covers/art.jpg',
    );
    expect(
      relocatedCoverArtPath(
        '/other/art.jpg',
        fromDir: '/old/covers',
        toDir: '/new/covers',
      ),
      '/other/art.jpg',
    );
  });

  test('falls back to an XDG cover directory without path_provider', () {
    final path = fallbackCoverCacheDir();
    expect(path, contains('dev.vesein.miaosic'));
    expect(path.endsWith('covers'), isTrue);
    expect(Directory(path).existsSync(), isTrue);
  });
}
