import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/library_diff.dart';
import 'package:miaosic/models.dart';

void main() {
  test('diffs tracks by path using size and modified time', () {
    final unchanged = _track('/music/a.flac', size: 10, modified: 1);
    final changedOld = _track('/music/b.flac', size: 10, modified: 1);
    final removed = _track('/music/c.flac', size: 10, modified: 1);
    final changedNew = _track('/music/b.flac', size: 11, modified: 1);
    final added = _track('/music/d.flac', size: 10, modified: 1);

    final diff = diffLibrary(
      LibrarySnapshot(
        tracks: [unchanged, changedOld, removed],
        folders: const [],
        albums: const [],
        scanState: null,
      ),
      _scanResult([unchanged, changedNew, added]),
    );

    expect(diff.added.map((change) => change.path), ['/music/d.flac']);
    expect(diff.removed.map((change) => change.path), ['/music/c.flac']);
    expect(diff.modified.map((change) => change.path), ['/music/b.flac']);
    expect(diff.unchangedCount, 1);
  });

  test('flags large deletion risk by count or ratio', () {
    final byCount = LibraryDiff(
      added: const [],
      removed: List.generate(
        100,
        (index) => TrackChange(
          path: '/music/$index.flac',
          oldTrack: _track('/music/$index.flac'),
          newTrack: null,
          reason: TrackChangeReason.removed,
        ),
      ),
      modified: const [],
      unchangedCount: 1000,
      result: _scanResult(const []),
    );
    final byRatio = LibraryDiff(
      added: const [],
      removed: [
        TrackChange(
          path: '/music/a.flac',
          oldTrack: _track('/music/a.flac'),
          newTrack: null,
          reason: TrackChangeReason.removed,
        ),
      ],
      modified: const [],
      unchangedCount: 9,
      result: _scanResult(const []),
    );

    expect(byCount.deletionRisk().isLargeDeletion, isTrue);
    expect(byRatio.deletionRisk().isLargeDeletion, isTrue);
  });
}

ScanResult _scanResult(List<Track> tracks) {
  return ScanResult(
    rootPath: '/music',
    engine: 'test',
    tracks: tracks,
    folders: const [],
    albums: const [],
    elapsed: Duration.zero,
    coversCached: 0,
  );
}

Track _track(String path, {int size = 1, int modified = 1}) {
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
    sizeBytes: size,
    modifiedMs: modified,
    coverArtPath: null,
  );
}
