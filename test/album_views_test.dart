import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/album_views.dart';
import 'package:miaosic/models.dart';

void main() {
  testWidgets('single tap opens album without playing it', (tester) async {
    final album = _album();
    final tracks = [_track()];
    var openCount = 0;
    var playCount = 0;

    await tester.pumpWidget(
      _albumGrid(
        album: album,
        tracks: tracks,
        onOpen: (_, _) => openCount += 1,
        onPlay: (_, _) => playCount += 1,
      ),
    );

    await tester.tap(find.text(album.title));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));

    expect(openCount, 1);
    expect(playCount, 0);
  });

  testWidgets('double tap plays album without also opening it as a tap', (
    tester,
  ) async {
    final album = _album();
    final tracks = [_track()];
    var openCount = 0;
    var playCount = 0;

    await tester.pumpWidget(
      _albumGrid(
        album: album,
        tracks: tracks,
        onOpen: (_, _) => openCount += 1,
        onPlay: (_, _) => playCount += 1,
      ),
    );

    await _doubleTap(tester, find.text(album.title));

    expect(openCount, 0);
    expect(playCount, 1);
  });

  testWidgets('double tap opens current album without restarting playback', (
    tester,
  ) async {
    final album = _album();
    final tracks = [_track()];
    var openCount = 0;
    var playCount = 0;

    await tester.pumpWidget(
      _albumGrid(
        album: album,
        tracks: tracks,
        isPlayingAlbum: true,
        onOpen: (_, _) => openCount += 1,
        onPlay: (_, _) => playCount += 1,
      ),
    );

    await _doubleTap(tester, find.text(album.title));

    expect(openCount, 1);
    expect(playCount, 0);
  });

  testWidgets('empty album does not open or play', (tester) async {
    final album = _album(trackCount: 0);
    var openCount = 0;
    var playCount = 0;

    await tester.pumpWidget(
      _albumGrid(
        album: album,
        tracks: const [],
        onOpen: (_, _) => openCount += 1,
        onPlay: (_, _) => playCount += 1,
      ),
    );

    await tester.tap(find.text(album.title));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
    await _doubleTap(tester, find.text(album.title));

    expect(openCount, 0);
    expect(playCount, 0);
  });
}

Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(kDoubleTapMinTime);
  await tester.tap(finder);
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
}

Widget _albumGrid({
  required AlbumSummary album,
  required List<Track> tracks,
  required void Function(AlbumSummary album, List<Track> tracks) onOpen,
  required void Function(AlbumSummary album, List<Track> tracks) onPlay,
  bool isPlayingAlbum = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 900,
        height: 700,
        child: AlbumGrid(
          albums: [album],
          tracksByFolder: {album.folderPath: tracks},
          isPlayingAlbum: (_, _) => isPlayingAlbum,
          onOpen: onOpen,
          onPlay: onPlay,
        ),
      ),
    ),
  );
}

AlbumSummary _album({int trackCount = 1}) {
  return AlbumSummary(
    folderPath: '/music/artist/album',
    title: 'Album One',
    albumArtist: 'Artist',
    year: 2026,
    trackCount: trackCount,
    coverArtPath: null,
  );
}

Track _track() {
  return const Track(
    path: '/music/artist/album/01.flac',
    folderPath: '/music/artist/album',
    title: 'Track One',
    artist: 'Artist',
    album: 'Album One',
    albumArtist: 'Artist',
    trackNumber: 1,
    discNumber: 1,
    year: 2026,
    durationMs: 120000,
    sizeBytes: 42,
    modifiedMs: 99,
    coverArtPath: null,
  );
}
