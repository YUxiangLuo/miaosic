import 'package:flutter/widgets.dart';

import 'library_sidebar.dart';
import 'library_types.dart';
import 'models.dart';

class LibraryActiveAlbumPlayback {
  const LibraryActiveAlbumPlayback({required this.album, required this.tracks});

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
  }) : kind = LibraryNowPlayingKind.album,
       folder = null;

  const LibraryPlaybackOverlay.playlist({
    required this.folder,
    required this.tracks,
  }) : kind = LibraryNowPlayingKind.playlist,
       album = null;

  const LibraryPlaybackOverlay.favorites()
    : kind = LibraryNowPlayingKind.favorites,
      album = null,
      folder = null,
      tracks = const [];

  final LibraryNowPlayingKind kind;
  final AlbumSummary? album;
  final FolderSummary? folder;
  final List<Track> tracks;

  bool get isAlbum => kind == LibraryNowPlayingKind.album;
  bool get isPlaylist => kind == LibraryNowPlayingKind.playlist;
  bool get isFavorites => kind == LibraryNowPlayingKind.favorites;
}

class LibraryActivePlaylistPlayback {
  const LibraryActivePlaylistPlayback({
    required this.folderPath,
    required this.tracks,
    required this.queue,
    required this.shuffled,
  });

  final String folderPath;
  final List<Track> tracks;
  final List<Track> queue;
  final bool shuffled;
}

class LibraryActiveFavoritesPlayback {
  const LibraryActiveFavoritesPlayback({
    required this.tracks,
    required this.queue,
    required this.shuffled,
  });

  final List<Track> tracks;
  final List<Track> queue;
  final bool shuffled;
}

enum LibraryNowPlayingKind { album, playlist, favorites }

class LibraryNowPlayingTarget {
  const LibraryNowPlayingTarget.album({
    required AlbumSummary this.album,
    required List<Track> tracks,
    required this.sidebarItem,
  }) : kind = LibraryNowPlayingKind.album,
       tracks = tracks,
       queue = tracks,
       shuffled = false,
       folder = null;

  const LibraryNowPlayingTarget.playlist({
    required FolderSummary this.folder,
    required List<Track> tracks,
    required this.sidebarItem,
  }) : kind = LibraryNowPlayingKind.playlist,
       tracks = tracks,
       queue = tracks,
       shuffled = false,
       album = null;

  const LibraryNowPlayingTarget.favorites({
    required this.tracks,
    required this.queue,
    required this.shuffled,
    required this.sidebarItem,
  }) : kind = LibraryNowPlayingKind.favorites,
       album = null,
       folder = null;

  final LibraryNowPlayingKind kind;
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
