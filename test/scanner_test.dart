import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/models.dart';
import 'package:miaosic/music_scanner.dart';
import 'package:miaosic/rust_music_scanner.dart';

void main() {
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

  test('Rust scanner scans generated FLAC fixture', () async {
    if (RustMusicScanner.tryLoad() == null) {
      markTestSkipped('Rust dynamic library is not available');
      return;
    }

    final dir = await Directory.systemTemp.createTemp('miaosic_scan_fixture_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    await _writeFixture(dir);

    final result = await MusicScanner().scan(dir.path);

    expect(result.engine, 'rust');
    _expectFixtureShape(result);
  });
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
