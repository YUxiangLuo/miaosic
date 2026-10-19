import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'artwork_resolver.dart';
import 'collection_playback_dock.dart';
import 'collection_playback_style.dart';
import 'collection_track_table.dart';
import 'library_widgets.dart';
import 'models.dart';

const _favoritesPlaybackSpaceActivator = SingleActivator(
  LogicalKeyboardKey.space,
  includeRepeats: false,
);

class FavoritesPlaybackView extends StatelessWidget {
  const FavoritesPlaybackView({
    super.key,
    required this.tracks,
    required this.trackCoverCache,
    required this.currentTrack,
    required this.playbackActive,
    required this.playing,
    required this.onClose,
    this.onOpenNowPlaying,
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
  final VoidCallback onClose;
  final VoidCallback? onOpenNowPlaying;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffleAll;
  final VoidCallback? onPrevious;
  final VoidCallback? onTogglePlayback;
  final VoidCallback? onNext;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track> onToggleFavorite;

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      onClose();
      return KeyEventResult.handled;
    }
    if (_favoritesPlaybackSpaceActivator.accepts(
      event,
      HardwareKeyboard.instance,
    )) {
      final action = playbackActive ? onTogglePlayback : onPlayAll;
      if (action != null) {
        action();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final coverPaths = _favoriteCoverPaths();
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Material(
        color: Colors.black,
        child: LayoutBuilder(
          builder: (context, viewportConstraints) {
            final dockHeight = math.max(
              viewportConstraints.maxHeight * collectionDockHeightFraction,
              collectionDockMinHeight,
            );
            return Stack(
              children: [
                Positioned.fill(
                  child: _FavoritesPlaybackBackground(
                    coverPath: _stageCoverPath(coverPaths),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(28, 24, 28, dockHeight + 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton.filledTonal(
                              tooltip: 'Back to library',
                              onPressed: onClose,
                              icon: const Icon(Icons.keyboard_arrow_down),
                            ),
                            if (onOpenNowPlaying != null) ...[
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                tooltip: 'Back to now playing',
                                onPressed: onOpenNowPlaying,
                                icon: const Icon(Icons.graphic_eq),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 18),
                        Expanded(
                          child: tracks.isEmpty
                              ? const CollectionPlaybackEmptyState(
                                  icon: Icons.favorite_border,
                                  label: 'No favorite tracks yet',
                                )
                              : _FavoritesPlaybackBody(
                                  coverPaths: coverPaths,
                                  tracks: tracks,
                                  trackCoverCache: trackCoverCache,
                                  currentTrack: currentTrack,
                                  playing: playing,
                                  playbackActive: playbackActive,
                                  onPlayTrack: onPlayTrack,
                                  onToggleFavorite: onToggleFavorite,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: dockHeight,
                  child: CollectionPlaybackDock(
                    identity: _DockFavoritesIdentity(
                      coverPaths: coverPaths,
                      trackCount: tracks.length,
                    ),
                    shuffleTooltip: 'Shuffle favorites',
                    trackCoverCache: trackCoverCache,
                    currentTrack: currentTrack,
                    playbackActive: playbackActive,
                    playing: playing,
                    onPlayAll: onPlayAll,
                    onShuffleAll: onShuffleAll,
                    onPrevious: onPrevious,
                    onTogglePlayback: onTogglePlayback,
                    onNext: onNext,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<String> _favoriteCoverPaths() {
    final paths = <String>[];
    for (final track in tracks) {
      final path = resolveTrackArtwork(track, trackCoverCache);
      if (path != null && path.isNotEmpty && !paths.contains(path)) {
        paths.add(path);
      }
      if (paths.length >= 4) {
        return paths;
      }
    }
    return paths;
  }

  String? _stageCoverPath(List<String> coverPaths) {
    if (currentTrack != null) {
      final current = resolveTrackArtwork(currentTrack!, trackCoverCache);
      if (current != null && current.isNotEmpty) {
        return current;
      }
    }
    if (coverPaths.isNotEmpty) {
      return coverPaths.first;
    }
    return null;
  }
}

class _FavoritesPlaybackBackground extends StatelessWidget {
  const _FavoritesPlaybackBackground({required this.coverPath});

  final String? coverPath;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xff050706)),
        if (coverPath != null)
          RepaintBoundary(
            key: ValueKey(coverPath),
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
              child: Transform.scale(
                scale: 1.08,
                child: Image.file(
                  File(coverPath!),
                  fit: BoxFit.cover,
                  cacheWidth: 256,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66000000), Color(0xd9000000)],
            ),
          ),
        ),
        const ColoredBox(color: Color(0x47000000)),
      ],
    );
  }
}

class _FavoritesPlaybackBody extends StatelessWidget {
  const _FavoritesPlaybackBody({
    required this.coverPaths,
    required this.tracks,
    required this.trackCoverCache,
    required this.currentTrack,
    required this.playing,
    required this.playbackActive,
    required this.onPlayTrack,
    required this.onToggleFavorite,
  });

  final List<String> coverPaths;
  final List<Track> tracks;
  final Map<String, String?> trackCoverCache;
  final Track? currentTrack;
  final bool playing;
  final bool playbackActive;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 840;
        if (compact) {
          final headerMaxHeight = math.max(64.0, constraints.maxHeight * 0.40);
          final headerGap = constraints.maxHeight < 280 ? 10.0 : 18.0;
          return Column(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: headerMaxHeight),
                child: _FavoritesCompactHeader(
                  coverPaths: coverPaths,
                  trackCount: tracks.length,
                  currentTrack: playbackActive ? currentTrack : null,
                  playing: playing,
                ),
              ),
              SizedBox(height: headerGap),
              Expanded(
                child: CollectionTrackTable(
                  tracks: tracks,
                  trackCoverCache: trackCoverCache,
                  currentTrack: currentTrack,
                  playing: playing,
                  onPlayTrack: onPlayTrack,
                  favoriteTrackPaths: tracks.map((track) => track.path).toSet(),
                  onToggleFavoriteTrack: onToggleFavorite,
                ),
              ),
            ],
          );
        }

        final panelWidth = math.min(
          360.0,
          math.max(280.0, constraints.maxWidth * 0.32),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: panelWidth,
              child: _FavoritesHeroStage(
                coverPaths: coverPaths,
                trackCount: tracks.length,
                currentTrack: playbackActive ? currentTrack : null,
                playing: playing,
              ),
            ),
            const SizedBox(width: 26),
            Expanded(
              child: CollectionTrackTable(
                tracks: tracks,
                trackCoverCache: trackCoverCache,
                currentTrack: currentTrack,
                playing: playing,
                onPlayTrack: onPlayTrack,
                favoriteTrackPaths: tracks.map((track) => track.path).toSet(),
                onToggleFavoriteTrack: onToggleFavorite,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FavoritesHeroStage extends StatelessWidget {
  const _FavoritesHeroStage({
    required this.coverPaths,
    required this.trackCount,
    required this.currentTrack,
    required this.playing,
  });

  final List<String> coverPaths;
  final int trackCount;
  final Track? currentTrack;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showNowPlaying =
            currentTrack != null && constraints.maxHeight >= 200;
        final tight = constraints.maxHeight < 280;
        final gap = tight ? 10.0 : 22.0;
        final coverSize = math.min(
          constraints.maxWidth,
          math.max(72.0, constraints.maxHeight * 0.52),
        );
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: SizedBox(
            width: constraints.maxWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PlaylistCoverCollage(
                  paths: coverPaths,
                  size: coverSize,
                  radius: 14,
                  icon: Icons.favorite,
                ),
                SizedBox(height: gap),
                _FavoritesStageIdentity(
                  trackCount: trackCount,
                  currentTrack: showNowPlaying ? currentTrack : null,
                  playing: playing,
                  compact: false,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FavoritesCompactHeader extends StatelessWidget {
  const _FavoritesCompactHeader({
    required this.coverPaths,
    required this.trackCount,
    required this.currentTrack,
    required this.playing,
  });

  final List<String> coverPaths;
  final int trackCount;
  final Track? currentTrack;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        final coverSize = maxH.isFinite
            ? math.min(120.0, math.max(56.0, maxH))
            : 120.0;
        final showNowPlaying =
            currentTrack != null && (!maxH.isFinite || maxH >= 124);
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: constraints.maxWidth,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                PlaylistCoverCollage(
                  paths: coverPaths,
                  size: coverSize,
                  radius: 12,
                  icon: Icons.favorite,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: _FavoritesStageIdentity(
                    trackCount: trackCount,
                    currentTrack: showNowPlaying ? currentTrack : null,
                    playing: playing,
                    compact: true,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FavoritesStageIdentity extends StatelessWidget {
  const _FavoritesStageIdentity({
    required this.trackCount,
    required this.currentTrack,
    required this.playing,
    required this.compact,
  });

  final int trackCount;
  final Track? currentTrack;
  final bool playing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final nowPlaying = currentTrack;
    return Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Favorites',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: compact ? TextAlign.left : TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$trackCount favorite ${trackCount == 1 ? 'track' : 'tracks'}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.58),
            fontWeight: FontWeight.w700,
          ),
        ),
        if (nowPlaying != null) ...[
          const SizedBox(height: 16),
          Text(
            playing ? 'NOW PLAYING' : 'PAUSED',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: collectionControlAccent,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            nowPlaying.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: compact ? TextAlign.left : TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            nowPlaying.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: compact ? TextAlign.left : TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.62),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _DockFavoritesIdentity extends StatelessWidget {
  const _DockFavoritesIdentity({
    required this.coverPaths,
    required this.trackCount,
  });

  final List<String> coverPaths;
  final int trackCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PlaylistCoverCollage(
          paths: coverPaths,
          size: 64,
          radius: 8,
          icon: Icons.favorite,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Favorites',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$trackCount favorite ${trackCount == 1 ? 'track' : 'tracks'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
