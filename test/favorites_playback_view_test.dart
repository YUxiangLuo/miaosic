import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/favorites_playback_view.dart';
import 'package:miaosic/models.dart';

void main() {
  testWidgets('favorites overlay closes with escape', (tester) async {
    var closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FavoritesPlaybackView(
          tracks: [
            Track(
              path: '/music/a.flac',
              folderPath: '/music',
              title: 'A',
              artist: 'Artist',
              album: 'Album',
              albumArtist: 'Artist',
              trackNumber: 1,
              discNumber: 1,
              year: 2026,
              durationMs: 1000,
              sizeBytes: 1,
              modifiedMs: 1,
              coverArtPath: null,
            ),
          ],
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
      ),
    );

    expect(find.text('Favorites'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(closed, 1);
  });

  testWidgets('favorites overlay can jump back to now playing', (tester) async {
    var nowPlayingCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FavoritesPlaybackView(
          tracks: [
            Track(
              path: '/music/a.flac',
              folderPath: '/music',
              title: 'A',
              artist: 'Artist',
              album: 'Album',
              albumArtist: 'Artist',
              trackNumber: 1,
              discNumber: 1,
              year: 2026,
              durationMs: 1000,
              sizeBytes: 1,
              modifiedMs: 1,
              coverArtPath: null,
            ),
          ],
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
      ),
    );

    await tester.tap(find.byTooltip('Back to now playing'));
    await tester.pump();
    expect(nowPlayingCount, 1);
  });
}
