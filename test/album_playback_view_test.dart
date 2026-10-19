import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/album_playback_view.dart';
import 'package:miaosic/models.dart';

void main() {
  testWidgets('space toggles playback after arrow key focus movement', (
    tester,
  ) async {
    final album = _album();
    final tracks = [_track(1), _track(2), _track(3)];
    var closeCount = 0;
    var previousCount = 0;
    var toggleCount = 0;
    var nextCount = 0;
    var leakedKeyCount = 0;
    Track? playedTrack;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1280,
          height: 720,
          child: Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.arrowRight ||
                      event.logicalKey == LogicalKeyboardKey.arrowDown ||
                      event.logicalKey == LogicalKeyboardKey.space)) {
                leakedKeyCount += 1;
              }
              return KeyEventResult.ignored;
            },
            child: AlbumPlaybackView(
              album: album,
              tracks: tracks,
              currentTrack: tracks[1],
              playing: false,
              onClose: () => closeCount += 1,
              onPrevious: () => previousCount += 1,
              onToggle: () => toggleCount += 1,
              onNext: () => nextCount += 1,
              canSwitchPreviousAlbum: false,
              canSwitchNextAlbum: false,
              onSwitchPreviousAlbum: null,
              onSwitchNextAlbum: null,
              onPlayTrack: (track) => playedTrack = track,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(toggleCount, 1);
    expect(leakedKeyCount, 0);
    expect(closeCount, 0);
    expect(previousCount, 0);
    expect(nextCount, 0);
    expect(playedTrack, isNull);
  });

  testWidgets('left and right arrows switch albums instead of tracks', (
    tester,
  ) async {
    final album = _album();
    final tracks = [_track(1), _track(2), _track(3)];
    var previousTrackCount = 0;
    var nextTrackCount = 0;
    var previousAlbumCount = 0;
    var nextAlbumCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1280,
          height: 720,
          child: AlbumPlaybackView(
            album: album,
            tracks: tracks,
            currentTrack: tracks[1],
            playing: false,
            onClose: () {},
            onPrevious: () => previousTrackCount += 1,
            onToggle: () {},
            onNext: () => nextTrackCount += 1,
            canSwitchPreviousAlbum: true,
            canSwitchNextAlbum: true,
            onSwitchPreviousAlbum: () => previousAlbumCount += 1,
            onSwitchNextAlbum: () => nextAlbumCount += 1,
            onPlayTrack: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(previousAlbumCount, 1);
    expect(nextAlbumCount, 1);
    expect(previousTrackCount, 0);
    expect(nextTrackCount, 0);
  });

  testWidgets('escape closes album playback without leaking to parent focus', (
    tester,
  ) async {
    final album = _album();
    final tracks = [_track(1), _track(2), _track(3)];
    var closeCount = 0;
    var leakedEscapeCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1280,
          height: 720,
          child: Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                leakedEscapeCount += 1;
              }
              return KeyEventResult.ignored;
            },
            child: AlbumPlaybackView(
              album: album,
              tracks: tracks,
              currentTrack: tracks[1],
              playing: false,
              onClose: () => closeCount += 1,
              onPrevious: () {},
              onToggle: () {},
              onNext: () {},
              canSwitchPreviousAlbum: false,
              canSwitchNextAlbum: false,
              onSwitchPreviousAlbum: null,
              onSwitchNextAlbum: null,
              onPlayTrack: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(closeCount, 1);
    expect(leakedEscapeCount, 0);
  });

  testWidgets('currently playing track has no selected row background', (
    tester,
  ) async {
    final album = _album();
    final tracks = [_track(1), _track(2), _track(3)];

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1280,
          height: 720,
          child: AlbumPlaybackView(
            album: album,
            tracks: tracks,
            currentTrack: tracks[1],
            playing: true,
            onClose: () {},
            onPrevious: () {},
            onToggle: () {},
            onNext: () {},
            canSwitchPreviousAlbum: false,
            canSwitchNextAlbum: false,
            onSwitchPreviousAlbum: null,
            onSwitchNextAlbum: null,
            onPlayTrack: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final row = tester.widget<AnimatedContainer>(
      find.ancestor(
        of: find.text('Track 2'),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final decoration = row.decoration as BoxDecoration;

    expect(decoration.color, Colors.white.withValues(alpha: 0));
    expect(find.byKey(const ValueKey('playing')), findsOneWidget);
  });

  testWidgets('album track rows toggle favorite state', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final album = _album();
    final tracks = [_track(1), _track(2), _track(3)];
    Track? toggledTrack;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1280,
          height: 720,
          child: AlbumPlaybackView(
            album: album,
            tracks: tracks,
            currentTrack: tracks[1],
            playing: true,
            favoriteTrackPaths: {tracks[1].path},
            onClose: () {},
            onPrevious: () {},
            onToggle: () {},
            onNext: () {},
            canSwitchPreviousAlbum: false,
            canSwitchNextAlbum: false,
            onSwitchPreviousAlbum: null,
            onSwitchNextAlbum: null,
            onPlayTrack: (_) {},
            onToggleFavoriteTrack: (track) => toggledTrack = track,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Remove from favorites'), findsOneWidget);
    expect(find.byTooltip('Add to favorites'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Remove from favorites'));
    await tester.pump();

    expect(toggledTrack?.path, tracks[1].path);
  });

  testWidgets('bottom dock centers enlarged controls without metadata', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final album = _album();
    final tracks = [_track(1), _track(2), _track(3)];

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1280,
          height: 720,
          child: AlbumPlaybackView(
            album: album,
            tracks: tracks,
            currentTrack: tracks[1],
            playing: true,
            onClose: () {},
            onPrevious: () {},
            onToggle: () {},
            onNext: () {},
            canSwitchPreviousAlbum: false,
            canSwitchNextAlbum: false,
            onSwitchPreviousAlbum: null,
            onSwitchNextAlbum: null,
            onPlayTrack: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Album One'), findsNothing);
    expect(find.text('Artist · 2026 · 3 tracks'), findsNothing);

    final previous = find.byTooltip('Previous');
    final pause = find.byTooltip('Pause');
    final next = find.byTooltip('Next');
    expect(previous, findsOneWidget);
    expect(pause, findsOneWidget);
    expect(next, findsOneWidget);

    expect(tester.getSize(previous).width, closeTo(80.6, 0.5));
    expect(tester.getSize(pause).width, closeTo(112, 0.1));
    expect(tester.getSize(next).width, closeTo(80.6, 0.5));
    expect(tester.getSize(previous).height, closeTo(80.6, 0.5));
    expect(tester.getSize(pause).height, closeTo(112, 0.1));
    expect(tester.getSize(next).height, closeTo(80.6, 0.5));
    expect(tester.getCenter(pause).dx, closeTo(640, 0.1));
    expect(tester.getCenter(pause).dy, closeTo(636, 0.1));
  });

  testWidgets('bottom dock shows now playing album shortcut on the left', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final album = _album();
    final tracks = [_track(1), _track(2), _track(3)];
    var openNowPlayingCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1280,
          height: 720,
          child: AlbumPlaybackView(
            album: album,
            tracks: tracks,
            currentTrack: null,
            playing: false,
            nowPlayingAlbum: const AlbumPlaybackNowPlaying(
              coverArtPath: null,
              playing: true,
            ),
            onClose: () {},
            onPrevious: () {},
            onToggle: () {},
            onNext: () {},
            onOpenNowPlayingAlbum: () => openNowPlayingCount += 1,
            canSwitchPreviousAlbum: false,
            canSwitchNextAlbum: false,
            onSwitchPreviousAlbum: null,
            onSwitchNextAlbum: null,
            onPlayTrack: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final shortcut = find.byTooltip('Back to now playing');
    final play = find.byTooltip('Play');
    expect(shortcut, findsOneWidget);
    expect(play, findsOneWidget);
    expect(tester.getSize(shortcut).width, closeTo(96, 0.1));
    expect(tester.getCenter(shortcut).dx, closeTo(76, 0.1));
    expect(tester.getCenter(play).dx, closeTo(640, 0.1));

    await tester.tap(shortcut);
    await tester.pump();

    expect(openNowPlayingCount, 1);
  });

  testWidgets('large artwork morphs into a disc while album is active', (
    tester,
  ) async {
    final album = _album();
    final tracks = [_track(1), _track(2), _track(3)];

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1280,
          height: 720,
          child: AlbumPlaybackView(
            album: album,
            tracks: tracks,
            currentTrack: null,
            playing: false,
            onClose: () {},
            onPrevious: () {},
            onToggle: () {},
            onNext: () {},
            canSwitchPreviousAlbum: false,
            canSwitchNextAlbum: false,
            onSwitchPreviousAlbum: null,
            onSwitchNextAlbum: null,
            onPlayTrack: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('album-morphing-artwork')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('album-disc-sheen')), findsNothing);
    expect(find.byKey(const ValueKey('album-disc-hole')), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1280,
          height: 720,
          child: AlbumPlaybackView(
            album: album,
            tracks: tracks,
            currentTrack: tracks[1],
            playing: false,
            onClose: () {},
            onPrevious: () {},
            onToggle: () {},
            onNext: () {},
            canSwitchPreviousAlbum: false,
            canSwitchNextAlbum: false,
            onSwitchPreviousAlbum: null,
            onSwitchNextAlbum: null,
            onPlayTrack: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('album-morphing-artwork')),
      findsOneWidget,
    );
    expect(find.byType(RotationTransition), findsOneWidget);
    expect(find.byKey(const ValueKey('album-disc-sheen')), findsOneWidget);
    expect(find.byKey(const ValueKey('album-disc-hole')), findsOneWidget);
  });

  testWidgets('disc pauses and resumes without losing its angle', (
    tester,
  ) async {
    double turns() => tester
        .widget<RotationTransition>(find.byType(RotationTransition))
        .turns
        .value;

    await tester.pumpWidget(_discView(playing: true));
    await tester.pump(const Duration(seconds: 2));
    final spinningTurns = turns();
    expect(spinningTurns, greaterThan(0));

    await tester.pumpWidget(_discView(playing: false));
    await tester.pump(const Duration(seconds: 3));
    expect(turns(), spinningTurns);
    expect(find.byKey(const ValueKey('album-disc-sheen')), findsOneWidget);
    expect(find.byKey(const ValueKey('album-disc-hole')), findsOneWidget);

    await tester.pumpWidget(_discView(playing: true));
    await tester.pump();
    expect(turns(), closeTo(spinningTurns, 0.00001));
    await tester.pump(const Duration(seconds: 1));
    expect(turns(), closeTo(spinningTurns + 1 / 18, 0.00001));

    // Rebuilding for an unrelated state notification must not restart rotation.
    final beforeRebuild = turns();
    await tester.pumpWidget(_discView(playing: true));
    await tester.pump(const Duration(seconds: 1));
    expect(turns(), closeTo(beforeRebuild + 1 / 18, 0.00001));

    // A non-active album may still receive the global playing state. Its cover
    // must settle after morphing back, without a hidden repeating ticker.
    await tester.pumpWidget(_discView(playing: true, active: false));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('album-disc-hole')), findsNothing);
    expect(turns(), 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('disc starts during morphing and keeps its angle through hover', (
    tester,
  ) async {
    double turns() => tester
        .widget<RotationTransition>(find.byType(RotationTransition))
        .turns
        .value;

    await tester.pumpWidget(_discView(playing: true, active: false));
    await tester.pumpAndSettle();
    expect(turns(), 0);

    await tester.pumpWidget(_discView(playing: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    expect(turns(), closeTo(0.26 / 18, 0.00001));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('album-morphing-artwork'))),
    );
    await tester.pump(const Duration(milliseconds: 260));
    expect(turns(), closeTo(0.52 / 18, 0.00001));

    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(seconds: 1));
    expect(turns(), closeTo(1.52 / 18, 0.00001));

    // Reactivating before the shape transition ends must not reset rotation.
    final beforeMorph = turns();
    await tester.pumpWidget(_discView(playing: true, active: false));
    await tester.pump(const Duration(milliseconds: 260));
    expect(turns(), beforeMorph);
    await tester.pumpWidget(_discView(playing: true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(turns(), closeTo(beforeMorph + 1 / 18, 0.00001));
  });
}

Widget _discView({required bool playing, bool active = true}) {
  final tracks = [_track(1), _track(2), _track(3)];
  return MaterialApp(
    home: AlbumPlaybackView(
      album: _album(),
      tracks: tracks,
      currentTrack: active ? tracks[1] : null,
      playing: playing,
      onClose: () {},
      onPrevious: () {},
      onToggle: () {},
      onNext: () {},
      canSwitchPreviousAlbum: false,
      canSwitchNextAlbum: false,
      onSwitchPreviousAlbum: null,
      onSwitchNextAlbum: null,
      onPlayTrack: (_) {},
    ),
  );
}

AlbumSummary _album() {
  return const AlbumSummary(
    folderPath: '/music/artist/album',
    title: 'Album One',
    albumArtist: 'Artist',
    year: 2026,
    trackCount: 3,
    coverArtPath: null,
  );
}

Track _track(int trackNumber) {
  return Track(
    path: '/music/artist/album/${trackNumber.toString().padLeft(2, '0')}.flac',
    folderPath: '/music/artist/album',
    title: 'Track $trackNumber',
    artist: 'Artist',
    album: 'Album One',
    albumArtist: 'Artist',
    trackNumber: trackNumber,
    discNumber: 1,
    year: 2026,
    durationMs: 120000,
    sizeBytes: 42,
    modifiedMs: 99,
    coverArtPath: null,
  );
}
