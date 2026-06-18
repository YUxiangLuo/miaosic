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

class LibraryScreenView extends StatelessWidget {
  const LibraryScreenView({
    super.key,
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
    required this.albumPlaybackActive,
    required this.dockNowPlayingAlbumTarget,
    required this.activePlaylistOverlayFolder,
    required this.activePlaylistOverlayTracks,
    required this.activePlaylistTrack,
    required this.playlistOverlayPlaybackActive,
    required this.playbackCurrentTrack,
    required this.playbackPlaying,
    required this.albumGridScrollController,
    required this.playlistListScrollController,
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
    required this.canSwitchPreviousAlbum,
    required this.canSwitchNextAlbum,
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
  final bool albumPlaybackActive;
  final LibraryNowPlayingTarget? dockNowPlayingAlbumTarget;
  final FolderSummary? activePlaylistOverlayFolder;
  final List<Track> activePlaylistOverlayTracks;
  final Track? activePlaylistTrack;
  final bool playlistOverlayPlaybackActive;
  final Track? playbackCurrentTrack;
  final bool playbackPlaying;
  final ScrollController albumGridScrollController;
  final ScrollController playlistListScrollController;
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
  final bool canSwitchPreviousAlbum;
  final bool canSwitchNextAlbum;
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

  @override
  Widget build(BuildContext context) {
    final activeAlbumPlayback = this.activeAlbumPlayback;
    final activePlaylistOverlayFolder = this.activePlaylistOverlayFolder;
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
                    selected: selectedView,
                    albums: albums.length,
                    playlists: playlistCount,
                    favorites: favoriteCount,
                    nowPlaying: nowPlayingTarget?.sidebarItem,
                    themeMode: themeMode,
                    onOpenLibrary: onOpenLibrary,
                    onToggleThemeMode: onToggleThemeMode,
                    onOpenSettings: onOpenSettings,
                    onOpenNowPlaying: nowPlayingTarget == null
                        ? null
                        : () => onOpenNowPlaying(nowPlayingTarget!),
                    onSelected: onSelectedView,
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
                currentTrack: activeAlbumTrack,
                playing: activeAlbumTrack != null && playbackPlaying,
                nowPlayingAlbum: dockNowPlayingAlbumTarget == null
                    ? null
                    : AlbumPlaybackNowPlaying(
                        coverArtPath:
                            dockNowPlayingAlbumTarget!.album?.coverArtPath,
                        playing: dockNowPlayingAlbumTarget!.sidebarItem.playing,
                      ),
                onClose: onCloseAlbumPlayback,
                onPrevious: onAlbumPrevious!,
                onToggle: onAlbumToggle!,
                onNext: onAlbumNext!,
                onOpenNowPlayingAlbum: onOpenNowPlayingAlbum,
                canSwitchPreviousAlbum: canSwitchPreviousAlbum,
                canSwitchNextAlbum: canSwitchNextAlbum,
                onSwitchPreviousAlbum: onSwitchPreviousAlbum,
                onSwitchNextAlbum: onSwitchNextAlbum,
                favoriteTrackPaths: favoriteTrackPaths,
                onPlayTrack: onPlayAlbumTrack,
                onToggleFavoriteTrack: onToggleFavoriteTrack,
              ),
            ),
          if (activeAlbumPlayback == null &&
              activePlaylistOverlayFolder != null)
            Positioned.fill(
              child: PlaylistPlaybackView(
                folder: activePlaylistOverlayFolder,
                tracks: activePlaylistOverlayTracks,
                trackCoverCache: trackCoverCache,
                currentTrack: activePlaylistTrack,
                playbackActive: playlistOverlayPlaybackActive,
                playing: playlistOverlayPlaybackActive && playbackPlaying,
                onClose: onClosePlaylistPlayback,
                onPlayAll: onPlaylistPlayAll,
                onShuffleAll: onPlaylistShuffleAll,
                onPrevious: onPlaylistPrevious,
                onTogglePlayback: onPlaylistTogglePlayback,
                onNext: onPlaylistNext,
                favoriteTrackPaths: favoriteTrackPaths,
                onPlayTrack: onPlayPlaylistTrack,
                onToggleFavoriteTrack: onToggleFavoriteTrack,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return _LibraryContentCache(
      selectedView: selectedView,
      albums: albums,
      playlistFolders: playlistFolders,
      favoriteTracks: favoriteTracks,
      favoriteTrackPaths: favoriteTrackPaths,
      favoritesPlaybackActive: favoritesPlaybackActive,
      tracksByFolder: tracksByFolder,
      trackCoverCache: trackCoverCache,
      activeAlbumPlayback: activeAlbumPlayback,
      activePlaylistOverlayFolder: activePlaylistOverlayFolder,
      playbackCurrentTrack: playbackCurrentTrack,
      playbackPlaying: playbackPlaying,
      albumGridScrollController: albumGridScrollController,
      playlistListScrollController: playlistListScrollController,
      onOpenAlbum: onOpenAlbum,
      onToggleFavoriteTrack: onToggleFavoriteTrack,
      onFavoritePlayAll: onFavoritePlayAll,
      onFavoriteShuffleAll: onFavoriteShuffleAll,
      onFavoritePrevious: onFavoritePrevious,
      onFavoriteTogglePlayback: onFavoriteTogglePlayback,
      onFavoriteNext: onFavoriteNext,
      onOpenPlaylistPlayback: onOpenPlaylistPlayback,
      onPlayFavoriteTrack: onPlayFavoriteTrack,
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
      ),
    };
  }
}
