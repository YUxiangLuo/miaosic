import 'package:flutter/material.dart';

import 'artwork_resolver.dart';
import 'library_formatters.dart';
import 'library_widgets.dart';
import 'models.dart';

const _favoriteBrowsePlaySlotWidth = 44.0;

class FavoriteBrowseList extends StatelessWidget {
  const FavoriteBrowseList({
    super.key,
    required this.tracks,
    required this.trackCoverCache,
    required this.currentTrack,
    required this.playing,
    required this.onPlayTrack,
    required this.onToggleFavorite,
    this.scrollController,
  });

  final List<Track> tracks;
  final Map<String, String?> trackCoverCache;
  final Track? currentTrack;
  final bool playing;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track> onToggleFavorite;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const EmptyState(message: 'No favorite tracks yet');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final showArtist = constraints.maxWidth >= 600;
        final showAlbum = constraints.maxWidth >= 780;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 14),
              child: _FavoriteTitleBlock(trackCount: tracks.length),
            ),
            _FavoriteTableHeader(showArtist: showArtist, showAlbum: showAlbum),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                itemCount: tracks.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.7),
                ),
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  final selected = currentTrack?.path == track.path;
                  return _FavoriteTrackRow(
                    track: track,
                    artworkPath: resolveTrackArtwork(track, trackCoverCache),
                    selected: selected,
                    playing: selected && playing,
                    showArtist: showArtist,
                    showAlbum: showAlbum,
                    onPlay: () => onPlayTrack(track),
                    onDoubleTap: () => onPlayTrack(track),
                    onToggleFavorite: () => onToggleFavorite(track),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FavoriteTitleBlock extends StatelessWidget {
  const _FavoriteTitleBlock({required this.trackCount});

  final int trackCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Favorites',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          '$trackCount favorite ${trackCount == 1 ? 'track' : 'tracks'}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _FavoriteTableHeader extends StatelessWidget {
  const _FavoriteTableHeader({
    required this.showArtist,
    required this.showAlbum,
  });

  final bool showArtist;
  final bool showAlbum;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
      child: Row(
        children: [
          const SizedBox(width: _favoriteBrowsePlaySlotWidth),
          const SizedBox(width: 42),
          const SizedBox(width: 14),
          Expanded(flex: 5, child: Text('TITLE', style: style)),
          if (showArtist) ...[
            const SizedBox(width: 16),
            Expanded(flex: 3, child: Text('ARTIST', style: style)),
          ],
          if (showAlbum) ...[
            const SizedBox(width: 16),
            Expanded(flex: 3, child: Text('ALBUM', style: style)),
          ],
          const SizedBox(width: 16),
          SizedBox(
            width: 68,
            child: Text('TIME', textAlign: TextAlign.right, style: style),
          ),
          const SizedBox(width: 8),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _FavoriteTrackRow extends StatelessWidget {
  const _FavoriteTrackRow({
    required this.track,
    required this.artworkPath,
    required this.selected,
    required this.playing,
    required this.showArtist,
    required this.showAlbum,
    required this.onPlay,
    required this.onDoubleTap,
    required this.onToggleFavorite,
  });

  final Track track;
  final String? artworkPath;
  final bool selected;
  final bool playing;
  final bool showArtist;
  final bool showAlbum;
  final VoidCallback onPlay;
  final VoidCallback onDoubleTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = selected ? scheme.primary : scheme.onSurface;
    final secondary = scheme.onSurfaceVariant;
    final background = selected
        ? scheme.primaryContainer.withValues(alpha: 0.55)
        : Colors.transparent;
    final details = Row(
      children: [
        Artwork(path: artworkPath, size: 42, icon: Icons.music_note),
        const SizedBox(width: 14),
        Expanded(
          flex: 5,
          child: _FavoriteTrackCell(
            title: track.title,
            subtitle: showArtist ? track.fileName : track.artist,
            titleColor: primary,
            subtitleColor: secondary,
          ),
        ),
        if (showArtist) ...[
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: secondary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
        if (showAlbum) ...[
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Text(
              track.album.isEmpty ? track.folderName : track.album,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: secondary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
        const SizedBox(width: 16),
        SizedBox(
          width: 68,
          child: Text(
            formatDurationMs(track.durationMs),
            textAlign: TextAlign.right,
            style: TextStyle(color: secondary, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Remove from favorites',
          onPressed: onToggleFavorite,
          icon: const Icon(Icons.favorite),
          color: scheme.error,
        ),
      ],
    );
    return Material(
      color: background,
      child: SizedBox(
        height: 58,
        child: Row(
          children: [
            SizedBox(
              width: _favoriteBrowsePlaySlotWidth,
              child: IconButton(
                key: Key('favorite-play-${track.path}'),
                tooltip: 'Play favorite',
                visualDensity: VisualDensity.compact,
                onPressed: onPlay,
                icon: Icon(
                  playing ? Icons.graphic_eq : Icons.play_arrow_rounded,
                ),
                color: primary,
              ),
            ),
            Expanded(
              child: InkWell(onDoubleTap: onDoubleTap, child: details),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoriteTrackCell extends StatelessWidget {
  const _FavoriteTrackCell({
    required this.title,
    required this.subtitle,
    required this.titleColor,
    required this.subtitleColor,
  });

  final String title;
  final String subtitle;
  final Color titleColor;
  final Color subtitleColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: titleColor,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: subtitleColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
