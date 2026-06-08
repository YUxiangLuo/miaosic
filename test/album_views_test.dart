import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/album_views.dart';
import 'package:miaosic/models.dart';

void main() {
  testWidgets('single tap opens album without playing it', (tester) async {
    final album = _album();
    final tracks = [_track()];
    var openCount = 0;

    await tester.pumpWidget(
      _albumGrid(
        album: album,
        tracks: tracks,
        onOpen: (_, _) => openCount += 1,
      ),
    );

    expect(find.text(album.title), findsNothing);

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(openCount, 1);
  });

  testWidgets('empty album does not open', (tester) async {
    final album = _album(trackCount: 0);
    var openCount = 0;

    await tester.pumpWidget(
      _albumGrid(
        album: album,
        tracks: const [],
        onOpen: (_, _) => openCount += 1,
      ),
    );

    expect(find.text(album.title), findsNothing);

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(openCount, 0);
  });
}

Widget _albumGrid({
  required AlbumSummary album,
  required List<Track> tracks,
  required void Function(AlbumSummary album, List<Track> tracks) onOpen,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 900,
        height: 700,
        child: AlbumGrid(
          albums: [album],
          tracksByFolder: {album.folderPath: tracks},
          onOpen: onOpen,
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
