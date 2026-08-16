import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'artwork_resolver.dart';
import 'library_formatters.dart';
import 'library_widgets.dart';
import 'models.dart';

const _favoritesPlaybackSpaceActivator = SingleActivator(
  LogicalKeyboardKey.space,
  includeRepeats: false,
);
const _favoritesControlAccent = Color(0xff9ee6d4);
const _favoritesDockRadius = 12.0;
const _favoritesPlaybackDockHeightFraction = 0.18;
const _favoritesPlaybackDockMinHeight = 148.0;

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
              viewportConstraints.maxHeight *
                  _favoritesPlaybackDockHeightFraction,
              _favoritesPlaybackDockMinHeight,
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
                              ? const _FavoritesPlaybackEmptyState()
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
                  child: _FavoritesPlaybackDock(
                    coverPaths: coverPaths,
                    trackCount: tracks.length,
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
                child: _FavoritesPlaybackTable(
                  tracks: tracks,
                  trackCoverCache: trackCoverCache,
                  currentTrack: currentTrack,
                  playing: playing,
                  onPlayTrack: onPlayTrack,
                  onToggleFavorite: onToggleFavorite,
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
              child: _FavoritesPlaybackTable(
                tracks: tracks,
                trackCoverCache: trackCoverCache,
                currentTrack: currentTrack,
                playing: playing,
                onPlayTrack: onPlayTrack,
                onToggleFavorite: onToggleFavorite,
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
              color: _favoritesControlAccent,
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

class _FavoritesPlaybackDock extends StatelessWidget {
  const _FavoritesPlaybackDock({
    required this.coverPaths,
    required this.trackCount,
    required this.trackCoverCache,
    required this.currentTrack,
    required this.playbackActive,
    required this.playing,
    required this.onPlayAll,
    required this.onShuffleAll,
    required this.onPrevious,
    required this.onTogglePlayback,
    required this.onNext,
  });

  final List<String> coverPaths;
  final int trackCount;
  final Map<String, String?> trackCoverCache;
  final Track? currentTrack;
  final bool playbackActive;
  final bool playing;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffleAll;
  final VoidCallback? onPrevious;
  final VoidCallback? onTogglePlayback;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.38),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
            ),
          ),
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final gap = math.min(
                    22.0,
                    math.max(12.0, constraints.maxHeight * 0.12),
                  );
                  final maxPrimaryButtonWidth =
                      (constraints.maxWidth - gap * 4) / 5;
                  final primaryButtonSize = math.max(
                    72.0,
                    [
                      constraints.maxHeight * 0.72,
                      maxPrimaryButtonWidth,
                      108.0,
                    ].reduce(math.min),
                  );
                  final secondaryButtonSize = math.max(
                    56.0,
                    primaryButtonSize * 0.72,
                  );
                  final shuffleButtonSize = math.max(
                    52.0,
                    primaryButtonSize * 0.58,
                  );
                  final controlsWidth =
                      secondaryButtonSize * 2 +
                      primaryButtonSize +
                      shuffleButtonSize +
                      gap * 3;
                  final sideSlotWidth =
                      (constraints.maxWidth - controlsWidth) / 2 - gap;
                  final showIdentity = sideSlotWidth >= 170;
                  final showCurrentTrack =
                      currentTrack != null && sideSlotWidth >= 210;

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      if (showIdentity)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: sideSlotWidth,
                            child: _DockFavoritesIdentity(
                              coverPaths: coverPaths,
                              trackCount: trackCount,
                            ),
                          ),
                        ),
                      _FavoritesPlaybackControls(
                        playbackActive: playbackActive,
                        playing: playing,
                        onPlayAll: onPlayAll,
                        onShuffleAll: onShuffleAll,
                        onPrevious: onPrevious,
                        onTogglePlayback: onTogglePlayback,
                        onNext: onNext,
                        primaryButtonSize: primaryButtonSize,
                        secondaryButtonSize: secondaryButtonSize,
                        shuffleButtonSize: shuffleButtonSize,
                        gap: gap,
                      ),
                      if (showCurrentTrack)
                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: sideSlotWidth,
                            child: _DockCurrentTrack(
                              track: currentTrack!,
                              artworkPath: resolveTrackArtwork(
                                currentTrack!,
                                trackCoverCache,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
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

class _DockCurrentTrack extends StatelessWidget {
  const _DockCurrentTrack({required this.track, required this.artworkPath});

  final Track track;
  final String? artworkPath;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Artwork(path: artworkPath, size: 58, icon: Icons.music_note),
      ],
    );
  }
}

class _FavoritesPlaybackControls extends StatelessWidget {
  const _FavoritesPlaybackControls({
    required this.playbackActive,
    required this.playing,
    required this.onPlayAll,
    required this.onShuffleAll,
    required this.onPrevious,
    required this.onTogglePlayback,
    required this.onNext,
    required this.primaryButtonSize,
    required this.secondaryButtonSize,
    required this.shuffleButtonSize,
    required this.gap,
  });

  final bool playbackActive;
  final bool playing;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffleAll;
  final VoidCallback? onPrevious;
  final VoidCallback? onTogglePlayback;
  final VoidCallback? onNext;
  final double primaryButtonSize;
  final double secondaryButtonSize;
  final double shuffleButtonSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final playAction = playbackActive ? onTogglePlayback : onPlayAll;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FavoritesDockIconButton(
          tooltip: 'Previous',
          icon: Icons.skip_previous_rounded,
          onPressed: playbackActive ? onPrevious : null,
          size: secondaryButtonSize,
          iconSize: secondaryButtonSize * 0.45,
        ),
        SizedBox(width: gap),
        _FavoritesDockIconButton(
          tooltip: playbackActive && playing ? 'Pause' : 'Play',
          icon: playbackActive && playing
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          onPressed: playAction,
          prominent: true,
          size: primaryButtonSize,
          iconSize: primaryButtonSize * 0.46,
        ),
        SizedBox(width: gap),
        _FavoritesDockIconButton(
          tooltip: 'Next',
          icon: Icons.skip_next_rounded,
          onPressed: playbackActive ? onNext : null,
          size: secondaryButtonSize,
          iconSize: secondaryButtonSize * 0.45,
        ),
        SizedBox(width: gap),
        _FavoritesDockIconButton(
          tooltip: 'Shuffle favorites',
          icon: Icons.shuffle_rounded,
          onPressed: onShuffleAll,
          size: shuffleButtonSize,
          iconSize: shuffleButtonSize * 0.44,
          accent: true,
        ),
      ],
    );
  }
}

class _FavoritesDockIconButton extends StatelessWidget {
  const _FavoritesDockIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.size,
    required this.iconSize,
    this.prominent = false,
    this.accent = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final bool prominent;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = prominent
        ? _favoritesControlAccent
        : accent
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.20);
    final foregroundColor = prominent
        ? const Color(0xff07110f)
        : accent
        ? _favoritesControlAccent
        : Colors.white.withValues(alpha: 0.95);
    return IconButton.filled(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: iconSize,
      style: IconButton.styleFrom(
        fixedSize: Size.square(size),
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_favoritesDockRadius),
        ),
      ),
      icon: Icon(icon),
    );
  }
}

class _FavoritesPlaybackTable extends StatelessWidget {
  const _FavoritesPlaybackTable({
    required this.tracks,
    required this.trackCoverCache,
    required this.currentTrack,
    required this.playing,
    required this.onPlayTrack,
    required this.onToggleFavorite,
  });

  final List<Track> tracks;
  final Map<String, String?> trackCoverCache;
  final Track? currentTrack;
  final bool playing;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track> onToggleFavorite;

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
            _FavoritesTableHeader(
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
                  return _FavoritesTableRow(
                    index: index,
                    track: track,
                    artworkPath: resolveTrackArtwork(track, trackCoverCache),
                    selected: selected,
                    playing: selected && playing,
                    showArtist: showArtist,
                    showAlbum: showAlbum,
                    showDuration: showDuration,
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

class _FavoritesTableHeader extends StatelessWidget {
  const _FavoritesTableHeader({
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

class _FavoritesTableRow extends StatelessWidget {
  const _FavoritesTableRow({
    required this.index,
    required this.track,
    required this.artworkPath,
    required this.selected,
    required this.playing,
    required this.showArtist,
    required this.showAlbum,
    required this.showDuration,
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
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final primary = Colors.white.withValues(alpha: selected ? 1 : 0.82);
    final secondary = Colors.white.withValues(alpha: selected ? 0.82 : 0.52);
    final background = selected
        ? _favoritesControlAccent.withValues(alpha: 0.16)
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
                color: selected ? _favoritesControlAccent : Colors.transparent,
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
                            color: _favoritesControlAccent,
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
                  child: _FavoritesTrackCell(
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
                IconButton(
                  tooltip: 'Remove from favorites',
                  onPressed: onToggleFavorite,
                  icon: const Icon(Icons.favorite),
                  color: Colors.redAccent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoritesTrackCell extends StatelessWidget {
  const _FavoritesTrackCell({
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

class _FavoritesPlaybackEmptyState extends StatelessWidget {
  const _FavoritesPlaybackEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.favorite_border,
            size: 52,
            color: Colors.white.withValues(alpha: 0.34),
          ),
          const SizedBox(height: 12),
          Text(
            'No favorite tracks yet',
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
