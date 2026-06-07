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

class TwoLineText extends StatelessWidget {
  const TwoLineText({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ],
    );
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
