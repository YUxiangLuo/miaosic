import 'package:flutter/material.dart';

import 'artwork_resolver.dart';
import 'collection_playback_style.dart';
import 'library_formatters.dart';
import 'library_widgets.dart';
import 'models.dart';

class CollectionTrackTable extends StatelessWidget {
  const CollectionTrackTable({
    super.key,
    required this.tracks,
    required this.trackCoverCache,
    required this.currentTrack,
    required this.playing,
    required this.favoriteTrackPaths,
    required this.onPlayTrack,
    required this.onToggleFavoriteTrack,
  });

  final List<Track> tracks;
  final Map<String, String?> trackCoverCache;
  final Track? currentTrack;
  final bool playing;
  final Set<String> favoriteTrackPaths;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track>? onToggleFavoriteTrack;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showArtist = constraints.maxWidth >= 520;
        final showAlbum = constraints.maxWidth >= 620;
        final showDuration = constraints.maxWidth >= 400;
        final horizontalPadding = constraints.maxWidth < 420 ? 10.0 : 28.0;
        return Column(
          children: [
            _TableHeader(
              showArtist: showArtist,
              showAlbum: showAlbum,
              showDuration: showDuration,
              horizontalPadding: horizontalPadding,
            ),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  0,
                  horizontalPadding,
                  28,
                ),
                itemCount: tracks.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  final selected = currentTrack?.path == track.path;
                  return _TableRow(
                    index: index,
                    track: track,
                    artworkPath: resolveTrackArtwork(track, trackCoverCache),
                    selected: selected,
                    playing: selected && playing,
                    showArtist: showArtist,
                    showAlbum: showAlbum,
                    showDuration: showDuration,
                    favorite: favoriteTrackPaths.contains(track.path),
                    onTap: () => onPlayTrack(track),
                    onToggleFavorite: onToggleFavoriteTrack == null
                        ? null
                        : () => onToggleFavoriteTrack!(track),
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

class _TableHeader extends StatelessWidget {
  const _TableHeader({
    required this.showArtist,
    required this.showAlbum,
    required this.showDuration,
    required this.horizontalPadding,
  });

  final bool showArtist;
  final bool showAlbum;
  final bool showDuration;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Colors.white.withValues(alpha: 0.46),
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 8),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              '#',
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: style,
            ),
          ),
          const SizedBox(width: 52),
          const SizedBox(width: 14),
          Expanded(
            flex: 5,
            child: Text(
              'TITLE',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (showArtist) ...[
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: Text(
                'ARTIST',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
          if (showAlbum) ...[
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: Text(
                'ALBUM',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
          if (showDuration) ...[
            const SizedBox(width: 16),
            SizedBox(
              width: 68,
              child: Text(
                'TIME',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: style,
              ),
            ),
          ],
          const SizedBox(width: 8),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.index,
    required this.track,
    required this.artworkPath,
    required this.selected,
    required this.playing,
    required this.showArtist,
    required this.showAlbum,
    required this.showDuration,
    required this.favorite,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final int index;
  final Track track;
  final String? artworkPath;
  final bool selected;
  final bool playing;
  final bool showArtist;
  final bool showAlbum;
  final bool showDuration;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final primary = Colors.white.withValues(alpha: selected ? 1 : 0.82);
    final secondary = Colors.white.withValues(alpha: selected ? 0.82 : 0.52);
    final background = selected
        ? collectionControlAccent.withValues(alpha: 0.16)
        : Colors.transparent;
    return Material(
      color: background,
      child: InkWell(
        onTap: onTap,
        hoverColor: Colors.white.withValues(alpha: selected ? 0.08 : 0.06),
        splashColor: Colors.white.withValues(alpha: 0.10),
        highlightColor: Colors.white.withValues(alpha: 0.08),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? collectionControlAccent : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Center(
                    child: playing
                        ? Icon(
                            Icons.graphic_eq,
                            size: 20,
                            color: collectionControlAccent,
                          )
                        : Text(
                            (index + 1).toString().padLeft(2, '0'),
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: secondary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                  ),
                ),
                Artwork(path: artworkPath, size: 42, icon: Icons.music_note),
                const SizedBox(width: 14),
                Expanded(
                  flex: 5,
                  child: _TrackCell(
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
                      style: TextStyle(
                        color: secondary,
                        fontWeight: FontWeight.w600,
                      ),
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
                      style: TextStyle(
                        color: secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (showDuration) ...[
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 68,
                    child: Text(
                      formatDurationMs(track.durationMs),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                if (onToggleFavorite == null)
                  const SizedBox(width: 44)
                else
                  IconButton(
                    tooltip: favorite
                        ? 'Remove from favorites'
                        : 'Add to favorites',
                    onPressed: onToggleFavorite,
                    icon: Icon(
                      favorite ? Icons.favorite : Icons.favorite_border,
                    ),
                    color: favorite ? Colors.redAccent : secondary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackCell extends StatelessWidget {
  const _TrackCell({
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

class CollectionPlaybackEmptyState extends StatelessWidget {
  const CollectionPlaybackEmptyState({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: Colors.white.withValues(alpha: 0.34)),
          const SizedBox(height: 12),
          Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
