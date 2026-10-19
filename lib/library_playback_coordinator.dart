import 'dart:async';

import 'app_diagnostics.dart';
import 'library_controller.dart';
import 'models.dart';
import 'playback_controller.dart';
import 'playback_session.dart';

/// Connects catalog changes and persistence to the player's single session.
class LibraryPlaybackCoordinator {
  LibraryPlaybackCoordinator({
    required this.library,
    required this.playback,
    this.onSaveError,
  }) {
    library.addListener(_reconcileLibrary);
    playback.addListener(saveCurrentState);
  }

  final LibraryController library;
  final PlaybackController playback;
  final void Function(Object error)? onSaveError;
  List<Track>? _knownTracks;
  Set<String>? _knownFavorites;
  bool _restoreAttempted = false;
  bool _disposed = false;
  bool _saving = false;
  LastPlaybackState? _pendingState;
  String? _lastPersistedKey;
  Future<void> _favoriteMutation = Future<void>.value();

  void _reconcileLibrary() {
    if (_disposed || library.loading) return;
    if (identical(_knownTracks, library.tracks) &&
        identical(_knownFavorites, library.favoriteTrackPaths)) {
      return;
    }
    _knownTracks = library.tracks;
    _knownFavorites = library.favoriteTrackPaths;
    unawaited(
      playback.reconcileLibrary(
        trackPaths: library.tracks.map((track) => track.path).toSet(),
        favoritePaths: library.favoriteTrackPaths,
      ),
    );
  }

  Future<void> play({
    required LastPlaybackKind kind,
    String folderPath = '',
    required List<Track> tracks,
    Track? startTrack,
    bool shuffled = false,
  }) async {
    if (_disposed || tracks.isEmpty) return;
    _restoreAttempted = true;
    await playback.playSession(
      PlaybackSession.start(
        kind: kind,
        folderPath: folderPath,
        tracks: tracks,
        startTrack: startTrack,
        shuffled: shuffled,
      ),
    );
  }

  Future<PlaybackSession?> restoreIfReady() async {
    if (_disposed ||
        _restoreAttempted ||
        !library.canRestoreLastPlayback ||
        library.tracks.isEmpty) {
      return null;
    }
    _restoreAttempted = true;
    final saved = library.lastPlayback;
    if (saved == null) return null;
    final sourceExists = switch (saved.kind) {
      LastPlaybackKind.album => library.albums.any(
        (album) => album.folderPath == saved.folderPath,
      ),
      LastPlaybackKind.playlist => library.playlistFolders.any(
        (folder) => folder.path == saved.folderPath,
      ),
      LastPlaybackKind.favorites => true,
    };
    if (!sourceExists) return null;
    final tracks = saved.kind == LastPlaybackKind.favorites
        ? library.favoriteTracks
        : library.tracksByFolder[saved.folderPath] ?? const <Track>[];
    if (tracks.isEmpty) return null;
    final session = PlaybackSession.start(
      kind: saved.kind,
      folderPath: saved.folderPath,
      tracks: tracks,
      startTrack: tracks
          .where((track) => track.path == saved.trackPath)
          .firstOrNull,
      shuffled: saved.shuffled,
    );
    // Launch resumes playback even when the saved state was paused.
    await playback.playSession(session);
    return !_disposed && identical(playback.session, session) ? session : null;
  }

  Future<void> toggleFavorite(Track track) {
    final result = _favoriteMutation.then((_) async {
      if (!_disposed) await library.toggleFavoriteTrack(track);
    });
    // Keep the serialization tail usable after failure; callers receive result.
    _favoriteMutation = result.catchError((Object _) {});
    return result;
  }

  void saveCurrentState() {
    if (_disposed) return;
    final state = playback.session?.savedState(playing: playback.playing);
    if (state == null) return;
    _pendingState = state;
    if (!_saving) unawaited(_persistPendingState());
  }

  Future<void> _persistPendingState() async {
    _saving = true;
    try {
      while (!_disposed && _pendingState != null) {
        final state = _pendingState!;
        _pendingState = null;
        final key = lastPlaybackStateKey(state);
        if (key == _lastPersistedKey) continue;
        try {
          await library.saveLastPlayback(state);
          _lastPersistedKey = key;
        } catch (error, stackTrace) {
          reportAppError('save playback', error, stackTrace);
          if (!_disposed) onSaveError?.call(error);
        }
      }
    } finally {
      _saving = false;
    }
  }

  void dispose() {
    _disposed = true;
    library.removeListener(_reconcileLibrary);
    playback.removeListener(saveCurrentState);
  }
}
