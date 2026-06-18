import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/favorite_views.dart';
import 'package:miaosic/models.dart';

void main() {
  testWidgets('favorites page plays and removes tracks', (tester) async {
    final tracks = [_track(1), _track(2)];
    Track? playedTrack;
    Track? removedTrack;
    var toggleCount = 0;
    var nextCount = 0;
    var shuffleCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1000,
          height: 640,
          child: FavoriteTrackList(
            tracks: tracks,
            trackCoverCache: const {},
            currentTrack: tracks[0],
            playbackActive: true,
            playing: true,
            onPlayAll: () {},
            onShuffleAll: () => shuffleCount += 1,
            onPrevious: () {},
            onTogglePlayback: () => toggleCount += 1,
            onNext: () => nextCount += 1,
            onPlayTrack: (track) => playedTrack = track,
            onToggleFavorite: (track) => removedTrack = track,
          ),
        ),
      ),
    );

    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('2 favorite tracks'), findsOneWidget);
    expect(find.text('Track 1'), findsOneWidget);
    expect(find.text('Track 2'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byTooltip('Next'), findsOneWidget);
    expect(find.byTooltip('Shuffle favorites'), findsOneWidget);
    expect(find.byTooltip('Remove from favorites'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Pause'));
    await tester.tap(find.byTooltip('Next'));
    await tester.tap(find.byTooltip('Shuffle favorites'));
    await tester.pump();
    expect(toggleCount, 1);
    expect(nextCount, 1);
    expect(shuffleCount, 1);

    await tester.tap(find.text('Track 2'));
    await tester.pump();
    expect(playedTrack?.path, tracks[1].path);

    await tester.tap(find.byTooltip('Remove from favorites').first);
    await tester.pump();
    expect(removedTrack?.path, tracks[0].path);
  });

  testWidgets('empty favorites page shows an empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FavoriteTrackList(
          tracks: const [],
          trackCoverCache: const {},
          currentTrack: null,
          playbackActive: false,
          playing: false,
          onPlayAll: null,
          onShuffleAll: null,
          onPrevious: null,
          onTogglePlayback: null,
          onNext: null,
          onPlayTrack: (_) {},
          onToggleFavorite: (_) {},
        ),
      ),
    );

    expect(find.text('No favorite tracks yet'), findsOneWidget);
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
