import 'package:flutter/widgets.dart';

import 'library_sidebar.dart';
import 'library_types.dart';
import 'models.dart';

class LibraryAlbumSelection {
  const LibraryAlbumSelection({required this.album, required this.tracks});

  final AlbumSummary album;
  final List<Track> tracks;
}

class LibraryAlbumPlaybackSwitchTarget {
  const LibraryAlbumPlaybackSwitchTarget({
    required this.album,
    required this.tracks,
  });

  final AlbumSummary album;
  final List<Track> tracks;
}

class LibraryPlaylistPlaybackSwitchTarget {
  const LibraryPlaylistPlaybackSwitchTarget({
    required this.folder,
    required this.tracks,
  });

  final FolderSummary folder;
  final List<Track> tracks;
}

class LibraryPlaybackOverlay {
  const LibraryPlaybackOverlay.album({
    required this.album,
    required this.tracks,
  }) : kind = LastPlaybackKind.album,
       folder = null;

  const LibraryPlaybackOverlay.playlist({
    required this.folder,
    required this.tracks,
  }) : kind = LastPlaybackKind.playlist,
       album = null;

  const LibraryPlaybackOverlay.favorites()
    : kind = LastPlaybackKind.favorites,
      album = null,
      folder = null,
      tracks = const [];

  final LastPlaybackKind kind;
  final AlbumSummary? album;
  final FolderSummary? folder;
  final List<Track> tracks;

  bool get isAlbum => kind == LastPlaybackKind.album;
  bool get isPlaylist => kind == LastPlaybackKind.playlist;
  bool get isFavorites => kind == LastPlaybackKind.favorites;
}

class LibraryNowPlayingTarget {
  const LibraryNowPlayingTarget.album({
    required AlbumSummary this.album,
    required List<Track> tracks,
    required this.sidebarItem,
  }) : kind = LastPlaybackKind.album,
       tracks = tracks,
       queue = tracks,
       shuffled = false,
       folder = null;

  const LibraryNowPlayingTarget.playlist({
    required FolderSummary this.folder,
    required this.tracks,
    required this.queue,
    required this.shuffled,
    required this.sidebarItem,
  }) : kind = LastPlaybackKind.playlist,
       album = null;

  const LibraryNowPlayingTarget.favorites({
    required this.tracks,
    required this.queue,
    required this.shuffled,
    required this.sidebarItem,
  }) : kind = LastPlaybackKind.favorites,
       album = null,
       folder = null;

  final LastPlaybackKind kind;
  final AlbumSummary? album;
  final FolderSummary? folder;
  final List<Track> tracks;
  final List<Track> queue;
  final bool shuffled;
  final SidebarNowPlaying sidebarItem;
}

class LibraryScrollMemory {
  final albumGridScrollController = ScrollController();
  final playlistListScrollController = ScrollController();
  final favoritesListScrollController = ScrollController();

  double _albumGridScrollOffset = 0;
  double _playlistListScrollOffset = 0;
  double _favoritesListScrollOffset = 0;

  void dispose() {
    albumGridScrollController.dispose();
    playlistListScrollController.dispose();
    favoritesListScrollController.dispose();
  }

  void saveAlbumGridScrollOffset() {
    if (albumGridScrollController.hasClients) {
      _albumGridScrollOffset = albumGridScrollController.offset;
    }
  }

  void restoreAlbumGridScrollOffset({
    required bool Function() isMounted,
    required LibraryView Function() currentView,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted() ||
          currentView() != LibraryView.albums ||
          !albumGridScrollController.hasClients) {
        return;
      }
      final position = albumGridScrollController.position;
      final target = _albumGridScrollOffset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      albumGridScrollController.jumpTo(target);
    });
  }

  void savePlaylistListScrollOffset() {
    if (playlistListScrollController.hasClients) {
      _playlistListScrollOffset = playlistListScrollController.offset;
    }
  }

  void restorePlaylistListScrollOffset({
    required bool Function() isMounted,
    required LibraryView Function() currentView,
    required bool Function() hasPlaylistOverlay,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted() ||
          currentView() != LibraryView.playlists ||
          hasPlaylistOverlay() ||
          !playlistListScrollController.hasClients) {
        return;
      }
      final position = playlistListScrollController.position;
      final target = _playlistListScrollOffset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      playlistListScrollController.jumpTo(target);
    });
  }

  void saveFavoritesListScrollOffset() {
    if (favoritesListScrollController.hasClients) {
      _favoritesListScrollOffset = favoritesListScrollController.offset;
    }
  }

  void restoreFavoritesListScrollOffset({
    required bool Function() isMounted,
    required LibraryView Function() currentView,
    required bool Function() hasFavoritesOverlay,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted() ||
          currentView() != LibraryView.favorites ||
          hasFavoritesOverlay() ||
          !favoritesListScrollController.hasClients) {
        return;
      }
      final position = favoritesListScrollController.position;
      final target = _favoritesListScrollOffset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      favoritesListScrollController.jumpTo(target);
    });
  }
}
