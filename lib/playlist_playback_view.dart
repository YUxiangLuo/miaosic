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

const _playlistPlaybackSpaceActivator = SingleActivator(
  LogicalKeyboardKey.space,
  includeRepeats: false,
);

class PlaylistPlaybackView extends StatelessWidget {
  const PlaylistPlaybackView({
    super.key,
    required this.folder,
    required this.tracks,
    required this.trackCoverCache,
    required this.currentTrack,
    required this.playbackActive,
    required this.playing,
    required this.onClose,
    required this.onPlayAll,
    required this.onShuffleAll,
    required this.onPrevious,
    required this.onTogglePlayback,
    required this.onNext,
    this.favoriteTrackPaths = const {},
    required this.onPlayTrack,
    this.onToggleFavoriteTrack,
    this.canSwitchPreviousPlaylist = false,
    this.canSwitchNextPlaylist = false,
    this.onSwitchPreviousPlaylist,
    this.onSwitchNextPlaylist,
    this.onOpenNowPlaying,
  });

  final FolderSummary folder;
  final List<Track> tracks;
  final Map<String, String?> trackCoverCache;
  final Track? currentTrack;
  final bool playbackActive;
  final bool playing;
  final VoidCallback onClose;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffleAll;
  final VoidCallback? onPrevious;
  final VoidCallback? onTogglePlayback;
  final VoidCallback? onNext;
  final Set<String> favoriteTrackPaths;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track>? onToggleFavoriteTrack;
  final bool canSwitchPreviousPlaylist;
  final bool canSwitchNextPlaylist;
  final VoidCallback? onSwitchPreviousPlaylist;
  final VoidCallback? onSwitchNextPlaylist;
  final VoidCallback? onOpenNowPlaying;

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      onClose();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        canSwitchPreviousPlaylist) {
      onSwitchPreviousPlaylist?.call();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowRight &&
        canSwitchNextPlaylist) {
      onSwitchNextPlaylist?.call();
      return KeyEventResult.handled;
    }
    if (_playlistPlaybackSpaceActivator.accepts(
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
    final coverPaths = _playlistCoverPaths();
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
                  child: _PlaylistPlaybackBackground(
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
                                  icon: Icons.queue_music,
                                  label: 'No tracks found',
                                )
                              : _PlaylistPlaybackBody(
                                  folder: folder,
                                  coverPaths: coverPaths,
                                  tracks: tracks,
                                  trackCoverCache: trackCoverCache,
                                  currentTrack: currentTrack,
                                  playing: playing,
                                  playbackActive: playbackActive,
                                  favoriteTrackPaths: favoriteTrackPaths,
                                  onPlayTrack: onPlayTrack,
                                  onToggleFavoriteTrack: onToggleFavoriteTrack,
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
                    identity: _DockPlaylistIdentity(
                      folder: folder,
                      coverPaths: coverPaths,
                    ),
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

  List<String> _playlistCoverPaths() {
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
    final folderCover = folder.coverArtPath;
    if (folderCover != null && folderCover.isNotEmpty) {
      paths.add(folderCover);
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
    final folderCover = folder.coverArtPath;
    if (folderCover != null && folderCover.isNotEmpty) {
      return folderCover;
    }
    return null;
  }
}

class _PlaylistPlaybackBackground extends StatelessWidget {
  const _PlaylistPlaybackBackground({required this.coverPath});

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
                  // Blurred fill; skip() swaps this path so keep the decode small.
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

class _PlaylistPlaybackBody extends StatelessWidget {
  const _PlaylistPlaybackBody({
    required this.folder,
    required this.coverPaths,
    required this.tracks,
    required this.trackCoverCache,
    required this.currentTrack,
    required this.playing,
    required this.playbackActive,
    required this.favoriteTrackPaths,
    required this.onPlayTrack,
    required this.onToggleFavoriteTrack,
  });

  final FolderSummary folder;
  final List<String> coverPaths;
  final List<Track> tracks;
  final Map<String, String?> trackCoverCache;
  final Track? currentTrack;
  final bool playing;
  final bool playbackActive;
  final Set<String> favoriteTrackPaths;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track>? onToggleFavoriteTrack;

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
                child: _PlaylistCompactHeader(
                  folder: folder,
                  coverPaths: coverPaths,
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
                  favoriteTrackPaths: favoriteTrackPaths,
                  onPlayTrack: onPlayTrack,
                  onToggleFavoriteTrack: onToggleFavoriteTrack,
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
              child: _PlaylistHeroStage(
                folder: folder,
                coverPaths: coverPaths,
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
                favoriteTrackPaths: favoriteTrackPaths,
                onPlayTrack: onPlayTrack,
                onToggleFavoriteTrack: onToggleFavoriteTrack,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlaylistHeroStage extends StatelessWidget {
  const _PlaylistHeroStage({
    required this.folder,
    required this.coverPaths,
    required this.currentTrack,
    required this.playing,
  });

  final FolderSummary folder;
  final List<String> coverPaths;
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
                ),
                SizedBox(height: gap),
                _PlaylistStageIdentity(
                  folder: folder,
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

class _PlaylistCompactHeader extends StatelessWidget {
  const _PlaylistCompactHeader({
    required this.folder,
    required this.coverPaths,
    required this.currentTrack,
    required this.playing,
  });

  final FolderSummary folder;
  final List<String> coverPaths;
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
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: _PlaylistStageIdentity(
                    folder: folder,
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

class _PlaylistStageIdentity extends StatelessWidget {
  const _PlaylistStageIdentity({
    required this.folder,
    required this.currentTrack,
    required this.playing,
    required this.compact,
  });

  final FolderSummary folder;
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
          folder.name,
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
          '${folder.trackCount} tracks',
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

class _DockPlaylistIdentity extends StatelessWidget {
  const _DockPlaylistIdentity({required this.folder, required this.coverPaths});

  final FolderSummary folder;
  final List<String> coverPaths;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PlaylistCoverCollage(paths: coverPaths, size: 64, radius: 8),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${folder.trackCount} tracks',
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
