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

  testWidgets('large artwork morphs into a disc only while album is playing', (
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
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('album-morphing-artwork')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('album-disc-sheen')), findsOneWidget);
    expect(find.byKey(const ValueKey('album-disc-hole')), findsOneWidget);
  });
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
