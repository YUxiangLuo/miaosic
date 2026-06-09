part of 'album_playback_view.dart';

class _AlbumPlaybackDock extends StatelessWidget {
  const _AlbumPlaybackDock({
    required this.playing,
    required this.nowPlayingAlbum,
    required this.canPrevious,
    required this.canNext,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
    required this.onOpenNowPlayingAlbum,
  });

  final bool playing;
  final AlbumPlaybackNowPlaying? nowPlayingAlbum;
  final bool canPrevious;
  final bool canNext;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;
  final VoidCallback? onOpenNowPlayingAlbum;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.34),
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
                    24.0,
                    math.max(14.0, constraints.maxHeight * 0.12),
                  );
                  final maxPrimaryButtonWidth =
                      (constraints.maxWidth - gap * 2) / 3;
                  final primaryButtonSize = math.max(
                    64.0,
                    [
                      constraints.maxHeight * 0.78,
                      maxPrimaryButtonWidth,
                      112.0,
                    ].reduce(math.min),
                  );
                  final secondaryButtonSize = math.max(
                    56.0,
                    primaryButtonSize * 0.72,
                  );
                  final controlsWidth =
                      secondaryButtonSize * 2 + primaryButtonSize + gap * 2;
                  final sideSlotWidth =
                      (constraints.maxWidth - controlsWidth) / 2 - gap;
                  final baseNowPlayingSize = math.min(
                    96.0,
                    math.max(64.0, constraints.maxHeight * 0.72),
                  );
                  final showNowPlaying =
                      nowPlayingAlbum != null && sideSlotWidth >= 56;
                  final nowPlayingSize = showNowPlaying
                      ? math.min(baseNowPlayingSize, sideSlotWidth)
                      : baseNowPlayingSize;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      if (showNowPlaying)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox.square(
                            dimension: nowPlayingSize,
                            child: _DockNowPlayingAlbum(
                              nowPlaying: nowPlayingAlbum!,
                              onTap: onOpenNowPlayingAlbum,
                            ),
                          ),
                        ),
                      _AlbumPlaybackControls(
                        playing: playing,
                        canPrevious: canPrevious,
                        canNext: canNext,
                        onPrevious: onPrevious,
                        onToggle: onToggle,
                        onNext: onNext,
                        primaryButtonSize: primaryButtonSize,
                        secondaryButtonSize: secondaryButtonSize,
                        gap: gap,
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

class _DockNowPlayingAlbum extends StatefulWidget {
  const _DockNowPlayingAlbum({required this.nowPlaying, required this.onTap});

  final AlbumPlaybackNowPlaying nowPlaying;
  final VoidCallback? onTap;

  @override
  State<_DockNowPlayingAlbum> createState() => _DockNowPlayingAlbumState();
}

class _DockNowPlayingAlbumState extends State<_DockNowPlayingAlbum>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _DockNowPlayingAlbum oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nowPlaying.playing != widget.nowPlaying.playing) {
      _syncAnimation();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncAnimation() {
    if (widget.nowPlaying.playing) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Back to now playing album',
      child: AnimatedBuilder(
        animation: _controller,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Artwork(
                      path: widget.nowPlaying.coverArtPath,
                      size: double.infinity,
                      icon: Icons.album,
                      radius: 0,
                    ),
                  ),
                  if (widget.nowPlaying.playing)
                    Center(
                      child: _DockMiniPlayingBars(
                        controller: _controller,
                        color: Colors.white,
                        backgroundColor: Colors.black,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        builder: (context, child) {
          final pulse = widget.nowPlaying.playing
              ? (0.5 + 0.5 * Curves.easeInOut.transform(_controller.value))
              : 0.0;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                if (widget.nowPlaying.playing)
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.08 + pulse * 0.08),
                    blurRadius: 14 + pulse * 5,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: child,
          );
        },
      ),
    );
  }
}

class _DockMiniPlayingBars extends StatelessWidget {
  const _DockMiniPlayingBars({
    required this.controller,
    required this.color,
    required this.backgroundColor,
  });

  final Animation<double> controller;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          width: 24,
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          decoration: BoxDecoration(
            color: backgroundColor.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var index = 0; index < 3; index += 1) ...[
                _DockMiniPlayingBar(
                  color: color,
                  height: _barHeight(controller.value, index),
                ),
                if (index != 2) const SizedBox(width: 2),
              ],
            ],
          ),
        );
      },
    );
  }

  double _barHeight(double value, int index) {
    final phase = value * math.pi * 2 + index * 1.4;
    return 4 + ((1 + math.sin(phase)) / 2) * 8;
  }
}

class _DockMiniPlayingBar extends StatelessWidget {
  const _DockMiniPlayingBar({required this.color, required this.height});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 2.5,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

class _AlbumPlaybackControls extends StatelessWidget {
  const _AlbumPlaybackControls({
    required this.playing,
    required this.canPrevious,
    required this.canNext,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
    required this.primaryButtonSize,
    required this.secondaryButtonSize,
    required this.gap,
  });

  final bool playing;
  final bool canPrevious;
  final bool canNext;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;
  final double primaryButtonSize;
  final double secondaryButtonSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PlaybackIconButton(
          tooltip: 'Previous',
          icon: Icons.skip_previous,
          onPressed: canPrevious ? onPrevious : null,
          size: secondaryButtonSize,
          iconSize: secondaryButtonSize * 0.44,
        ),
        SizedBox(width: gap),
        _PlaybackIconButton(
          tooltip: playing ? 'Pause' : 'Play',
          icon: playing ? Icons.pause : Icons.play_arrow,
          prominent: true,
          onPressed: onToggle,
          size: primaryButtonSize,
          iconSize: primaryButtonSize * 0.44,
        ),
        SizedBox(width: gap),
        _PlaybackIconButton(
          tooltip: 'Next',
          icon: Icons.skip_next,
          onPressed: canNext ? onNext : null,
          size: secondaryButtonSize,
          iconSize: secondaryButtonSize * 0.44,
        ),
      ],
    );
  }
}

class _PlaybackIconButton extends StatelessWidget {
  const _PlaybackIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.size,
    required this.iconSize,
    this.prominent = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: iconSize,
      style: IconButton.styleFrom(
        fixedSize: Size.square(size),
        backgroundColor: Colors.white.withValues(alpha: prominent ? 0.92 : 0.2),
        foregroundColor: prominent
            ? const Color(0xff151515)
            : Colors.white.withValues(alpha: 0.95),
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.28),
      ),
      icon: Icon(icon),
    );
  }
}
