import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/library_screen_selectors.dart';
import 'package:miaosic/library_sidebar.dart';
import 'package:miaosic/models.dart';
import 'package:miaosic/playback_session.dart';

void main() {
  test('album switch target skips empty albums and wraps', () {
    final albums = [
      _album('/music/a', 'A'),
      _album('/music/b', 'B'),
      _album('/music/c', 'C'),
    ];
    final tracksByFolder = {
      albums[0].folderPath: [_track(albums[0].folderPath)],
      albums[2].folderPath: [_track(albums[2].folderPath)],
    };

    final next = albumPlaybackSwitchTarget(
      album: albums[0],
      delta: 1,
      albums: albums,
      tracksByFolder: tracksByFolder,
    );
    final wrapped = albumPlaybackSwitchTarget(
      album: albums[2],
      delta: 1,
      albums: albums,
      tracksByFolder: tracksByFolder,
    );

    expect(next?.album.folderPath, albums[2].folderPath);
    expect(wrapped?.album.folderPath, albums[0].folderPath);
  });

  test('playlist switch target skips empty folders and wraps', () {
    final folders = [
      _folder('/music/a'),
      _folder('/music/b'),
      _folder('/music/c'),
    ];
    final tracksByFolder = {
      folders[0].path: [_track(folders[0].path)],
      folders[2].path: [_track(folders[2].path)],
    };

    final next = playlistPlaybackSwitchTarget(
      folder: folders[0],
      delta: 1,
      folders: folders,
      tracksByFolder: tracksByFolder,
    );
    final wrapped = playlistPlaybackSwitchTarget(
      folder: folders[2],
      delta: 1,
      folders: folders,
      tracksByFolder: tracksByFolder,
    );

    expect(next?.folder.path, folders[2].path);
    expect(wrapped?.folder.path, folders[0].path);
  });

  test('playlist overlay folder prefers the live library summary', () {
    final stored = FolderSummary(
      path: '/music/mix',
      name: 'Old Name',
      kind: FolderKind.playlist,
      confidence: 0.8,
      trackCount: 1,
      albumCount: 1,
      albumArtistCount: 1,
      artistCount: 1,
      yearCount: 1,
      coverArtPath: null,
    );
    final live = FolderSummary(
      path: stored.path,
      name: 'New Name',
      kind: FolderKind.playlist,
      confidence: 0.8,
      trackCount: 4,
      albumCount: 2,
      albumArtistCount: 1,
      artistCount: 2,
      yearCount: 1,
      coverArtPath: '/covers/mix.jpg',
    );

    final resolved = livePlaylistOverlayFolder(stored: stored, folders: [live]);
    final missing = livePlaylistOverlayFolder(
      stored: stored,
      folders: const [],
    );

    expect(resolved?.name, 'New Name');
    expect(resolved?.trackCount, 4);
    expect(missing?.name, 'Old Name');
  });

  test('playlist artwork uses track cache before folder fallback', () {
    final folder = _folder('/music/mix', coverArtPath: '/covers/folder.jpg');
    final tracks = [
      _track(folder.path, path: '${folder.path}/1.flac'),
      _track(folder.path, path: '${folder.path}/2.flac', coverArtPath: ''),
    ];

    final cached = playlistCoverArtPaths(
      folder: folder,
      tracks: tracks,
      trackCoverCache: {tracks.first.path: '/covers/track.jpg'},
    );
    final fallback = playlistCoverArtPaths(
      folder: folder,
      tracks: tracks,
      trackCoverCache: const {},
    );

    expect(cached, ['/covers/track.jpg', '']);
    expect(fallback, ['/covers/folder.jpg']);
  });

  for (final kind in LastPlaybackKind.values) {
    test('now playing keeps the explicit ${kind.name} source', () {
      final album = _album('/music/collection', 'Album');
      final folder = _folder(album.folderPath);
      final track = _track(album.folderPath);
      final target = nowPlayingTarget(
        session: PlaybackSession.start(
          kind: kind,
          folderPath: kind == LastPlaybackKind.favorites ? '' : folder.path,
          tracks: [track],
        ),
        playing: true,
        albums: [album],
        folders: [folder],
        trackCoverCache: const {},
      );
      expect(target?.kind, kind);
      expect(target?.tracks.single.path, track.path);
      expect(
        target?.sidebarItem.kind,
        kind == LastPlaybackKind.album
            ? SidebarNowPlayingKind.album
            : SidebarNowPlayingKind.playlist,
      );
    });
  }

  for (final kind in [LastPlaybackKind.playlist, LastPlaybackKind.favorites]) {
    test(
      'now playing preserves shuffled ${kind.name} order and persistence',
      () {
        final folder = _folder('/music/collection');
        final first = _track(folder.path, path: '${folder.path}/1.flac');
        final second = _track(folder.path, path: '${folder.path}/2.flac');
        final session = PlaybackSession.start(
          kind: kind,
          folderPath: kind == LastPlaybackKind.favorites ? '' : folder.path,
          tracks: [first, second],
          queue: [second, first],
          shuffled: true,
        );
        final target = nowPlayingTarget(
          session: session,
          playing: true,
          albums: const [],
          folders: [folder],
          trackCoverCache: const {},
        );
        expect(target?.tracks.map((track) => track.path), [
          first.path,
          second.path,
        ]);
        expect(target?.queue.map((track) => track.path), [
          second.path,
          first.path,
        ]);
        expect(target?.shuffled, isTrue);
        final state = session.savedState(playing: true);
        expect(state?.kind, kind);
        expect(state?.folderPath, session.folderPath);
        expect(state?.trackPath, second.path);
        expect(state?.playing, isTrue);
        expect(state?.shuffled, isTrue);
      },
    );
  }

  test('theme and last playback values stay stable', () {
    const state = LastPlaybackState(
      kind: LastPlaybackKind.playlist,
      folderPath: '/music/playlist',
      trackPath: '/music/playlist/1.flac',
      playing: true,
      shuffled: true,
    );

    expect(themeModeFromDb('dark'), ThemeMode.dark);
    expect(themeModeFromDb('anything'), ThemeMode.light);
    expect(themeModeToDb(ThemeMode.dark), 'dark');
    expect(themeModeToDb(ThemeMode.light), 'light');
    expect(
      lastPlaybackStateKey(state),
      'playlist\n/music/playlist\n/music/playlist/1.flac\ntrue\ntrue',
    );
  });
}

AlbumSummary _album(String folderPath, String title) {
  return AlbumSummary(
    folderPath: folderPath,
    title: title,
    albumArtist: 'Artist',
    year: 2026,
    trackCount: 1,
    coverArtPath: null,
  );
}

FolderSummary _folder(String path, {String? coverArtPath}) {
  return FolderSummary(
    path: path,
    name: 'Playlist',
    kind: FolderKind.playlist,
    confidence: 0.9,
    trackCount: 1,
    albumCount: 1,
    albumArtistCount: 1,
    artistCount: 1,
    yearCount: 1,
    coverArtPath: coverArtPath,
  );
}

Track _track(String folderPath, {String? path, String? coverArtPath}) {
  return Track(
    path: path ?? '$folderPath/1.flac',
    folderPath: folderPath,
    title: 'Track',
    artist: 'Artist',
    album: 'Album',
    albumArtist: 'Artist',
    trackNumber: 1,
    discNumber: 1,
    year: 2026,
    durationMs: 120000,
    sizeBytes: 42,
    modifiedMs: 99,
    coverArtPath: coverArtPath,
  );
}
