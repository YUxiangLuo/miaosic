import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/artwork_resolver.dart';
import 'package:miaosic/library_diff.dart';
import 'package:miaosic/models.dart';

void main() {
  test('track artwork prefers per-track cache over folder artwork', () {
    final track = _track('/music/a.flac', cover: '/cache/folder.jpg');

    expect(
      resolveTrackArtwork(track, {track.path: '/cache/embedded.jpg'}),
      '/cache/embedded.jpg',
    );
    expect(resolveTrackArtwork(track, const {}), '/cache/folder.jpg');
  });

  test('diff artwork can fall back to removed track cover', () {
    final oldTrack = _track('/music/removed.flac', cover: '/cache/old.jpg');
    final change = TrackChange(
      path: oldTrack.path,
      oldTrack: oldTrack,
      newTrack: null,
      reason: TrackChangeReason.removed,
    );

    expect(resolveChangeArtwork(change, const {}), '/cache/old.jpg');
  });
}

Track _track(String path, {String? cover}) {
  return Track(
    path: path,
    folderPath: '/music',
    title: path,
    artist: 'Artist',
    album: 'Album',
    albumArtist: 'Artist',
    trackNumber: null,
    discNumber: null,
    year: null,
    durationMs: null,
    sizeBytes: 1,
    modifiedMs: 1,
    coverArtPath: cover,
  );
}
