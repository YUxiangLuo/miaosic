import 'package:flutter/material.dart';

import 'library_diff.dart';
import 'models.dart';

enum LibraryView {
  albums('Albums', Icons.album),
  playlists('Playlists', Icons.queue_music),
  favorites('Favorites', Icons.favorite);

  const LibraryView(this.label, this.icon);

  final String label;
  final IconData icon;
}

enum RescanPhase {
  idle,
  loadingDatabase,
  scanning,
  diffing,
  ready,
  applying,
  done,
  error;

  bool get isBusy {
    return this == RescanPhase.loadingDatabase ||
        this == RescanPhase.scanning ||
        this == RescanPhase.diffing ||
        this == RescanPhase.applying;
  }
}

enum LibraryScanMode { direct, diff }

class RescanUiState {
  const RescanUiState({
    this.mode = LibraryScanMode.diff,
    required this.phase,
    this.message = '',
    this.progress,
    this.diff,
    this.error,
  });

  static const _unset = Object();

  final LibraryScanMode mode;
  final RescanPhase phase;
  final String message;
  final ScanProgress? progress;
  final LibraryDiff? diff;
  final String? error;

  RescanUiState copyWith({
    LibraryScanMode? mode,
    RescanPhase? phase,
    String? message,
    Object? progress = _unset,
    Object? diff = _unset,
    Object? error = _unset,
  }) {
    return RescanUiState(
      mode: mode ?? this.mode,
      phase: phase ?? this.phase,
      message: message ?? this.message,
      progress: identical(progress, _unset)
          ? this.progress
          : progress as ScanProgress?,
      diff: identical(diff, _unset) ? this.diff : diff as LibraryDiff?,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}
