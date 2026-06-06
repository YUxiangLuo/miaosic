part of 'main.dart';

class _PlaylistTrackList extends StatelessWidget {
  const _PlaylistTrackList({
    required this.tracks,
    required this.currentPath,
    required this.onPlay,
    this.trackCoverCache = const {},
    this.showArtwork = true,
  });

  final List<Track> tracks;
  final String? currentPath;
  final ValueChanged<Track> onPlay;
  final Map<String, String?> trackCoverCache;
  final bool showArtwork;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const _EmptyState(message: 'No tracks found');
    }

    final leftPadding = showArtwork ? 18.0 : 60.0;
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(leftPadding, 14, 18, 18),
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
          showArtwork: showArtwork,
          artworkPath: showArtwork
              ? trackCoverPath ?? track.coverArtPath
              : trackCoverPath,
          onTap: () => onPlay(track),
        );
      },
    );
  }
}

class _LibraryTrackList extends StatelessWidget {
  const _LibraryTrackList({
    required this.tracks,
    required this.currentPath,
    required this.trackCoverCache,
    required this.onPlay,
  });

  final List<Track> tracks;
  final String? currentPath;
  final Map<String, String?> trackCoverCache;
  final ValueChanged<Track> onPlay;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const _EmptyState(message: 'No tracks found');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 18.0;
        const spacing = 10.0;
        const cardHeight = 76.0;
        final availableWidth = math.max(
          1.0,
          constraints.maxWidth - horizontalPadding * 2,
        );
        final columns = math.max(1, (availableWidth / 320).floor());
        final cardWidth = (availableWidth - spacing * (columns - 1)) / columns;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            12,
            horizontalPadding,
            18,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: cardWidth / cardHeight,
          ),
          itemCount: tracks.length,
          itemBuilder: (context, index) {
            final track = tracks[index];
            return _LibraryTrackTile(
              track: track,
              artworkPath: trackCoverCache[track.path] ?? track.coverArtPath,
              selected: track.path == currentPath,
              onTap: () => onPlay(track),
            );
          },
        );
      },
    );
  }
}

class _LibraryTrackTile extends StatelessWidget {
  const _LibraryTrackTile({
    required this.track,
    required this.artworkPath,
    required this.selected,
    required this.onTap,
  });

  final Track track;
  final String? artworkPath;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.65)
              : scheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            _Artwork(path: artworkPath, size: 56, icon: Icons.music_note),
            const SizedBox(width: 10),
            Expanded(
              child: _LibraryTrackText(
                title: track.title,
                artist: track.artist,
                selected: selected,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryTrackText extends StatelessWidget {
  const _LibraryTrackText({
    required this.title,
    required this.artist,
    required this.selected,
  });

  final String title;
  final String artist;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _PlaylistTrackRow extends StatelessWidget {
  const _PlaylistTrackRow({
    required this.index,
    required this.track,
    required this.selected,
    required this.showArtwork,
    required this.artworkPath,
    required this.onTap,
  });

  final int index;
  final Track track;
  final bool selected;
  final bool showArtwork;
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
            if (showArtwork || artworkPath != null) ...[
              _Artwork(path: artworkPath, size: 50, icon: Icons.music_note),
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
              child: _TwoLineText(
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
                _formatDurationMs(track.durationMs),
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
