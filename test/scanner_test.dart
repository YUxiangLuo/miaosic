import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/library_controller.dart';
import 'package:miaosic/library_database.dart';
import 'package:miaosic/library_types.dart';
import 'package:miaosic/models.dart';
import 'package:miaosic/music_scanner.dart';
import 'package:miaosic/playlist_cover_indexer.dart';
import 'package:miaosic/rust_music_scanner.dart';

void main() {
  test(
    'rejects an incompatible Rust library before resolving scan functions',
    () async {
      final dir = await Directory.systemTemp.createTemp('miaosic_abi_test_');
      addTearDown(() => dir.delete(recursive: true));
      final source = File('${dir.path}/wrong_abi.c');
      await source.writeAsString(
        'unsigned int miaosic_abi_version(void) { return 999; }',
      );
      final libraryPath = '${dir.path}/wrong_abi.so';
      final build = await Process.run('clang', [
        '-shared',
        '-fPIC',
        source.path,
        '-o',
        libraryPath,
      ]);
      expect(build.exitCode, 0, reason: '${build.stderr}');
      expect(
        () => RustMusicScanner.open(libraryPath),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('ABI 999 does not match'),
          ),
        ),
      );
    },
  );

  for (final mode in ['incremental', 'full', 'direct']) {
    test(
      '$mode scan preserves library and favorites on unreadable subtree',
      () async {
        _requireRustScanner();
        final dir = await Directory.systemTemp.createTemp(
          'miaosic_scan_access_',
        );
        await _writeFixture(dir);
        final restricted = Directory(
          '${dir.path}/Artist - Album (2020)/Disc 1',
        );
        final scanner = _scannerFor(dir);
        final initial = await scanner.scan(dir.path);
        final favorite = initial.tracks.firstWhere(
          (track) => track.title == 'Opening',
        );
        final database = await LibraryDatabase.openAtPath(
          '${dir.path}/library.db',
        );
        await database.saveMusicRoot(dir.path);
        await database.replaceLibrary(initial);
        await database.setTrackFavorite(favorite.path, true);
        final controller = LibraryController(
          scanner: scanner,
          openDatabase: () async => database,
          coverIndexer: _NoopTrackCoverIndexer(),
          migrateCoverCache: (_) async {},
        );
        try {
          await controller.open();
          await _chmod(restricted.path, '000');
          await _rescan(controller, mode);
          expect(controller.rescanState.value.phase, RescanPhase.error);
          expect(controller.rescanState.value.error, contains(restricted.path));
          expect(controller.rescanState.value.diff, isNull);
          expect(
            await controller.applyPendingDiff(
              confirmLargeDeletion: (_) async => true,
            ),
            isNull,
          );
          expect(await database.loadTracks(), hasLength(initial.tracks.length));
          expect(
            await database.loadFavoriteTrackPaths(),
            contains(favorite.path),
          );

          await _chmod(restricted.path, '755');
          await _rescan(controller, mode);
          expect(
            controller.rescanState.value.phase,
            mode == 'direct' ? RescanPhase.done : RescanPhase.ready,
          );
          expect(controller.tracks, hasLength(initial.tracks.length));
          expect(
            await database.loadFavoriteTrackPaths(),
            contains(favorite.path),
          );
        } finally {
          await _chmod(restricted.path, '755');
          controller.dispose();
          await database.close();
          await dir.delete(recursive: true);
        }
      },
    );
  }

  test(
    'metadata read failure is reported and retry retains tagged metadata',
    () async {
      _requireRustScanner();
      final dir = await Directory.systemTemp.createTemp(
        'miaosic_metadata_access_',
      );
      final file = File('${dir.path}/fallback.flac');
      await _writeFlac(
        file,
        tags: const {'TITLE': 'Original title', 'ALBUM': 'Original album'},
      );
      final scanner = _scannerFor(dir);
      final initial = await scanner.scan(dir.path);
      final originalStat = await file.stat();
      try {
        await _chmod(file.path, '000');
        await expectLater(
          scanner.scan(dir.path),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains(file.path),
            ),
          ),
        );
        await _chmod(file.path, '600');
        final restoredStat = await file.stat();
        expect(restoredStat.size, originalStat.size);
        expect(restoredStat.modified, originalStat.modified);
        final retried = await scanner.scan(
          dir.path,
          previousTracks: initial.tracks,
        );
        expect(retried.tracks.single.title, 'Original title');
        expect(retried.tracks.single.album, 'Original album');
      } finally {
        await _chmod(file.path, '600');
        await dir.delete(recursive: true);
      }
    },
  );

  test('requires Rust scanner dynamic library', () async {
    final scanner = MusicScanner(rustScannerLoader: () => null);

    expect(
      scanner.scan('/tmp'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Rust scanner dynamic library is required'),
        ),
      ),
    );
  });

  test('honors cancel requested before scan starts', () async {
    final scanner = MusicScanner(rustScannerLoader: () => null);

    scanner.cancel();

    await expectLater(
      scanner.scan('/tmp'),
      throwsA(isA<ScanCancelledException>()),
    );
  });

  test('prepareForScan allows a new attempt after cancel', () async {
    final scanner = MusicScanner(rustScannerLoader: () => null);

    scanner.cancel();
    scanner.prepareForScan();

    await expectLater(
      scanner.scan('/tmp'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Rust scanner dynamic library is required'),
        ),
      ),
    );
  });

  test('Rust scanner scans generated FLAC fixture', () async {
    _requireRustScanner();

    final dir = await Directory.systemTemp.createTemp('miaosic_scan_fixture_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    await _writeFixture(dir);

    final result = await _scannerFor(dir).scan(dir.path);

    expect(result.engine, 'rust');
    _expectFixtureShape(result);
  });

  test('Rust scanner keeps root tracks in place', () async {
    _requireRustScanner();

    final dir = await Directory.systemTemp.createTemp(
      'miaosic_root_track_fixture_',
    );
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final looseTrack = File('${dir.path}/Loose.flac');
    await _writeFlac(
      looseTrack,
      tags: const {
        'TITLE': 'Loose',
        'ARTIST': 'Loose Artist',
        'ALBUM': 'Loose Album',
      },
    );

    final result = await _scannerFor(dir).scan(dir.path);

    expect(await looseTrack.exists(), isTrue);
    expect(
      result.tracks.singleWhere((track) => track.path == looseTrack.path).title,
      'Loose',
    );
    expect(result.folders.single.path, dir.path);
  });

  test('Rust scanner rejects root paths that cannot be opened', () async {
    _requireRustScanner();

    final dir = await Directory.systemTemp.createTemp(
      'miaosic_file_root_fixture_',
    );
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final fileRoot = File('${dir.path}/not_a_directory');
    await fileRoot.writeAsString('not a directory');

    expect(
      _scannerFor(dir).scan(fileRoot.path),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('music root cannot be opened'),
        ),
      ),
    );
  });

  test('incremental Rust scan reuses unchanged track metadata', () async {
    final rustScanner = _requireRustScanner();
    expect(rustScanner.abiVersion, RustMusicScanner.expectedAbiVersion);

    final dir = await Directory.systemTemp.createTemp(
      'miaosic_incremental_scan_fixture_',
    );
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    await _writeFixture(dir);

    final full = await _scannerFor(dir).scan(dir.path);
    final previousTracks = full.tracks
        .map((track) {
          if (track.title == 'Opening') {
            return _trackWithTitle(track, 'Cached Opening');
          }
          return track;
        })
        .toList(growable: false);

    final incremental = await _scannerFor(
      dir,
    ).scan(dir.path, previousTracks: previousTracks);

    expect(incremental.engine, 'rust');
    expect(
      incremental.tracks
          .firstWhere((track) => track.path.endsWith('Opening.flac'))
          .title,
      'Cached Opening',
    );
    _expectFixtureShape(incremental);
  });

  test('incremental Rust scan revalidates changed folder artwork', () async {
    final rustScanner = _requireRustScanner();
    expect(rustScanner.abiVersion, RustMusicScanner.expectedAbiVersion);

    final dir = await Directory.systemTemp.createTemp(
      'miaosic_incremental_cover_fixture_',
    );
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    await _writeFixture(dir);
    final cover = File('${dir.path}/Artist - Album (2020)/cover.jpg');
    await cover.writeAsBytes([0xff, 0xd8, 0xff, 0xd9]);

    final full = await _scannerFor(dir).scan(dir.path);
    final albumTrack = full.tracks.firstWhere(
      (track) => track.path.endsWith('Opening.flac'),
    );
    expect(albumTrack.coverArtPath, isNotNull);

    await cover.delete();
    final incremental = await _scannerFor(
      dir,
    ).scan(dir.path, previousTracks: full.tracks);

    expect(
      incremental.tracks
          .firstWhere((track) => track.path.endsWith('Opening.flac'))
          .coverArtPath,
      isNull,
    );
    expect(
      incremental.folders
          .firstWhere((folder) => folder.name == 'Artist - Album (2020)')
          .coverArtPath,
      isNull,
    );
  });
}

RustMusicScanner _requireRustScanner() {
  final scanner = RustMusicScanner.tryLoad();
  expect(
    scanner,
    isNotNull,
    reason:
        'Build the Rust scanner before running Flutter tests: '
        'cargo build --locked --manifest-path native/music_core/Cargo.toml',
  );
  return scanner!;
}

Future<void> _chmod(String path, String mode) async {
  final result = await Process.run('chmod', [mode, path]);
  expect(result.exitCode, 0, reason: result.stderr.toString());
}

Future<void> _rescan(LibraryController controller, String mode) async {
  if (mode == 'direct') {
    await controller.scanLibrary();
    return;
  }
  controller.startRescanDiff(full: mode == 'full');
  for (var attempt = 0; attempt < 1000; attempt++) {
    if (!controller.scanning && !controller.rescanState.value.phase.isBusy) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Scan did not finish: ${controller.rescanState.value.phase}');
}

class _NoopTrackCoverIndexer extends TrackCoverIndexer {
  @override
  Future<bool> indexTracks({
    required List<Track> tracks,
    required LibraryDatabase database,
    Map<String, String?>? knownCache,
    required bool Function() shouldPause,
    required TrackCoverCacheUpdated onCacheUpdated,
  }) async => false;
}

MusicScanner _scannerFor(Directory root) {
  return MusicScanner(
    cacheDirectoryProvider: () async {
      final covers = Directory('${root.path}/.covers');
      await covers.create(recursive: true);
      return covers.path;
    },
  );
}

Future<void> _writeFixture(Directory root) async {
  final albumFolder = Directory('${root.path}/Artist - Album (2020)');
  await _writeFlac(
    File('${albumFolder.path}/Disc 1/01. Opening.flac'),
    tags: const {
      'TITLE': 'Opening',
      'ARTIST': 'Artist',
      'ALBUM': 'Album',
      'ALBUMARTIST': 'Artist',
      'TRACKNUMBER': '1',
      'DISCNUMBER': '1',
      'DATE': '2020',
    },
  );
  await _writeFlac(
    File('${albumFolder.path}/Disc 2/02. Finale.flac'),
    tags: const {
      'TITLE': 'Finale',
      'ARTIST': 'Artist',
      'ALBUM': 'Album',
      'ALBUMARTIST': 'Artist',
      'TRACKNUMBER': '2',
      'DISCNUMBER': '2',
      'DATE': '2020',
    },
  );

  final playlistFolder = Directory('${root.path}/Road playlist');
  for (var i = 0; i < 12; i++) {
    await _writeFlac(
      File('${playlistFolder.path}/Track ${i + 1}.flac'),
      tags: {
        'TITLE': 'Playlist Track ${i + 1}',
        'ARTIST': 'Artist $i',
        'ALBUM': 'Source Album $i',
        'ALBUMARTIST': 'Artist $i',
        'DATE': '${2000 + i}',
      },
    );
  }
}

Future<void> _writeFlac(
  File file, {
  required Map<String, String> tags,
  int durationMs = 120000,
}) async {
  await file.parent.create(recursive: true);
  await file.writeAsBytes(_flacBytes(tags: tags, durationMs: durationMs));
}

List<int> _flacBytes({
  required Map<String, String> tags,
  required int durationMs,
}) {
  final bytes = BytesBuilder();
  bytes.add(ascii.encode('fLaC'));
  bytes.add(_metadataBlockHeader(type: 0, length: 34, isLast: false));
  bytes.add(_streamInfo(durationMs));

  final comments = _vorbisComments(tags);
  bytes.add(
    _metadataBlockHeader(type: 4, length: comments.length, isLast: true),
  );
  bytes.add(comments);
  return bytes.toBytes();
}

List<int> _metadataBlockHeader({
  required int type,
  required int length,
  required bool isLast,
}) {
  return [
    (isLast ? 0x80 : 0x00) | type,
    (length >> 16) & 0xff,
    (length >> 8) & 0xff,
    length & 0xff,
  ];
}

Uint8List _streamInfo(int durationMs) {
  final block = Uint8List(34);
  const sampleRate = 44100;
  final totalSamples = (sampleRate * durationMs / 1000).round();
  final packed = (sampleRate << 44) | totalSamples;
  for (var i = 0; i < 8; i++) {
    block[17 - i] = (packed >> (i * 8)) & 0xff;
  }
  return block;
}

Uint8List _vorbisComments(Map<String, String> tags) {
  final bytes = BytesBuilder();
  _addUint32Le(bytes, 7);
  bytes.add(utf8.encode('miaosic'));
  _addUint32Le(bytes, tags.length);
  for (final entry in tags.entries) {
    final raw = utf8.encode('${entry.key}=${entry.value}');
    _addUint32Le(bytes, raw.length);
    bytes.add(raw);
  }
  return bytes.toBytes();
}

void _addUint32Le(BytesBuilder bytes, int value) {
  bytes.add([
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ]);
}

void _expectFixtureShape(ScanResult result) {
  expect(result.tracks.length, 14);
  final albumFolders = result.folders
      .where((folder) => folder.kind == FolderKind.album)
      .toList();
  final playlistFolders = result.folders
      .where((folder) => folder.kind == FolderKind.playlist)
      .toList();

  expect(albumFolders, hasLength(1));
  expect(playlistFolders, hasLength(1));
  expect(albumFolders.single.trackCount, 2);
  expect(playlistFolders.single.trackCount, 12);
  expect(result.albums, hasLength(1));
  expect(result.albums.single.title, 'Album');
  expect(result.tracks.every((track) => track.coverArtPath == null), true);
}

Track _trackWithTitle(Track track, String title) {
  return Track(
    id: track.id,
    path: track.path,
    folderPath: track.folderPath,
    title: title,
    artist: track.artist,
    album: track.album,
    albumArtist: track.albumArtist,
    trackNumber: track.trackNumber,
    discNumber: track.discNumber,
    year: track.year,
    durationMs: track.durationMs,
    sizeBytes: track.sizeBytes,
    modifiedMs: track.modifiedMs,
    coverArtPath: track.coverArtPath,
  );
}
