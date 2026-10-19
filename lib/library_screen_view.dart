import 'package:flutter/material.dart';

import 'album_playback_view.dart';
import 'album_views.dart';
import 'favorite_views.dart';
import 'favorites_playback_view.dart';
import 'library_screen_models.dart';
import 'library_sidebar.dart';
import 'library_types.dart';
import 'models.dart';
import 'playlist_playback_view.dart';
import 'playlist_views.dart';

class LibraryScreenViewModel {
  const LibraryScreenViewModel({
    required this.selectedView,
    required this.browseView,
    required this.loading,
    required this.albums,
    required this.playlistFolders,
    required this.playlistCount,
    required this.favoriteTracks,
    required this.favoriteCount,
    required this.favoriteTrackPaths,
    required this.favoritesPlaybackActive,
    required this.tracksByFolder,
    required this.trackCoverCache,
    required this.themeMode,
    required this.nowPlayingTarget,
    required this.activeAlbumPlayback,
    required this.activeAlbumTrack,
    required this.dockNowPlayingAlbumTarget,
    required this.activePlaylistOverlayFolder,
    required this.activePlaylistOverlayTracks,
    required this.activePlaylistTrack,
    required this.playlistOverlayPlaybackActive,
    required this.favoritesOverlayOpen,
    required this.playbackCurrentTrack,
    required this.playbackPlaying,
    required this.albumGridScrollController,
    required this.playlistListScrollController,
    required this.favoritesListScrollController,
    required this.canSwitchPreviousAlbum,
    required this.canSwitchNextAlbum,
    required this.canSwitchPreviousPlaylist,
    required this.canSwitchNextPlaylist,
  });

  final LibraryView selectedView;
  final LibraryView browseView;
  final bool loading;
  final List<AlbumSummary> albums;
  final List<FolderSummary> playlistFolders;
  final int playlistCount;
  final List<Track> favoriteTracks;
  final int favoriteCount;
  final Set<String> favoriteTrackPaths;
  final bool favoritesPlaybackActive;
  final Map<String, List<Track>> tracksByFolder;
  final Map<String, String?> trackCoverCache;
  final ThemeMode themeMode;
  final LibraryNowPlayingTarget? nowPlayingTarget;
  final LibraryAlbumSelection? activeAlbumPlayback;
  final Track? activeAlbumTrack;
  final LibraryNowPlayingTarget? dockNowPlayingAlbumTarget;
  final FolderSummary? activePlaylistOverlayFolder;
  final List<Track> activePlaylistOverlayTracks;
  final Track? activePlaylistTrack;
  final bool playlistOverlayPlaybackActive;
  final bool favoritesOverlayOpen;
  final Track? playbackCurrentTrack;
  final bool playbackPlaying;
  final ScrollController albumGridScrollController;
  final ScrollController playlistListScrollController;
  final ScrollController favoritesListScrollController;
  final bool canSwitchPreviousAlbum;
  final bool canSwitchNextAlbum;
  final bool canSwitchPreviousPlaylist;
  final bool canSwitchNextPlaylist;
}

class LibraryScreenViewActions {
  const LibraryScreenViewActions({
    required this.onOpenLibrary,
    required this.onToggleThemeMode,
    required this.onOpenSettings,
    required this.onOpenNowPlaying,
    required this.onSelectedView,
    required this.onOpenAlbum,
    required this.onCloseAlbumPlayback,
    required this.onAlbumPrevious,
    required this.onAlbumToggle,
    required this.onAlbumNext,
    required this.onOpenNowPlayingAlbum,
    required this.onSwitchPreviousAlbum,
    required this.onSwitchNextAlbum,
    required this.onPlayAlbumTrack,
    required this.onToggleFavoriteTrack,
    required this.onFavoritePlayAll,
    required this.onFavoriteShuffleAll,
    required this.onFavoritePrevious,
    required this.onFavoriteTogglePlayback,
    required this.onFavoriteNext,
    required this.onOpenPlaylistPlayback,
    required this.onCloseFavoritesPlayback,
    required this.onOpenNowPlayingFromFavorites,
    required this.onClosePlaylistPlayback,
    required this.onSwitchPreviousPlaylist,
    required this.onSwitchNextPlaylist,
    required this.onOpenNowPlayingFromPlaylist,
    required this.onPlaylistPlayAll,
    required this.onPlaylistShuffleAll,
    required this.onPlaylistPrevious,
    required this.onPlaylistTogglePlayback,
    required this.onPlaylistNext,
    required this.onPlayPlaylistTrack,
    required this.onPlayFavoriteTrack,
  });

  final VoidCallback? onOpenLibrary;
  final VoidCallback? onToggleThemeMode;
  final VoidCallback? onOpenSettings;
  final ValueChanged<LibraryNowPlayingTarget> onOpenNowPlaying;
  final ValueChanged<LibraryView> onSelectedView;
  final void Function(AlbumSummary album, List<Track> tracks) onOpenAlbum;
  final VoidCallback onCloseAlbumPlayback;
  final VoidCallback? onAlbumPrevious;
  final VoidCallback? onAlbumToggle;
  final VoidCallback? onAlbumNext;
  final VoidCallback? onOpenNowPlayingAlbum;
  final VoidCallback? onSwitchPreviousAlbum;
  final VoidCallback? onSwitchNextAlbum;
  final ValueChanged<Track> onPlayAlbumTrack;
  final ValueChanged<Track> onToggleFavoriteTrack;
  final VoidCallback? onFavoritePlayAll;
  final VoidCallback? onFavoriteShuffleAll;
  final VoidCallback? onFavoritePrevious;
  final VoidCallback? onFavoriteTogglePlayback;
  final VoidCallback? onFavoriteNext;
  final ValueChanged<FolderSummary> onOpenPlaylistPlayback;
  final VoidCallback onCloseFavoritesPlayback;
  final VoidCallback? onOpenNowPlayingFromFavorites;
  final VoidCallback onClosePlaylistPlayback;
  final VoidCallback? onSwitchPreviousPlaylist;
  final VoidCallback? onSwitchNextPlaylist;
  final VoidCallback? onOpenNowPlayingFromPlaylist;
  final VoidCallback? onPlaylistPlayAll;
  final VoidCallback? onPlaylistShuffleAll;
  final VoidCallback? onPlaylistPrevious;
  final VoidCallback? onPlaylistTogglePlayback;
  final VoidCallback? onPlaylistNext;
  final ValueChanged<Track> onPlayPlaylistTrack;
  final ValueChanged<Track> onPlayFavoriteTrack;
}

class LibraryScreenView extends StatelessWidget {
  const LibraryScreenView({
    super.key,
    required this.model,
    required this.actions,
  });

  final LibraryScreenViewModel model;
  final LibraryScreenViewActions actions;

  @override
  Widget build(BuildContext context) {
    final activeAlbumPlayback = model.activeAlbumPlayback;
    final activePlaylistOverlayFolder = model.activePlaylistOverlayFolder;
    final overlayOpen =
        activeAlbumPlayback != null ||
        activePlaylistOverlayFolder != null ||
        model.favoritesOverlayOpen;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Visibility(
            visible: !overlayOpen,
            maintainState: true,
            child: Row(
              children: [
                RepaintBoundary(
                  child: LibrarySidebar(
                    selected: model.selectedView,
                    albums: model.albums.length,
                    playlists: model.playlistCount,
                    favorites: model.favoriteCount,
                    nowPlaying: model.nowPlayingTarget?.sidebarItem,
                    themeMode: model.themeMode,
                    onOpenLibrary: actions.onOpenLibrary,
                    onToggleThemeMode: actions.onToggleThemeMode,
                    onOpenSettings: actions.onOpenSettings,
                    onOpenNowPlaying: model.nowPlayingTarget == null
                        ? null
                        : () =>
                              actions.onOpenNowPlaying(model.nowPlayingTarget!),
                    onSelected: actions.onSelectedView,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: RepaintBoundary(
                    child: _buildContent(overlayOpen: overlayOpen),
                  ),
                ),
              ],
            ),
          ),
          if (activeAlbumPlayback != null)
            Positioned.fill(
              child: AlbumPlaybackView(
                album: activeAlbumPlayback.album,
                tracks: activeAlbumPlayback.tracks,
                currentTrack: model.activeAlbumTrack,
                playing:
                    model.activeAlbumTrack != null && model.playbackPlaying,
                nowPlayingAlbum: model.dockNowPlayingAlbumTarget == null
                    ? null
                    : _albumNowPlayingChip(model.dockNowPlayingAlbumTarget!),
                onClose: actions.onCloseAlbumPlayback,
                onPrevious: actions.onAlbumPrevious!,
                onToggle: actions.onAlbumToggle!,
                onNext: actions.onAlbumNext!,
                onOpenNowPlayingAlbum: actions.onOpenNowPlayingAlbum,
                canSwitchPreviousAlbum: model.canSwitchPreviousAlbum,
                canSwitchNextAlbum: model.canSwitchNextAlbum,
                onSwitchPreviousAlbum: actions.onSwitchPreviousAlbum,
                onSwitchNextAlbum: actions.onSwitchNextAlbum,
                favoriteTrackPaths: model.favoriteTrackPaths,
                onPlayTrack: actions.onPlayAlbumTrack,
                onToggleFavoriteTrack: actions.onToggleFavoriteTrack,
              ),
            ),
          if (activeAlbumPlayback == null &&
              activePlaylistOverlayFolder != null)
            Positioned.fill(
              child: PlaylistPlaybackView(
                folder: activePlaylistOverlayFolder,
                tracks: model.activePlaylistOverlayTracks,
                trackCoverCache: model.trackCoverCache,
                currentTrack: model.activePlaylistTrack,
                playbackActive: model.playlistOverlayPlaybackActive,
                playing:
                    model.playlistOverlayPlaybackActive &&
                    model.playbackPlaying,
                onClose: actions.onClosePlaylistPlayback,
                onPlayAll: actions.onPlaylistPlayAll,
                onShuffleAll: actions.onPlaylistShuffleAll,
                onPrevious: actions.onPlaylistPrevious,
                onTogglePlayback: actions.onPlaylistTogglePlayback,
                onNext: actions.onPlaylistNext,
                favoriteTrackPaths: model.favoriteTrackPaths,
                onPlayTrack: actions.onPlayPlaylistTrack,
                onToggleFavoriteTrack: actions.onToggleFavoriteTrack,
                canSwitchPreviousPlaylist: model.canSwitchPreviousPlaylist,
                canSwitchNextPlaylist: model.canSwitchNextPlaylist,
                onSwitchPreviousPlaylist: actions.onSwitchPreviousPlaylist,
                onSwitchNextPlaylist: actions.onSwitchNextPlaylist,
                onOpenNowPlaying: actions.onOpenNowPlayingFromPlaylist,
              ),
            ),
          if (activeAlbumPlayback == null &&
              activePlaylistOverlayFolder == null &&
              model.favoritesOverlayOpen)
            Positioned.fill(
              child: FavoritesPlaybackView(
                tracks: model.favoriteTracks,
                trackCoverCache: model.trackCoverCache,
                currentTrack: model.favoritesPlaybackActive
                    ? model.playbackCurrentTrack
                    : null,
                playbackActive: model.favoritesPlaybackActive,
                playing: model.favoritesPlaybackActive && model.playbackPlaying,
                onClose: actions.onCloseFavoritesPlayback,
                onOpenNowPlaying: actions.onOpenNowPlayingFromFavorites,
                onPlayAll: actions.onFavoritePlayAll,
                onShuffleAll: actions.onFavoriteShuffleAll,
                onPrevious: actions.onFavoritePrevious,
                onTogglePlayback: actions.onFavoriteTogglePlayback,
                onNext: actions.onFavoriteNext,
                onPlayTrack: actions.onPlayFavoriteTrack,
                onToggleFavorite: actions.onToggleFavoriteTrack,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent({required bool overlayOpen}) {
    if (model.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final albumsActive = !overlayOpen && model.browseView == LibraryView.albums;
    final playlistsActive =
        !overlayOpen && model.browseView == LibraryView.playlists;
    final favoritesActive =
        !overlayOpen && model.browseView == LibraryView.favorites;
    return IndexedStack(
      index: switch (model.browseView) {
        LibraryView.albums => 0,
        LibraryView.playlists => 1,
        LibraryView.favorites => 2,
      },
      children: [
        _LibraryContentSlot(
          active: albumsActive,
          child: AlbumGrid(
            key: const PageStorageKey<String>('library-content-albums'),
            albums: model.albums,
            tracksByFolder: model.tracksByFolder,
            scrollController: model.albumGridScrollController,
            keyboardShortcutsEnabled: albumsActive,
            onOpen: actions.onOpenAlbum,
          ),
        ),
        _LibraryContentSlot(
          active: playlistsActive,
          child: PlaylistList(
            key: const PageStorageKey<String>('library-content-playlists'),
            folders: model.playlistFolders,
            tracksByFolder: model.tracksByFolder,
            trackCoverCache: model.trackCoverCache,
            scrollController: model.playlistListScrollController,
            keyboardShortcutsEnabled: playlistsActive,
            onOpen: actions.onOpenPlaylistPlayback,
          ),
        ),
        _LibraryContentSlot(
          active: favoritesActive,
          child: FavoriteBrowseList(
            key: const PageStorageKey<String>('library-content-favorites'),
            tracks: model.favoriteTracks,
            trackCoverCache: model.trackCoverCache,
            currentTrack: model.favoritesPlaybackActive
                ? model.playbackCurrentTrack
                : null,
            playing: model.favoritesPlaybackActive && model.playbackPlaying,
            scrollController: model.favoritesListScrollController,
            onPlayTrack: actions.onPlayFavoriteTrack,
            onToggleFavorite: actions.onToggleFavoriteTrack,
          ),
        ),
      ],
    );
  }
}

AlbumPlaybackNowPlaying _albumNowPlayingChip(LibraryNowPlayingTarget target) {
  final sidebar = target.sidebarItem;
  final collage = sidebar.playlistCoverArtPaths
      .whereType<String>()
      .where((path) => path.isNotEmpty)
      .toList(growable: false);
  return AlbumPlaybackNowPlaying(
    coverArtPath:
        target.album?.coverArtPath ?? (collage.isEmpty ? null : collage.first),
    collagePaths: collage,
    playing: sidebar.playing,
  );
}

class _LibraryContentSlot extends StatelessWidget {
  const _LibraryContentSlot({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TickerMode(
      enabled: active,
      child: IgnorePointer(
        ignoring: !active,
        child: ExcludeFocus(excluding: !active, child: child),
      ),
    );
  }
}
