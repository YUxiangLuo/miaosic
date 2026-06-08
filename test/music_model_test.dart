import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/models.dart';

void main() {
  test('recognizes FLAC files as supported audio', () {
    expect(isAudioPath('/music/A/01. Track.flac'), isTrue);
    expect(isAudioPath('/music/A/cover.jpg'), isFalse);
  });

  test('collapses disc folders into the parent album folder', () {
    final file = File('/music/Artist - Album (2001)/Disc 1/01. Song.flac');

    expect(logicalFolderFor(file), '/music/Artist - Album (2001)');
  });

  test('expands tilde music root paths', () {
    expect(normalizeMusicRootPath('~/Music'), defaultMusicRoot);
    expect(normalizeMusicRootPath(' /tmp/music '), '/tmp/music');
  });

  test('maps legacy mixed folders to playlists', () {
    expect(FolderKind.fromDb('mixed'), FolderKind.playlist);
  });

  test('maps nullable cover art paths on tracks', () {
    final track = Track.fromMap({
      'id': 1,
      'path': '/music/A/01. Song.flac',
      'folder_path': '/music/A',
      'title': 'Song',
      'artist': 'Artist',
      'album': 'Album',
      'album_artist': 'Artist',
      'track_number': 1,
      'disc_number': 1,
      'year': 2024,
      'duration_ms': 120000,
      'size_bytes': 42,
      'modified_ms': 99,
      'cover_art_path': '/cache/cover.jpg',
    });

    expect(track.coverArtPath, '/cache/cover.jpg');
    expect(track.toMap()['cover_art_path'], '/cache/cover.jpg');
  });
}
