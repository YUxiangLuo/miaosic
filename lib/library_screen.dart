import 'dart:async';

import 'package:flutter/material.dart';

import 'library_controller.dart';
import 'library_screen_dialogs.dart';
import 'library_screen_models.dart';
import 'library_screen_selectors.dart';
import 'library_screen_view.dart';
import 'library_types.dart';
import 'models.dart';
import 'playback_controller.dart';

part 'library_screen_actions.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.libraryController,
    this.playbackController,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final LibraryController? libraryController;
  final PlaybackController? playbackController;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final LibraryController _library;
  late final PlaybackController _playback;
  late final bool _ownsLibrary;
  late final bool _ownsPlayback;
  final _scrollMemory = LibraryScrollMemory();

  LibraryActiveAlbumPlayback? _activeAlbumPlayback;
  LibraryActivePlaylistPlayback? _activePlaylistPlayback;
  String? _lastPlaybackPath;
  String? _lastNowPlayingPath;
  String? _lastPersistedPlaybackKey;
  bool _lastPlaybackPlaying = false;
  bool _lastNowPlayingPlaying = false;
  bool _lastPlaybackRestoreAttempted = false;
  bool _lastPlaybackRestoring = false;
  LibraryView _view = LibraryView.albums;
  String? _activePlaylistOverlayPath;
  bool _rescanDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _library = widget.libraryController ?? LibraryController();
    _playback = widget.playbackController ?? PlaybackController();
    _ownsLibrary = widget.libraryController == null;
    _ownsPlayback = widget.playbackController == null;
    _library.addListener(_handleLibraryChanged);
    _playback.addListener(_handlePlaybackChanged);
    unawaited(_library.open());
  }

  @override
  void dispose() {
    _scrollMemory.dispose();
    _library.removeListener(_handleLibraryChanged);
    if (_ownsLibrary) {
      _library.dispose();
    }
    _playback.removeListener(_handlePlaybackChanged);
    if (_ownsPlayback) {
      _playback.dispose();
    }
    super.dispose();
  }

  void _mutate(VoidCallback update) {
    setState(update);
  }

  @override
  Widget build(BuildContext context) {
    final activeAlbumPlayback = _activeAlbumPlayback;
    final activePlaylistOverlayFolder = _activePlaylistOverlayFolder;
    final activePlaylistOverlayTracks = activePlaylistOverlayFolder == null
        ? const <Track>[]
        : _tracksByFolder[activePlaylistOverlayFolder.path] ?? const <Track>[];
    final activePlaylistPlayback = _activePlaylistPlayback;
    final activePlaylistPlaybackTrack = activePlaylistPlayback == null
        ? null
        : _currentTrackForPlaylist(activePlaylistPlayback);
    final playlistOverlayPlaybackActive =
        activePlaylistOverlayFolder != null &&
        activePlaylistPlayback != null &&
        activePlaylistPlayback.folderPath == activePlaylistOverlayFolder.path &&
        activePlaylistPlaybackTrack != null;
    final activePlaylistTrack = playlistOverlayPlaybackActive
        ? activePlaylistPlaybackTrack
        : null;
    final settingsLoaded = _library.settingsLoaded;
    final albumPlaybackActive =
        activeAlbumPlayback != null &&
        _playback.isCurrentQueue(activeAlbumPlayback.tracks);
    final activeAlbumTrack = albumPlaybackActive
        ? _currentTrackForAlbum(activeAlbumPlayback)
        : null;
    final nowPlayingTarget = _nowPlayingTarget;
    final LibraryNowPlayingTarget? dockNowPlayingAlbumTarget;
    if (activeAlbumPlayback != null &&
        nowPlayingTarget != null &&
        nowPlayingTarget.kind == LibraryNowPlayingKind.album &&
        nowPlayingTarget.album?.folderPath !=
            activeAlbumPlayback.album.folderPath) {
      dockNowPlayingAlbumTarget = nowPlayingTarget;
    } else {
      dockNowPlayingAlbumTarget = null;
    }

    return LibraryScreenView(
      selectedView: _view,
      loading: _library.loading,
      albums: _library.albums,
      playlistFolders: _playlistFolders,
      playlistCount: _playlistCount,
      tracksByFolder: _tracksByFolder,
      trackCoverCache: _library.trackCoverCache,
      themeMode: widget.themeMode,
      nowPlayingTarget: nowPlayingTarget,
      activeAlbumPlayback: activeAlbumPlayback,
      activeAlbumTrack: activeAlbumTrack,
      albumPlaybackActive: albumPlaybackActive,
      dockNowPlayingAlbumTarget: dockNowPlayingAlbumTarget,
      activePlaylistOverlayFolder: activePlaylistOverlayFolder,
      activePlaylistOverlayTracks: activePlaylistOverlayTracks,
      activePlaylistTrack: activePlaylistTrack,
      playlistOverlayPlaybackActive: playlistOverlayPlaybackActive,
      playbackPlaying: _playback.playing,
      albumGridScrollController: _scrollMemory.albumGridScrollController,
      playlistListScrollController: _scrollMemory.playlistListScrollController,
      onOpenLibrary: settingsLoaded ? _openRescanModal : null,
      onToggleThemeMode: settingsLoaded ? _handleToggleThemeMode : null,
      onOpenSettings: settingsLoaded ? _openSettingsModal : null,
      onOpenNowPlaying: _openNowPlaying,
      onSelectedView: _selectLibraryView,
      onOpenAlbum: _openAlbumPlayback,
      onCloseAlbumPlayback: _closeAlbumPlayback,
      onAlbumPrevious: activeAlbumPlayback == null
          ? null
          : () => unawaited(_playback.skip(-1, activeAlbumPlayback.tracks)),
      onAlbumToggle: activeAlbumPlayback == null
          ? null
          : () => unawaited(
              albumPlaybackActive
                  ? _playback.togglePlayPause(activeAlbumPlayback.tracks)
                  : _playAlbum(
                      activeAlbumPlayback.album,
                      activeAlbumPlayback.tracks,
                    ),
            ),
      onAlbumNext: activeAlbumPlayback == null
          ? null
          : () => unawaited(_playback.skip(1, activeAlbumPlayback.tracks)),
      onOpenNowPlayingAlbum: dockNowPlayingAlbumTarget == null
          ? null
          : () => _openNowPlaying(dockNowPlayingAlbumTarget!),
      canSwitchPreviousAlbum:
          activeAlbumPlayback != null &&
          _albumPlaybackSwitchTarget(activeAlbumPlayback.album, -1) != null,
      canSwitchNextAlbum:
          activeAlbumPlayback != null &&
          _albumPlaybackSwitchTarget(activeAlbumPlayback.album, 1) != null,
      onSwitchPreviousAlbum: activeAlbumPlayback == null
          ? null
          : () => _switchAlbumPlayback(-1),
      onSwitchNextAlbum: activeAlbumPlayback == null
          ? null
          : () => _switchAlbumPlayback(1),
      onPlayAlbumTrack: (track) {
        final albumPlayback = _activeAlbumPlayback;
        if (albumPlayback == null) {
          return;
        }
        unawaited(
          _playAlbumFrom(albumPlayback.album, albumPlayback.tracks, track),
        );
      },
      onOpenPlaylistPlayback: _openPlaylistPlayback,
      onClosePlaylistPlayback: _closePlaylistPlayback,
      onPlaylistPlayAll:
          activePlaylistOverlayFolder == null ||
              activePlaylistOverlayTracks.isEmpty
          ? null
          : () => unawaited(
              _playPlaylist(
                activePlaylistOverlayFolder,
                activePlaylistOverlayTracks,
              ),
            ),
      onPlaylistShuffleAll:
          activePlaylistOverlayFolder == null ||
              activePlaylistOverlayTracks.isEmpty
          ? null
          : () => unawaited(
              _playPlaylistShuffled(
                activePlaylistOverlayFolder,
                activePlaylistOverlayTracks,
              ),
            ),
      onPlaylistPrevious: playlistOverlayPlaybackActive
          ? () => unawaited(_playback.skip(-1, activePlaylistPlayback.tracks))
          : null,
      onPlaylistTogglePlayback: playlistOverlayPlaybackActive
          ? () => unawaited(
              _playback.togglePlayPause(activePlaylistPlayback.tracks),
            )
          : null,
      onPlaylistNext: playlistOverlayPlaybackActive
          ? () => unawaited(_playback.skip(1, activePlaylistPlayback.tracks))
          : null,
      onPlayPlaylistTrack: (track) {
        final folder = _activePlaylistOverlayFolder;
        if (folder == null) {
          return;
        }
        final tracks = _tracksByFolder[folder.path] ?? const <Track>[];
        unawaited(_playPlaylist(folder, tracks, startTrack: track));
      },
    );
  }
}
