import 'package:flutter/material.dart';

import 'artwork_resolver.dart';
import 'library_formatters.dart';
import 'library_widgets.dart';
import 'models.dart';

class FavoriteTrackList extends StatelessWidget {
  const FavoriteTrackList({
    super.key,
    required this.tracks,
    required this.trackCoverCache,
    required this.currentTrack,
    required this.playbackActive,
    required this.playing,
    required this.onPlayAll,
    required this.onShuffleAll,
    required this.onPrevious,
    required this.onTogglePlayback,
    required this.onNext,
    required this.onPlayTrack,
    required this.onToggleFavorite,
  });

  final List<Track> tracks;
  final Map<String, String?> trackCoverCache;
  final Track? currentTrack;
  final bool playbackActive;
  final bool playing;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffleAll;
  final VoidCallback? onPrevious;
  final VoidCallback? onTogglePlayback;
  final VoidCallback? onNext;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const EmptyState(message: 'No favorite tracks yet');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final showArtist = constraints.maxWidth >= 600;
        final showAlbum = constraints.maxWidth >= 780;
        final compactHeader = constraints.maxWidth < 780;
        final controls = _FavoritePlaybackControls(
          playbackActive: playbackActive,
          playing: playing,
          onPlayAll: onPlayAll,
          onShuffleAll: onShuffleAll,
          onPrevious: onPrevious,
          onTogglePlayback: onTogglePlayback,
          onNext: onNext,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _FavoriteTitleBlock(trackCount: tracks.length),
                      ),
                      if (!compactHeader) ...[
                        const SizedBox(width: 16),
                        controls,
                      ],
                    ],
                  ),
                  if (compactHeader) ...[const SizedBox(height: 14), controls],
                ],
              ),
            ),
            _FavoriteTableHeader(showArtist: showArtist, showAlbum: showAlbum),
            Expanded(
              child: ListView.separated(
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
                    index: index,
                    track: track,
                    artworkPath: resolveTrackArtwork(track, trackCoverCache),
                    selected: selected,
                    playing: selected && playing,
                    showArtist: showArtist,
                    showAlbum: showAlbum,
                    onTap: () => onPlayTrack(track),
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

class _FavoritePlaybackControls extends StatelessWidget {
  const _FavoritePlaybackControls({
    required this.playbackActive,
    required this.playing,
    required this.onPlayAll,
    required this.onShuffleAll,
    required this.onPrevious,
    required this.onTogglePlayback,
    required this.onNext,
  });

  final bool playbackActive;
  final bool playing;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffleAll;
  final VoidCallback? onPrevious;
  final VoidCallback? onTogglePlayback;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    if (!playbackActive) {
      return _FavoriteControlBar(
        children: [
          _FavoriteControlButton(
            tooltip: 'Play favorites',
            icon: Icons.play_arrow_rounded,
            onPressed: onPlayAll,
            prominent: true,
          ),
          const _FavoriteControlDivider(),
          _FavoriteControlButton(
            tooltip: 'Shuffle favorites',
            icon: Icons.shuffle_rounded,
            onPressed: onShuffleAll,
          ),
        ],
      );
    }

    return _FavoriteControlBar(
      children: [
        _FavoriteControlButton(
          tooltip: 'Previous',
          icon: Icons.skip_previous_rounded,
          onPressed: onPrevious,
        ),
        const _FavoriteControlDivider(),
        _FavoriteControlButton(
          tooltip: playing ? 'Pause' : 'Play',
          icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          onPressed: onTogglePlayback,
          prominent: true,
        ),
        const _FavoriteControlDivider(),
        _FavoriteControlButton(
          tooltip: 'Next',
          icon: Icons.skip_next_rounded,
          onPressed: onNext,
        ),
        const _FavoriteControlDivider(),
        _FavoriteControlButton(
          tooltip: 'Shuffle favorites',
          icon: Icons.shuffle_rounded,
          onPressed: onShuffleAll,
        ),
      ],
    );
  }
}

class _FavoriteControlBar extends StatelessWidget {
  const _FavoriteControlBar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class _FavoriteControlButton extends StatelessWidget {
  const _FavoriteControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.prominent = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(48),
        minimumSize: const Size.square(48),
        maximumSize: const Size.square(48),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: prominent ? scheme.primary : Colors.transparent,
        foregroundColor: prominent ? scheme.onPrimary : scheme.onSurface,
        disabledBackgroundColor: prominent
            ? scheme.onSurface.withValues(alpha: 0.08)
            : Colors.transparent,
        disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.28),
      ),
    );
  }
}

class _FavoriteControlDivider extends StatelessWidget {
  const _FavoriteControlDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
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
          SizedBox(width: 44, child: Text('#', style: style)),
          const SizedBox(width: 52),
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
    required this.index,
    required this.track,
    required this.artworkPath,
    required this.selected,
    required this.playing,
    required this.showArtist,
    required this.showAlbum,
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
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = selected ? scheme.primary : scheme.onSurface;
    final secondary = scheme.onSurfaceVariant;
    final background = selected
        ? scheme.primaryContainer.withValues(alpha: 0.55)
        : Colors.transparent;
    return Material(
      color: background,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Center(
                  child: playing
                      ? Icon(Icons.graphic_eq, size: 18, color: primary)
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
              const SizedBox(width: 16),
              SizedBox(
                width: 68,
                child: Text(
                  formatDurationMs(track.durationMs),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: secondary,
                    fontWeight: FontWeight.w700,
                  ),
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
          ),
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
