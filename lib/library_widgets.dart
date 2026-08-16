import 'dart:io';

import 'package:flutter/material.dart';

class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.path,
    required this.size,
    required this.icon,
    this.radius = 8,
  });

  final String? path;
  final double size;
  final IconData icon;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = _ArtworkPlaceholder(icon: icon, radius: radius);
    final imagePath = path;
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: imagePath == null || imagePath.isEmpty
          ? placeholder
          : Image.file(
              File(imagePath),
              fit: BoxFit.cover,
              cacheWidth: size.isFinite ? (size * 2).round() : 320,
              cacheHeight: size.isFinite ? (size * 2).round() : 320,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );

    if (size.isFinite) {
      return SizedBox.square(dimension: size, child: image);
    }

    return AspectRatio(aspectRatio: 1, child: image);
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder({required this.icon, required this.radius});

  final IconData icon;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, color: scheme.onSurfaceVariant),
    );
  }
}

class PlaylistCoverCollage extends StatelessWidget {
  const PlaylistCoverCollage({
    super.key,
    required this.paths,
    this.size,
    this.radius = 0,
    this.icon = Icons.queue_music,
  });

  final List<String?> paths;
  final double? size;
  final double radius;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cleaned = [
      for (final path in paths)
        if (path != null && path.isNotEmpty) path,
    ].take(4).toList(growable: false);
    final collage = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: cleaned.length <= 1
          ? Artwork(
              path: cleaned.isEmpty ? null : cleaned.first,
              size: double.infinity,
              icon: icon,
              radius: 0,
            )
          : _PlaylistCoverGrid(paths: cleaned, icon: icon),
    );
    if (size == null) {
      return collage;
    }
    return SizedBox.square(dimension: size, child: collage);
  }
}

class _PlaylistCoverGrid extends StatelessWidget {
  const _PlaylistCoverGrid({required this.paths, required this.icon});

  final List<String> paths;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final padded = paths.toList(growable: true);
    while (padded.length < 4) {
      padded.add(paths.last);
    }
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _tile(padded[0])),
              Expanded(child: _tile(padded[1])),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _tile(padded[2])),
              Expanded(child: _tile(padded[3])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(String path) {
    return Artwork(path: path, size: double.infinity, icon: icon, radius: 0);
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(message, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
