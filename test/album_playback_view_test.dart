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
