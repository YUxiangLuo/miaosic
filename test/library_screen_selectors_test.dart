import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/library_screen_models.dart';
import 'package:miaosic/library_screen_selectors.dart';
import 'package:miaosic/library_sidebar.dart';
import 'package:miaosic/models.dart';

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

  test('now playing prefers active playlist over active album', () {
    final album = _album('/music/album', 'Album');
    final playlist = _folder('/music/playlist');
    final playlistTrack = _track(playlist.path);
    final albumTrack = _track(album.folderPath);
    final activePlaylist = LibraryActivePlaylistPlayback(
      folderPath: playlist.path,
      tracks: [playlistTrack],
      shuffled: false,
    );
    final activeAlbum = LibraryActiveAlbumPlayback(
      album: album,
      tracks: [albumTrack, playlistTrack],
    );

    final target = nowPlayingTarget(
      currentTrack: playlistTrack,
      playing: true,
      activePlaylist: activePlaylist,
      activeAlbum: activeAlbum,
      activeFavorites: null,
      albums: [album],
      folders: [playlist],
      favoriteTracks: const [],
      tracksByFolder: {
        album.folderPath: [albumTrack],
        playlist.path: [playlistTrack],
      },
      trackCoverCache: const {},
      isCurrentQueue: (_) => true,
    );

    expect(target?.kind, LibraryNowPlayingKind.playlist);
    expect(target?.folder?.path, playlist.path);
    expect(target?.sidebarItem.kind, SidebarNowPlayingKind.playlist);
  });

  test('now playing can target the favorites queue', () {
    final favoriteTrack = _track('/music/favorites');

    final target = nowPlayingTarget(
      currentTrack: favoriteTrack,
      playing: true,
      activePlaylist: null,
      activeAlbum: null,
      activeFavorites: null,
      albums: const [],
      folders: const [],
      favoriteTracks: [favoriteTrack],
      tracksByFolder: const {},
      trackCoverCache: const {},
      isCurrentQueue: (queue) => queue.single.path == favoriteTrack.path,
    );

    expect(target?.kind, LibraryNowPlayingKind.favorites);
    expect(target?.tracks.single.path, favoriteTrack.path);
    expect(target?.queue.single.path, favoriteTrack.path);
    expect(target?.shuffled, isFalse);
    expect(target?.sidebarItem.kind, SidebarNowPlayingKind.playlist);
  });

  test('now playing preserves active shuffled favorites queue', () {
    final first = _track('/music/favorites', path: '/music/favorites/1.flac');
    final second = _track('/music/favorites', path: '/music/favorites/2.flac');
    final tracks = [first, second];
    final queue = [second, first];
    final activeFavorites = LibraryActiveFavoritesPlayback(
      tracks: tracks,
      queue: queue,
      shuffled: true,
    );

    final target = nowPlayingTarget(
      currentTrack: second,
      playing: true,
      activePlaylist: null,
      activeAlbum: null,
      activeFavorites: activeFavorites,
      albums: const [],
      folders: const [],
      favoriteTracks: tracks,
      tracksByFolder: const {},
      trackCoverCache: const {},
      isCurrentQueue: (candidate) =>
          candidate.map((track) => track.path).join('|') ==
          queue.map((track) => track.path).join('|'),
    );

    expect(target?.kind, LibraryNowPlayingKind.favorites);
    expect(target?.tracks.map((track) => track.path), [
      first.path,
      second.path,
    ]);
    expect(target?.queue.map((track) => track.path), [second.path, first.path]);
    expect(target?.shuffled, isTrue);
  });

  test('current playback state persists an active favorites queue', () {
    final first = _track('/music/favorites', path: '/music/favorites/1.flac');
    final second = _track('/music/favorites', path: '/music/favorites/2.flac');
    final queue = [second, first];
    final activeFavorites = LibraryActiveFavoritesPlayback(
      tracks: [first, second],
      queue: queue,
      shuffled: true,
    );

    final state = currentPlaybackState(
      currentTrack: second,
      playing: true,
      activePlaylist: null,
      activeAlbum: null,
      activeFavorites: activeFavorites,
      albums: const [],
      tracksByFolder: const {},
      isCurrentQueue: (candidate) =>
          candidate.map((track) => track.path).join('|') ==
          queue.map((track) => track.path).join('|'),
    );

    expect(state?.kind, LastPlaybackKind.favorites);
    expect(state?.folderPath, isEmpty);
    expect(state?.trackPath, second.path);
    expect(state?.playing, isTrue);
    expect(state?.shuffled, isTrue);
  });

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
