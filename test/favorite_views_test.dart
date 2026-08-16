import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/favorite_views.dart';
import 'package:miaosic/models.dart';

void main() {
  testWidgets('empty browse list shows an empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FavoriteBrowseList(
          tracks: const [],
          trackCoverCache: const {},
          currentTrack: null,
          playing: false,
          onPlayTrack: (_) {},
          onToggleFavorite: (_) {},
        ),
      ),
    );

    expect(find.text('No favorite tracks yet'), findsOneWidget);
  });

  testWidgets('browse list plays from the row control, not a single tap', (
    tester,
  ) async {
    final tracks = [_track(1), _track(2)];
    Track? playedTrack;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1000,
          height: 640,
          child: FavoriteBrowseList(
            tracks: tracks,
            trackCoverCache: const {},
            currentTrack: null,
            playing: false,
            onPlayTrack: (track) => playedTrack = track,
            onToggleFavorite: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('#'), findsNothing);
    expect(find.byTooltip('Play favorites'), findsNothing);
    expect(find.byTooltip('Shuffle favorites'), findsNothing);
    expect(find.byTooltip('Play favorite'), findsNWidgets(2));

    await tester.tap(find.text('Track 2'));
    await tester.pump(kDoubleTapTimeout);
    expect(playedTrack, isNull);

    await tester.tap(find.byKey(Key('favorite-play-${tracks[1].path}')));
    await tester.pump();
    expect(playedTrack?.path, tracks[1].path);

    playedTrack = null;
    await tester.tap(find.text('Track 1'));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(find.text('Track 1'));
    await tester.pump(kDoubleTapTimeout);
    expect(playedTrack?.path, tracks[0].path);
  });
}

Track _track(int index) {
  return Track(
    path: '/music/favorites/$index.flac',
    folderPath: '/music/favorites',
    title: 'Track $index',
    artist: 'Artist $index',
    album: 'Album $index',
    albumArtist: 'Artist $index',
    trackNumber: index,
    discNumber: 1,
    year: 2026,
    durationMs: 120000,
    sizeBytes: 42,
    modifiedMs: 99,
    coverArtPath: null,
  );
}
