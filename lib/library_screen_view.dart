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
                LibrarySidebar(
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
                const VerticalDivider(width: 1),
                Expanded(child: _buildContent()),
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
    return switch (selectedView) {
      LibraryView.albums => AlbumGrid(
        albums: albums,
        tracksByFolder: tracksByFolder,
        scrollController: albumGridScrollController,
        keyboardShortcutsEnabled:
            activeAlbumPlayback == null && activePlaylistOverlayFolder == null,
        onOpen: onOpenAlbum,
      ),
      LibraryView.playlists => PlaylistList(
        folders: playlistFolders,
        tracksByFolder: tracksByFolder,
        trackCoverCache: trackCoverCache,
        scrollController: playlistListScrollController,
        keyboardShortcutsEnabled:
            activeAlbumPlayback == null && activePlaylistOverlayFolder == null,
        onOpen: onOpenPlaylistPlayback,
      ),
      LibraryView.favorites => FavoriteTrackList(
        tracks: favoriteTracks,
        trackCoverCache: trackCoverCache,
        currentTrack: playbackCurrentTrack,
        playbackActive: favoritesPlaybackActive,
        playing: playbackPlaying,
        onPlayAll: onFavoritePlayAll,
        onShuffleAll: onFavoriteShuffleAll,
        onPrevious: onFavoritePrevious,
        onTogglePlayback: onFavoriteTogglePlayback,
        onNext: onFavoriteNext,
        onPlayTrack: onPlayFavoriteTrack,
        onToggleFavorite: onToggleFavoriteTrack,
      ),
    };
  }
}
