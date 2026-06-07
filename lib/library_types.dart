import 'package:flutter/material.dart';

enum LibraryView {
  tracks('Tracks', Icons.music_note),
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
