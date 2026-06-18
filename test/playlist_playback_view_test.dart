import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/models.dart';
import 'package:miaosic/playlist_playback_view.dart';

void main() {
  testWidgets('playlist playback overlay shows dense track table', (
    tester,
  ) async {
    final folder = _folder(trackCount: 3);
    final tracks = [_track(1), _track(2), _track(3)];
    Track? playedTrack;

    await tester.pumpWidget(
      _Host(
        child: PlaylistPlaybackView(
          folder: folder,
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
        ),
      ),
    );

    expect(find.text('Road Set'), findsOneWidget);
    expect(find.text('3 tracks'), findsOneWidget);
    expect(find.text('TITLE'), findsOneWidget);
    expect(find.text('ARTIST'), findsOneWidget);
    expect(find.text('ALBUM'), findsOneWidget);
    expect(find.text('Track 1'), findsOneWidget);
    expect(find.text('Track 2'), findsOneWidget);
    expect(find.text('Album 2'), findsOneWidget);

    await tester.tap(find.text('Track 3'));
    await tester.pump();

    expect(playedTrack?.path, tracks[2].path);
  });

  testWidgets('playlist playback controls and shortcuts route actions', (
    tester,
  ) async {
    final folder = _folder(trackCount: 1);
    final tracks = [_track(1)];
    var closeCount = 0;
    var playCount = 0;
    var toggleCount = 0;

    await tester.pumpWidget(
      _Host(
        child: PlaylistPlaybackView(
          folder: folder,
          tracks: tracks,
          trackCoverCache: const {},
          currentTrack: null,
          playbackActive: false,
          playing: false,
          onClose: () => closeCount += 1,
          onPlayAll: () => playCount += 1,
          onShuffleAll: () {},
          onPrevious: null,
          onTogglePlayback: () => toggleCount += 1,
          onNext: null,
          onPlayTrack: (_) {},
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(playCount, 1);
    expect(toggleCount, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(closeCount, 1);
  });

  testWidgets('playlist rows toggle favorite state', (tester) async {
    final folder = _folder(trackCount: 2);
    final tracks = [_track(1), _track(2)];
    Track? toggledTrack;

    await tester.pumpWidget(
      _Host(
        child: PlaylistPlaybackView(
          folder: folder,
          tracks: tracks,
          trackCoverCache: const {},
          currentTrack: tracks[0],
          playbackActive: true,
          playing: true,
          onClose: () {},
          onPlayAll: () {},
          onShuffleAll: () {},
          onPrevious: () {},
          onTogglePlayback: () {},
          onNext: () {},
          favoriteTrackPaths: {tracks[0].path},
          onPlayTrack: (_) {},
          onToggleFavoriteTrack: (track) => toggledTrack = track,
        ),
      ),
    );

    expect(find.byTooltip('Remove from favorites'), findsOneWidget);
    expect(find.byTooltip('Add to favorites'), findsOneWidget);

    await tester.tap(find.byTooltip('Add to favorites'));
    await tester.pump();

    expect(toggledTrack?.path, tracks[1].path);
  });

  testWidgets('empty playlist disables playback commands', (tester) async {
    final folder = _folder(trackCount: 0);

    await tester.pumpWidget(
      _Host(
        child: PlaylistPlaybackView(
          folder: folder,
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
        ),
      ),
    );

    expect(find.text('No tracks found'), findsOneWidget);
    final playButton = tester.widget<IconButton>(
      _iconButtonFor(Icons.play_arrow_rounded),
    );
    final shuffleButton = tester.widget<IconButton>(
      _iconButtonFor(Icons.shuffle_rounded),
    );
    expect(playButton.onPressed, isNull);
    expect(shuffleButton.onPressed, isNull);
  });

  testWidgets('active playlist playback fits in a narrow layout', (
    tester,
  ) async {
    final folder = _folder(trackCount: 1);
    final tracks = [_track(1)];

    await tester.pumpWidget(
      _Host(
        width: 360,
        height: 640,
        child: PlaylistPlaybackView(
          folder: folder,
          tracks: tracks,
          trackCoverCache: const {},
          currentTrack: tracks.single,
          playbackActive: true,
          playing: true,
          onClose: () {},
          onPlayAll: () {},
          onShuffleAll: () {},
          onPrevious: () {},
          onTogglePlayback: () {},
          onNext: () {},
          onPlayTrack: (_) {},
        ),
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

class _Host extends StatelessWidget {
  const _Host({this.width = 1100, this.height = 720, required this.child});

  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SizedBox(width: width, height: height, child: child),
    );
  }
}

FolderSummary _folder({required int trackCount}) {
  return FolderSummary(
    path: '/music/playlists/road',
    name: 'Road Set',
    kind: FolderKind.playlist,
    confidence: 0.9,
    trackCount: trackCount,
    albumCount: 2,
    albumArtistCount: 2,
    artistCount: 3,
    yearCount: 2,
    coverArtPath: null,
  );
}

Track _track(int index) {
  return Track(
    path: '/music/playlists/road/$index.flac',
    folderPath: '/music/playlists/road',
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
