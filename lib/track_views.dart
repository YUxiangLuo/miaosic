import 'package:flutter/material.dart';

import 'library_formatters.dart';
import 'library_widgets.dart';
import 'models.dart';

class PlaylistTrackList extends StatelessWidget {
  const PlaylistTrackList({
    super.key,
    required this.tracks,
    required this.currentPath,
    required this.onPlay,
    required this.trackCoverCache,
  });

  final List<Track> tracks;
  final String? currentPath;
  final ValueChanged<Track> onPlay;
  final Map<String, String?> trackCoverCache;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const EmptyState(message: 'No tracks found');
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(60, 14, 18, 18),
      itemCount: tracks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final track = tracks[index];
        final selected = track.path == currentPath;
        final trackCoverPath = trackCoverCache[track.path];
        return _PlaylistTrackRow(
          index: index,
          track: track,
          selected: selected,
          artworkPath: trackCoverPath,
          onTap: () => onPlay(track),
        );
      },
    );
  }
}

class _PlaylistTrackRow extends StatelessWidget {
  const _PlaylistTrackRow({
    required this.index,
    required this.track,
    required this.selected,
    required this.artworkPath,
    required this.onTap,
  });

  final int index;
  final Track track;
  final bool selected;
  final String? artworkPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.65)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if (artworkPath != null) ...[
              Artwork(path: artworkPath, size: 50, icon: Icons.music_note),
              const SizedBox(width: 14),
            ] else ...[
              SizedBox(
                width: 50,
                child: Text(
                  (index + 1).toString().padLeft(2, '0'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              flex: 5,
              child: TwoLineText(
                title: track.title,
                subtitle: track.artist,
                selected: selected,
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                track.album.isEmpty ? track.folderName : track.album,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(
                formatDurationMs(track.durationMs),
                textAlign: TextAlign.right,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
