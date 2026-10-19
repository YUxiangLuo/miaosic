import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'artwork_resolver.dart';
import 'collection_playback_style.dart';
import 'library_widgets.dart';
import 'models.dart';

class CollectionPlaybackDock extends StatelessWidget {
  const CollectionPlaybackDock({
    super.key,
    required this.identity,
    this.shuffleTooltip = 'Shuffle',
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

  final Widget identity;
  final String shuffleTooltip;
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
                            child: identity,
                          ),
                        ),
                      _PlaybackControls(
                        shuffleTooltip: shuffleTooltip,
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

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({
    required this.shuffleTooltip,
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

  final String shuffleTooltip;
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
        _DockIconButton(
          tooltip: 'Previous',
          icon: Icons.skip_previous_rounded,
          onPressed: playbackActive ? onPrevious : null,
          size: secondaryButtonSize,
          iconSize: secondaryButtonSize * 0.45,
        ),
        SizedBox(width: gap),
        _DockIconButton(
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
        _DockIconButton(
          tooltip: 'Next',
          icon: Icons.skip_next_rounded,
          onPressed: playbackActive ? onNext : null,
          size: secondaryButtonSize,
          iconSize: secondaryButtonSize * 0.45,
        ),
        SizedBox(width: gap),
        _DockIconButton(
          tooltip: shuffleTooltip,
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

class _DockIconButton extends StatelessWidget {
  const _DockIconButton({
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
        ? collectionControlAccent
        : accent
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.20);
    final foregroundColor = prominent
        ? const Color(0xff07110f)
        : accent
        ? collectionControlAccent
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
          borderRadius: BorderRadius.circular(collectionDockRadius),
        ),
      ),
      icon: Icon(icon),
    );
  }
}
