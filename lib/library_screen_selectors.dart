import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'artwork_resolver.dart';
import 'library_screen_models.dart';
import 'library_sidebar.dart';
import 'models.dart';

ThemeMode themeModeFromDb(String value) {
  return value == 'dark' ? ThemeMode.dark : ThemeMode.light;
}

String themeModeToDb(ThemeMode mode) {
  return mode == ThemeMode.dark ? 'dark' : 'light';
}

String lastPlaybackStateKey(LastPlaybackState state) {
  return '${state.kind.dbValue}\n${state.folderPath}\n${state.trackPath}\n${state.playing}\n${state.shuffled}';
}

List<Track> shuffledTracks(List<Track> tracks, {math.Random? random}) {
  return tracks.toList(growable: false)..shuffle(random);
}

Track trackByPathOrFirst(List<Track> tracks, String path) {
  return tracks.firstWhere(
    (track) => track.path == path,
    orElse: () => tracks.first,
  );
}

bool activeAlbumStillAvailable({
  required LibraryActiveAlbumPlayback activeAlbum,
  required List<AlbumSummary> albums,
  required Set<String> currentTrackPaths,
}) {
  return albums.any(
        (album) => album.folderPath == activeAlbum.album.folderPath,
      ) &&
      activeAlbum.tracks.every(
        (track) => currentTrackPaths.contains(track.path),
      );
}

bool activePlaylistStillAvailable({
  required LibraryActivePlaylistPlayback activePlaylist,
  required List<FolderSummary> folders,
  required Set<String> currentTrackPaths,
}) {
  return folders.any((folder) => folder.path == activePlaylist.folderPath) &&
      activePlaylist.tracks.every(
        (track) => currentTrackPaths.contains(track.path),
      );
}

Track? currentTrackForAlbum({
  required LibraryActiveAlbumPlayback albumPlayback,
  required Track? currentTrack,
}) {
  if (currentTrack == null) {
    return null;
  }
  return albumPlayback.tracks.any((track) => track.path == currentTrack.path)
      ? currentTrack
      : null;
}

Track? currentTrackForPlaylist({
  required LibraryActivePlaylistPlayback playlistPlayback,
  required Track? currentTrack,
}) {
  if (currentTrack == null) {
    return null;
  }
  return playlistPlayback.tracks.any((track) => track.path == currentTrack.path)
      ? currentTrack
      : null;
}

Track? currentTrackForFavorites({
  required LibraryActiveFavoritesPlayback favoritesPlayback,
  required Track? currentTrack,
}) {
  if (currentTrack == null) {
    return null;
  }
  return favoritesPlayback.queue.any((track) => track.path == currentTrack.path)
      ? currentTrack
      : null;
}

AlbumSummary? albumForCurrentTrack(
  Track currentTrack,
  List<AlbumSummary> albums,
) {
  return albums
      .where((album) => album.folderPath == currentTrack.folderPath)
      .firstOrNull;
}

FolderSummary? playlistFolderForPath(String path, List<FolderSummary> folders) {
  return folders
      .where(
        (folder) => folder.kind == FolderKind.playlist && folder.path == path,
      )
      .firstOrNull;
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
  required Track? currentTrack,
  required bool playing,
  required LibraryActivePlaylistPlayback? activePlaylist,
  required LibraryActiveAlbumPlayback? activeAlbum,
  required LibraryActiveFavoritesPlayback? activeFavorites,
  required List<AlbumSummary> albums,
  required List<FolderSummary> folders,
  required List<Track> favoriteTracks,
  required Map<String, List<Track>> tracksByFolder,
  required Map<String, String?> trackCoverCache,
  required bool Function(List<Track> queue) isCurrentQueue,
}) {
  if (currentTrack == null) {
    return null;
  }

  if (activePlaylist != null &&
      currentTrackForPlaylist(
            playlistPlayback: activePlaylist,
            currentTrack: currentTrack,
          ) !=
          null) {
    final folder = playlistFolderForPath(activePlaylist.folderPath, folders);
    if (folder != null) {
      return LibraryNowPlayingTarget.playlist(
        folder: folder,
        tracks: activePlaylist.tracks,
        sidebarItem: SidebarNowPlaying.playlist(
          playlistCoverArtPaths: playlistCoverArtPaths(
            folder: folder,
            tracks: activePlaylist.tracks,
            trackCoverCache: trackCoverCache,
          ),
          playing: playing,
        ),
      );
    }
  }

  if (activeAlbum != null &&
      isCurrentQueue(activeAlbum.tracks) &&
      currentTrackForAlbum(
            albumPlayback: activeAlbum,
            currentTrack: currentTrack,
          ) !=
          null) {
    return LibraryNowPlayingTarget.album(
      album: activeAlbum.album,
      tracks: activeAlbum.tracks,
      sidebarItem: SidebarNowPlaying.album(
        coverArtPath: activeAlbum.album.coverArtPath,
        playing: playing,
      ),
    );
  }

  if (activeFavorites != null &&
      isCurrentQueue(activeFavorites.queue) &&
      currentTrackForFavorites(
            favoritesPlayback: activeFavorites,
            currentTrack: currentTrack,
          ) !=
          null) {
    return LibraryNowPlayingTarget.favorites(
      tracks: activeFavorites.tracks,
      sidebarItem: SidebarNowPlaying.playlist(
        playlistCoverArtPaths: favoriteCoverArtPaths(
          tracks: activeFavorites.tracks,
          trackCoverCache: trackCoverCache,
        ),
        playing: playing,
      ),
    );
  }

  if (favoriteTracks.isNotEmpty &&
      isCurrentQueue(favoriteTracks) &&
      favoriteTracks.any((track) => track.path == currentTrack.path)) {
    return LibraryNowPlayingTarget.favorites(
      tracks: favoriteTracks,
      sidebarItem: SidebarNowPlaying.playlist(
        playlistCoverArtPaths: favoriteCoverArtPaths(
          tracks: favoriteTracks,
          trackCoverCache: trackCoverCache,
        ),
        playing: playing,
      ),
    );
  }

  final album = albumForCurrentTrack(currentTrack, albums);
  if (album == null) {
    return null;
  }
  final tracks = tracksByFolder[album.folderPath] ?? const <Track>[];
  if (!isCurrentQueue(tracks)) {
    return null;
  }
  return LibraryNowPlayingTarget.album(
    album: album,
    tracks: tracks,
    sidebarItem: SidebarNowPlaying.album(
      coverArtPath: album.coverArtPath,
      playing: playing,
    ),
  );
}

LastPlaybackState? currentPlaybackState({
  required Track? currentTrack,
  required bool playing,
  required LibraryActivePlaylistPlayback? activePlaylist,
  required LibraryActiveAlbumPlayback? activeAlbum,
  required List<AlbumSummary> albums,
  required Map<String, List<Track>> tracksByFolder,
  required bool Function(List<Track> queue) isCurrentQueue,
}) {
  if (currentTrack == null) {
    return null;
  }

  if (activePlaylist != null &&
      currentTrackForPlaylist(
            playlistPlayback: activePlaylist,
            currentTrack: currentTrack,
          ) !=
          null) {
    return LastPlaybackState(
      kind: LastPlaybackKind.playlist,
      folderPath: activePlaylist.folderPath,
      trackPath: currentTrack.path,
      playing: playing,
      shuffled: activePlaylist.shuffled,
    );
  }

  if (activeAlbum != null &&
      isCurrentQueue(activeAlbum.tracks) &&
      currentTrackForAlbum(
            albumPlayback: activeAlbum,
            currentTrack: currentTrack,
          ) !=
          null) {
    return LastPlaybackState(
      kind: LastPlaybackKind.album,
      folderPath: activeAlbum.album.folderPath,
      trackPath: currentTrack.path,
      playing: playing,
      shuffled: false,
    );
  }

  final album = albumForCurrentTrack(currentTrack, albums);
  if (album == null) {
    return null;
  }
  final tracks = tracksByFolder[album.folderPath] ?? const <Track>[];
  if (!isCurrentQueue(tracks)) {
    return null;
  }
  return LastPlaybackState(
    kind: LastPlaybackKind.album,
    folderPath: album.folderPath,
    trackPath: currentTrack.path,
    playing: playing,
    shuffled: false,
  );
}
