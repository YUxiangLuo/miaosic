import 'package:flutter/material.dart';

import 'library_diff.dart';
import 'models.dart';

enum LibraryView {
  albums('Albums', Icons.album),
  playlists('Playlists', Icons.queue_music);

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

class RescanUiState {
  const RescanUiState({
    required this.phase,
    this.message = '',
    this.progress,
    this.diff,
    this.error,
  });

  final RescanPhase phase;
  final String message;
  final ScanProgress? progress;
  final LibraryDiff? diff;
  final String? error;

  RescanUiState copyWith({
    RescanPhase? phase,
    String? message,
    ScanProgress? progress,
    LibraryDiff? diff,
    String? error,
  }) {
    return RescanUiState(
      phase: phase ?? this.phase,
      message: message ?? this.message,
      progress: progress,
      diff: diff ?? this.diff,
      error: error,
    );
  }
}
