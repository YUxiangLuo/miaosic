import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'library_formatters.dart';
import 'models.dart';

class PlayerBar extends StatelessWidget {
  const PlayerBar({
    super.key,
    required this.track,
    required this.coverArtPath,
    required this.playing,
    required this.position,
    required this.duration,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
    required this.onSeek,
  });

  final Track? track;
  final String? coverArtPath;
  final bool playing;
  final Duration position;
  final Duration duration;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final durationMs = math.max(1, duration.inMilliseconds);
    final positionMs = position.inMilliseconds.clamp(0, durationMs).toDouble();
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
          color: scheme.surface,
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Artwork(path: coverArtPath, size: 56, icon: Icons.music_note),
            const SizedBox(width: 14),
            Expanded(
              flex: 3,
              child: TwoLineText(
                title: track?.title ?? 'Nothing playing',
                subtitle: track == null
                    ? 'Select a local track'
                    : '${track!.artist} · ${track!.folderName}',
              ),
            ),
            const SizedBox(width: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Previous',
                  onPressed: track == null ? null : onPrevious,
                  icon: const Icon(Icons.skip_previous),
                ),
                IconButton.filled(
                  tooltip: playing ? 'Pause' : 'Play',
                  onPressed: onToggle,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
                IconButton(
                  tooltip: 'Next',
                  onPressed: track == null ? null : onNext,
                  icon: const Icon(Icons.skip_next),
                ),
              ],
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 5,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: 42, child: Text(formatDuration(position))),
                  Expanded(
                    child: Slider(
                      value: positionMs,
                      max: durationMs.toDouble(),
                      onChanged: track == null
                          ? null
                          : (value) {
                              onSeek(Duration(milliseconds: value.round()));
                            },
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    child: Text(
                      formatDuration(duration),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    this.selected = false,
  });

  final String title;
  final String subtitle;
  final bool selected;

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
          style: TextStyle(
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
          ),
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
