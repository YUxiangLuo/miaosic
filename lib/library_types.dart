import 'package:flutter/material.dart';

export 'library_scan_state.dart';

enum LibraryView {
  albums('Albums', Icons.album),
  playlists('Playlists', Icons.queue_music),
  favorites('Favorites', Icons.favorite);

  const LibraryView(this.label, this.icon);

  final String label;
  final IconData icon;
}
