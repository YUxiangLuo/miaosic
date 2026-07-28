import 'package:flutter/material.dart';

import 'album_playback_view.dart';
import 'album_views.dart';
import 'favorite_views.dart';
import 'library_screen_models.dart';
import 'library_sidebar.dart';
import 'library_types.dart';
import 'models.dart';
import 'playlist_playback_view.dart';
import 'playlist_views.dart';

class LibraryScreenViewModel {
  const LibraryScreenViewModel({
    required this.selectedView,
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
    required this.playbackCurrentTrack,
    required this.playbackPlaying,
    required this.albumGridScrollController,
    required this.playlistListScrollController,
    required this.canSwitchPreviousAlbum,
    required this.canSwitchNextAlbum,
  });

  final LibraryView selectedView;
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
  final LibraryActiveAlbumPlayback? activeAlbumPlayback;
  final Track? activeAlbumTrack;
  final LibraryNowPlayingTarget? dockNowPlayingAlbumTarget;
  final FolderSummary? activePlaylistOverlayFolder;
  final List<Track> activePlaylistOverlayTracks;
  final Track? activePlaylistTrack;
  final bool playlistOverlayPlaybackActive;
  final Track? playbackCurrentTrack;
  final bool playbackPlaying;
  final ScrollController albumGridScrollController;
  final ScrollController playlistListScrollController;
  final bool canSwitchPreviousAlbum;
  final bool canSwitchNextAlbum;
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
    required this.onClosePlaylistPlayback,
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
  final VoidCallback onClosePlaylistPlayback;
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
    return Scaffold(
      body: Stack(
        children: [
          ExcludeFocus(
            excluding:
                activeAlbumPlayback != null ||
                activePlaylistOverlayFolder != null,
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
                Expanded(child: RepaintBoundary(child: _buildContent())),
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
                    : AlbumPlaybackNowPlaying(
                        coverArtPath: model
                            .dockNowPlayingAlbumTarget!
                            .album
                            ?.coverArtPath,
                        playing: model
                            .dockNowPlayingAlbumTarget!
                            .sidebarItem
                            .playing,
                      ),
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
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (model.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return _LibraryContentCache(
      selectedView: model.selectedView,
      albums: model.albums,
      playlistFolders: model.playlistFolders,
      favoriteTracks: model.favoriteTracks,
      favoriteTrackPaths: model.favoriteTrackPaths,
      favoritesPlaybackActive: model.favoritesPlaybackActive,
      tracksByFolder: model.tracksByFolder,
      trackCoverCache: model.trackCoverCache,
      activeAlbumPlayback: model.activeAlbumPlayback,
      activePlaylistOverlayFolder: model.activePlaylistOverlayFolder,
      playbackCurrentTrack: model.playbackCurrentTrack,
      playbackPlaying: model.playbackPlaying,
      albumGridScrollController: model.albumGridScrollController,
      playlistListScrollController: model.playlistListScrollController,
      onOpenAlbum: actions.onOpenAlbum,
      onToggleFavoriteTrack: actions.onToggleFavoriteTrack,
      onFavoritePlayAll: actions.onFavoritePlayAll,
      onFavoriteShuffleAll: actions.onFavoriteShuffleAll,
      onFavoritePrevious: actions.onFavoritePrevious,
      onFavoriteTogglePlayback: actions.onFavoriteTogglePlayback,
      onFavoriteNext: actions.onFavoriteNext,
      onOpenPlaylistPlayback: actions.onOpenPlaylistPlayback,
      onPlayFavoriteTrack: actions.onPlayFavoriteTrack,
    );
  }
}

class _LibraryContentCache extends StatefulWidget {
  const _LibraryContentCache({
    required this.selectedView,
    required this.albums,
    required this.playlistFolders,
    required this.favoriteTracks,
    required this.favoriteTrackPaths,
    required this.favoritesPlaybackActive,
    required this.tracksByFolder,
    required this.trackCoverCache,
    required this.activeAlbumPlayback,
    required this.activePlaylistOverlayFolder,
    required this.playbackCurrentTrack,
    required this.playbackPlaying,
    required this.albumGridScrollController,
    required this.playlistListScrollController,
    required this.onOpenAlbum,
    required this.onToggleFavoriteTrack,
    required this.onFavoritePlayAll,
    required this.onFavoriteShuffleAll,
    required this.onFavoritePrevious,
    required this.onFavoriteTogglePlayback,
    required this.onFavoriteNext,
    required this.onOpenPlaylistPlayback,
    required this.onPlayFavoriteTrack,
  });

  final LibraryView selectedView;
  final List<AlbumSummary> albums;
  final List<FolderSummary> playlistFolders;
  final List<Track> favoriteTracks;
  final Set<String> favoriteTrackPaths;
  final bool favoritesPlaybackActive;
  final Map<String, List<Track>> tracksByFolder;
  final Map<String, String?> trackCoverCache;
  final LibraryActiveAlbumPlayback? activeAlbumPlayback;
  final FolderSummary? activePlaylistOverlayFolder;
  final Track? playbackCurrentTrack;
  final bool playbackPlaying;
  final ScrollController albumGridScrollController;
  final ScrollController playlistListScrollController;
  final void Function(AlbumSummary album, List<Track> tracks) onOpenAlbum;
  final ValueChanged<Track> onToggleFavoriteTrack;
  final VoidCallback? onFavoritePlayAll;
  final VoidCallback? onFavoriteShuffleAll;
  final VoidCallback? onFavoritePrevious;
  final VoidCallback? onFavoriteTogglePlayback;
  final VoidCallback? onFavoriteNext;
  final ValueChanged<FolderSummary> onOpenPlaylistPlayback;
  final ValueChanged<Track> onPlayFavoriteTrack;

  @override
  State<_LibraryContentCache> createState() => _LibraryContentCacheState();
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

class _LibraryContentCacheState extends State<_LibraryContentCache> {
  final Map<LibraryView, Widget> _pages = {};
  final Map<LibraryView, Object> _tokens = {};
  int _activationSerial = 0;

  bool get _keyboardShortcutsEnabled =>
      widget.activeAlbumPlayback == null &&
      widget.activePlaylistOverlayFolder == null;

  @override
  void didUpdateWidget(covariant _LibraryContentCache oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedView != widget.selectedView) {
      _activationSerial += 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureSelectedPageIsFresh();
    return IndexedStack(
      index: LibraryView.values.indexOf(widget.selectedView),
      children: [
        for (final view in LibraryView.values)
          _LibraryContentSlot(
            active: view == widget.selectedView,
            child: _pages[view] ?? const SizedBox.expand(),
          ),
      ],
    );
  }

  void _ensureSelectedPageIsFresh() {
    final view = widget.selectedView;
    final token = _tokenFor(view);
    if (_tokens[view] == token) {
      return;
    }
    _tokens[view] = token;
    _pages[view] = _buildPage(view);
  }

  Object _tokenFor(LibraryView view) {
    return switch (view) {
      LibraryView.albums => (
        widget.albums,
        widget.tracksByFolder,
        widget.albumGridScrollController,
        _keyboardShortcutsEnabled,
        _activationSerial,
      ),
      LibraryView.playlists => (
        widget.playlistFolders,
        widget.tracksByFolder,
        widget.trackCoverCache,
        widget.playlistListScrollController,
        _keyboardShortcutsEnabled,
        _activationSerial,
      ),
      LibraryView.favorites => (
        widget.favoriteTracks,
        widget.trackCoverCache,
        widget.playbackCurrentTrack,
        widget.favoritesPlaybackActive,
        widget.playbackPlaying,
        widget.favoriteTrackPaths,
        _activationSerial,
      ),
    };
  }

  Widget _buildPage(LibraryView view) {
    return switch (view) {
      LibraryView.albums => AlbumGrid(
        key: const PageStorageKey<String>('library-content-albums'),
        albums: widget.albums,
        tracksByFolder: widget.tracksByFolder,
        scrollController: widget.albumGridScrollController,
        keyboardShortcutsEnabled: _keyboardShortcutsEnabled,
        focusRequestToken: _activationSerial,
        onOpen: widget.onOpenAlbum,
      ),
      LibraryView.playlists => PlaylistList(
        key: const PageStorageKey<String>('library-content-playlists'),
        folders: widget.playlistFolders,
        tracksByFolder: widget.tracksByFolder,
        trackCoverCache: widget.trackCoverCache,
        scrollController: widget.playlistListScrollController,
        keyboardShortcutsEnabled: _keyboardShortcutsEnabled,
        focusRequestToken: _activationSerial,
        onOpen: widget.onOpenPlaylistPlayback,
      ),
      LibraryView.favorites => FavoriteTrackList(
        key: const PageStorageKey<String>('library-content-favorites'),
        tracks: widget.favoriteTracks,
        trackCoverCache: widget.trackCoverCache,
        currentTrack: widget.playbackCurrentTrack,
        playbackActive: widget.favoritesPlaybackActive,
        playing: widget.playbackPlaying,
        onPlayAll: widget.onFavoritePlayAll,
        onShuffleAll: widget.onFavoriteShuffleAll,
        onPrevious: widget.onFavoritePrevious,
        onTogglePlayback: widget.onFavoriteTogglePlayback,
        onNext: widget.onFavoriteNext,
        onPlayTrack: widget.onPlayFavoriteTrack,
        onToggleFavorite: widget.onToggleFavoriteTrack,
        focusRequestToken: _activationSerial,
      ),
    };
  }
}
