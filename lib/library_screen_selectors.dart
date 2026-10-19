import 'package:flutter/material.dart';

import 'artwork_resolver.dart';
import 'library_screen_models.dart';
import 'library_sidebar.dart';
import 'models.dart';
import 'playback_session.dart';

ThemeMode themeModeFromDb(String value) {
  return value == 'dark' ? ThemeMode.dark : ThemeMode.light;
}

String themeModeToDb(ThemeMode mode) {
  return mode == ThemeMode.dark ? 'dark' : 'light';
}

FolderSummary? playlistFolderForPath(String path, List<FolderSummary> folders) {
  return folders
      .where(
        (folder) => folder.kind == FolderKind.playlist && folder.path == path,
      )
      .firstOrNull;
}

FolderSummary? livePlaylistOverlayFolder({
  required FolderSummary? stored,
  required List<FolderSummary> folders,
}) {
  if (stored == null) {
    return null;
  }
  return playlistFolderForPath(stored.path, folders) ?? stored;
}

LibraryPlaylistPlaybackSwitchTarget? playlistPlaybackSwitchTarget({
  required FolderSummary folder,
  required int delta,
  required List<FolderSummary> folders,
  required Map<String, List<Track>> tracksByFolder,
}) {
  if (folders.length < 2 || delta == 0) {
    return null;
  }
  final currentIndex = folders.indexWhere(
    (candidate) => candidate.path == folder.path,
  );
  if (currentIndex < 0) {
    return null;
  }

  final step = delta.sign;
  for (var offset = 1; offset < folders.length; offset += 1) {
    final index = (currentIndex + step * offset) % folders.length;
    final nextFolder = folders[index];
    final nextTracks = tracksByFolder[nextFolder.path] ?? const <Track>[];
    if (nextTracks.isNotEmpty) {
      return LibraryPlaylistPlaybackSwitchTarget(
        folder: nextFolder,
        tracks: nextTracks,
      );
    }
  }
  return null;
}

LibraryAlbumPlaybackSwitchTarget? albumPlaybackSwitchTarget({
  required AlbumSummary album,
  required int delta,
  required List<AlbumSummary> albums,
  required Map<String, List<Track>> tracksByFolder,
}) {
  if (albums.length < 2 || delta == 0) {
    return null;
  }
  final currentIndex = albums.indexWhere(
    (candidate) => candidate.folderPath == album.folderPath,
  );
  if (currentIndex < 0) {
    return null;
  }

  final step = delta.sign;
  for (var offset = 1; offset < albums.length; offset += 1) {
    final index = (currentIndex + step * offset) % albums.length;
    final nextAlbum = albums[index];
    final nextTracks = tracksByFolder[nextAlbum.folderPath] ?? const <Track>[];
    if (nextTracks.isNotEmpty) {
      return LibraryAlbumPlaybackSwitchTarget(
        album: nextAlbum,
        tracks: nextTracks,
      );
    }
  }
  return null;
}

List<String?> favoriteCoverArtPaths({
  required List<Track> tracks,
  required Map<String, String?> trackCoverCache,
}) {
  return tracks
      .take(4)
      .map((track) => resolveTrackArtwork(track, trackCoverCache))
      .toList(growable: false);
}

List<String?> playlistCoverArtPaths({
  required FolderSummary folder,
  required List<Track> tracks,
  required Map<String, String?> trackCoverCache,
}) {
  final paths = tracks
      .take(4)
      .map((track) => resolveTrackArtwork(track, trackCoverCache))
      .toList(growable: true);
  if (paths.every((path) => path == null || path.isEmpty)) {
    paths
      ..clear()
      ..add(folder.coverArtPath);
  }
  return paths;
}

LibraryNowPlayingTarget? nowPlayingTarget({
  required PlaybackSession? session,
  required bool playing,
  required List<AlbumSummary> albums,
  required List<FolderSummary> folders,
  required Map<String, String?> trackCoverCache,
}) {
  if (session == null) return null;
  switch (session.kind) {
    case LastPlaybackKind.album:
      final album = albums
          .where((album) => album.folderPath == session.folderPath)
          .firstOrNull;
      if (album == null) return null;
      return LibraryNowPlayingTarget.album(
        album: album,
        tracks: session.tracks,
        sidebarItem: SidebarNowPlaying.album(
          coverArtPath: album.coverArtPath,
          playing: playing,
        ),
      );
    case LastPlaybackKind.playlist:
      final folder = playlistFolderForPath(session.folderPath, folders);
      if (folder == null) return null;
      return LibraryNowPlayingTarget.playlist(
        folder: folder,
        tracks: session.tracks,
        sidebarItem: SidebarNowPlaying.playlist(
          playlistCoverArtPaths: playlistCoverArtPaths(
            folder: folder,
            tracks: session.tracks,
            trackCoverCache: trackCoverCache,
          ),
          playing: playing,
        ),
      );
    case LastPlaybackKind.favorites:
      return LibraryNowPlayingTarget.favorites(
        tracks: session.tracks,
        sidebarItem: SidebarNowPlaying.playlist(
          playlistCoverArtPaths: favoriteCoverArtPaths(
            tracks: session.tracks,
            trackCoverCache: trackCoverCache,
          ),
          playing: playing,
        ),
      );
  }
}
