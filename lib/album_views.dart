part of 'main.dart';

class _AlbumGrid extends StatelessWidget {
  const _AlbumGrid({
    required this.albums,
    required this.tracksByFolder,
    required this.onPlay,
  });

  final List<AlbumSummary> albums;
  final Map<String, List<Track>> tracksByFolder;
  final ValueChanged<List<Track>> onPlay;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return const _EmptyState(message: 'No album folders detected');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const gridPadding = 26.0;
        const crossAxisSpacing = 30.0;
        const mainAxisSpacing = 36.0;
        const labelExtent = 78.0;
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
            mainAxisExtent: tileWidth + labelExtent,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            final tracks = tracksByFolder[album.folderPath] ?? const <Track>[];
            return _AlbumTile(
              album: album,
              onTap: tracks.isEmpty ? null : () => onPlay(tracks),
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
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Artwork(
            path: album.coverArtPath,
            size: double.infinity,
            icon: Icons.album,
            radius: 8,
          ),
          const SizedBox(height: 12),
          Text(
            album.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            '${album.albumArtist}${album.year == null ? '' : ' · ${album.year}'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          Text(
            '${album.trackCount} tracks',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
