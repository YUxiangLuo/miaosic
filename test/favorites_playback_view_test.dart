import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/favorites_playback_view.dart';
import 'package:miaosic/models.dart';

void main() {
  testWidgets('favorites overlay shows now playing stage and track table', (
    tester,
  ) async {
    final tracks = [_track(1), _track(2), _track(3)];
    Track? playedTrack;

    await _pumpFavoritesOverlay(
      tester,
      child: FavoritesPlaybackView(
        tracks: tracks,
        trackCoverCache: const {},
        currentTrack: tracks[1],
        playbackActive: true,
        playing: true,
        onClose: () {},
        onPlayAll: () {},
        onShuffleAll: () {},
        onPrevious: () {},
        onTogglePlayback: () {},
        onNext: () {},
        onPlayTrack: (track) => playedTrack = track,
        onToggleFavorite: (_) {},
      ),
    );

    expect(find.text('Favorites'), findsWidgets);
    expect(find.text('3 favorite tracks'), findsWidgets);
    expect(find.text('TITLE'), findsOneWidget);
    expect(find.text('ARTIST'), findsOneWidget);
    expect(find.text('ALBUM'), findsOneWidget);
    expect(find.text('NOW PLAYING'), findsOneWidget);
    expect(find.text('Track 1'), findsOneWidget);
    expect(find.text('Track 2'), findsWidgets);
    expect(find.byTooltip('Shuffle favorites'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);

    await tester.tap(find.text('Track 3'));
    await tester.pump();

    expect(playedTrack?.path, tracks[2].path);
  });

  testWidgets('favorites overlay closes with escape', (tester) async {
    var closed = 0;
    await _pumpFavoritesOverlay(
      tester,
      child: FavoritesPlaybackView(
        tracks: [_track(1)],
        trackCoverCache: const {},
        currentTrack: null,
        playbackActive: false,
        playing: false,
        onClose: () => closed += 1,
        onPlayAll: () {},
        onShuffleAll: () {},
        onPrevious: null,
        onTogglePlayback: null,
        onNext: null,
        onPlayTrack: (_) {},
        onToggleFavorite: (_) {},
      ),
    );

    expect(find.text('Favorites'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(closed, 1);
  });

  testWidgets('favorites overlay can jump back to now playing', (tester) async {
    var nowPlayingCount = 0;
    await _pumpFavoritesOverlay(
      tester,
      child: FavoritesPlaybackView(
        tracks: [_track(1)],
        trackCoverCache: const {},
        currentTrack: null,
        playbackActive: false,
        playing: false,
        onClose: () {},
        onOpenNowPlaying: () => nowPlayingCount += 1,
        onPlayAll: () {},
        onShuffleAll: () {},
        onPrevious: null,
        onTogglePlayback: null,
        onNext: null,
        onPlayTrack: (_) {},
        onToggleFavorite: (_) {},
      ),
    );

    await tester.tap(find.byTooltip('Back to now playing'));
    await tester.pump();
    expect(nowPlayingCount, 1);
  });

  testWidgets('favorites overlay controls and shortcuts route actions', (
    tester,
  ) async {
    var playCount = 0;
    var toggleCount = 0;
    var nextCount = 0;
    var shuffleCount = 0;
    Track? removedTrack;

    await _pumpFavoritesOverlay(
      tester,
      child: FavoritesPlaybackView(
        tracks: [_track(1), _track(2)],
        trackCoverCache: const {},
        currentTrack: _track(1),
        playbackActive: true,
        playing: true,
        onClose: () {},
        onPlayAll: () => playCount += 1,
        onShuffleAll: () => shuffleCount += 1,
        onPrevious: () {},
        onTogglePlayback: () => toggleCount += 1,
        onNext: () => nextCount += 1,
        onPlayTrack: (_) {},
        onToggleFavorite: (track) => removedTrack = track,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(toggleCount, 1);
    expect(playCount, 0);

    await tester.tap(find.byTooltip('Next'));
    await tester.tap(find.byTooltip('Shuffle favorites'));
    await tester.tap(find.byTooltip('Remove from favorites').first);
    await tester.pump();

    expect(nextCount, 1);
    expect(shuffleCount, 1);
    expect(removedTrack?.path, _track(1).path);
  });

  testWidgets('empty favorites overlay disables playback commands', (
    tester,
  ) async {
    await _pumpFavoritesOverlay(
      tester,
      child: FavoritesPlaybackView(
        tracks: const [],
        trackCoverCache: const {},
        currentTrack: null,
        playbackActive: false,
        playing: false,
        onClose: () {},
        onPlayAll: null,
        onShuffleAll: null,
        onPrevious: null,
        onTogglePlayback: null,
        onNext: null,
        onPlayTrack: (_) {},
        onToggleFavorite: (_) {},
      ),
    );

    expect(find.text('No favorite tracks yet'), findsOneWidget);
    final playButton = tester.widget<IconButton>(
      _iconButtonFor(Icons.play_arrow_rounded),
    );
    final shuffleButton = tester.widget<IconButton>(
      _iconButtonFor(Icons.shuffle_rounded),
    );
    expect(playButton.onPressed, isNull);
    expect(shuffleButton.onPressed, isNull);
  });

  testWidgets('active favorites overlay fits a short wide window', (
    tester,
  ) async {
    await _pumpFavoritesOverlay(
      tester,
      size: const Size(1100, 560),
      child: FavoritesPlaybackView(
        tracks: [_track(1)],
        trackCoverCache: const {},
        currentTrack: _track(1),
        playbackActive: true,
        playing: true,
        onClose: () {},
        onPlayAll: () {},
        onShuffleAll: () {},
        onPrevious: () {},
        onTogglePlayback: () {},
        onNext: () {},
        onPlayTrack: (_) {},
        onToggleFavorite: (_) {},
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('NOW PLAYING'), findsOneWidget);
    expect(find.text('1 favorite track'), findsWidgets);
  });

  testWidgets('active favorites overlay fits a short narrow window', (
    tester,
  ) async {
    await _pumpFavoritesOverlay(
      tester,
      size: const Size(360, 400),
      child: FavoritesPlaybackView(
        tracks: [_track(1)],
        trackCoverCache: const {},
        currentTrack: _track(1),
        playbackActive: true,
        playing: true,
        onClose: () {},
        onPlayAll: () {},
        onShuffleAll: () {},
        onPrevious: () {},
        onTogglePlayback: () {},
        onNext: () {},
        onPlayTrack: (_) {},
        onToggleFavorite: (_) {},
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

Finder _iconButtonFor(IconData icon) {
  return find.ancestor(
    of: find.byIcon(icon),
    matching: find.byType(IconButton),
  );
}

Future<void> _pumpFavoritesOverlay(
  WidgetTester tester, {
  required Widget child,
  Size size = const Size(1100, 720),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(width: size.width, height: size.height, child: child),
    ),
  );
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
    durationMs: 120000 + index * 1000,
    sizeBytes: 42,
    modifiedMs: 99,
    coverArtPath: null,
  );
}
