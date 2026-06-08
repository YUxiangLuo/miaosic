import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'library_widgets.dart';
import 'models.dart';

class AlbumGrid extends StatelessWidget {
  const AlbumGrid({
    super.key,
    required this.albums,
    required this.tracksByFolder,
    required this.onOpen,
  });

  final List<AlbumSummary> albums;
  final Map<String, List<Track>> tracksByFolder;
  final void Function(AlbumSummary album, List<Track> tracks) onOpen;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return const EmptyState(message: 'No album folders detected');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const gridPadding = 26.0;
        const crossAxisSpacing = 30.0;
        const mainAxisSpacing = 36.0;
        final columns = math.min(6, math.max(2, (width / 220).floor()));
        final usableWidth =
            width - (gridPadding * 2) - (crossAxisSpacing * (columns - 1));
        final tileWidth = math.max(0.0, usableWidth / columns);
        return GridView.builder(
          padding: const EdgeInsets.all(gridPadding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: mainAxisSpacing,
            mainAxisExtent: tileWidth,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            final tracks = tracksByFolder[album.folderPath] ?? const <Track>[];
            return _AlbumTile(
              album: album,
              onTap: tracks.isEmpty ? null : () => onOpen(album, tracks),
            );
          },
        );
      },
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({required this.album, required this.onTap});

  final AlbumSummary album;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Artwork(
        path: album.coverArtPath,
        size: double.infinity,
        icon: Icons.album,
        radius: 8,
      ),
    );
  }
}
