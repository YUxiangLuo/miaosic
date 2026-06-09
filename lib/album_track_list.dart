part of 'album_playback_view.dart';

class _FadingAlbumTrackList extends StatelessWidget {
  const _FadingAlbumTrackList({
    required this.albumFolderPath,
    required this.tracks,
    required this.currentTrack,
    required this.playing,
    required this.height,
    required this.onPlayTrack,
  });

  final String albumFolderPath;
  final List<Track> tracks;
  final Track? currentTrack;
  final bool playing;
  final double? height;
  final ValueChanged<Track> onPlayTrack;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: _albumTrackListTransitionDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
          child: child,
        );
      },
      child: KeyedSubtree(
        key: ValueKey(albumFolderPath),
        child: _AlbumTrackList(
          tracks: tracks,
          currentTrack: currentTrack,
          playing: playing,
          height: height,
          onPlayTrack: onPlayTrack,
        ),
      ),
    );
  }
}

class _AlbumTrackList extends StatefulWidget {
  const _AlbumTrackList({
    required this.tracks,
    required this.currentTrack,
    required this.playing,
    required this.height,
    required this.onPlayTrack,
  });

  final List<Track> tracks;
  final Track? currentTrack;
  final bool playing;
  final double? height;
  final ValueChanged<Track> onPlayTrack;

  @override
  State<_AlbumTrackList> createState() => _AlbumTrackListState();
}

class _AlbumTrackListState extends State<_AlbumTrackList> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scheduleEnsureCurrentVisible();
  }

  @override
  void didUpdateWidget(covariant _AlbumTrackList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentTrack?.path != widget.currentTrack?.path ||
        oldWidget.tracks.length != widget.tracks.length ||
        oldWidget.height != widget.height) {
      _scheduleEnsureCurrentVisible();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleEnsureCurrentVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ensureCurrentVisible();
      }
    });
  }

  void _ensureCurrentVisible() {
    final currentPath = widget.currentTrack?.path;
    if (currentPath == null || !_scrollController.hasClients) {
      return;
    }

    final index = widget.tracks.indexWhere(
      (track) => track.path == currentPath,
    );
    if (index < 0) {
      return;
    }

    final position = _scrollController.position;
    final rowTop =
        _albumTrackListVerticalPadding +
        index * (_albumTrackRowHeight + _albumTrackSeparatorHeight);
    final rowBottom = rowTop + _albumTrackRowHeight;
    final viewportTop = _scrollController.offset;
    final viewportBottom = viewportTop + position.viewportDimension;

    double? target;
    if (rowTop < viewportTop) {
      target = rowTop;
    } else if (rowBottom > viewportBottom) {
      target = rowBottom - position.viewportDimension;
    }
    if (target == null) {
      return;
    }

    final clamped = target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((clamped - _scrollController.offset).abs() < 1) {
      return;
    }
    _scrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        vertical: _albumTrackListVerticalPadding,
      ),
      itemCount: widget.tracks.length,
      separatorBuilder: (_, _) => Divider(
        height: _albumTrackSeparatorHeight,
        indent: 58,
        endIndent: 12,
        color: Colors.white.withValues(alpha: 0.08),
      ),
      itemBuilder: (context, index) {
        final track = widget.tracks[index];
        final selected = widget.currentTrack?.path == track.path;
        return _AlbumTrackRow(
          index: index,
          track: track,
          selected: selected,
          playing: selected && widget.playing,
          onTap: () => widget.onPlayTrack(track),
        );
      },
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: widget.height == null
          ? SizedBox(width: double.infinity, child: list)
          : SizedBox(height: widget.height, child: list),
    );
  }
}

class _AlbumTrackRow extends StatefulWidget {
  const _AlbumTrackRow({
    required this.index,
    required this.track,
    required this.selected,
    required this.playing,
    required this.onTap,
  });

  final int index;
  final Track track;
  final bool selected;
  final bool playing;
  final VoidCallback onTap;

  @override
  State<_AlbumTrackRow> createState() => _AlbumTrackRowState();
}

class _AlbumTrackRowState extends State<_AlbumTrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final primary = Colors.white.withValues(alpha: widget.selected ? 1 : 0.86);
    final secondary = Colors.white.withValues(
      alpha: widget.selected ? 0.78 : 0.52,
    );
    final backgroundAlpha = widget.selected ? 0.0 : (_hovered ? 0.07 : 0.0);
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      hoverColor: Colors.transparent,
      splashColor: Colors.white.withValues(alpha: 0.08),
      highlightColor: Colors.white.withValues(alpha: 0.05),
      onHover: (hovered) => setState(() => _hovered = hovered),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        height: _albumTrackRowHeight,
        padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: backgroundAlpha),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: widget.playing
                    ? _PlayingBarsIcon(
                        key: const ValueKey('playing'),
                        color: primary,
                      )
                    : Text(
                        _trackIndexLabel(widget.index, widget.track),
                        key: ValueKey('index-${widget.index}'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: secondary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: primary,
                      fontWeight: widget.selected
                          ? FontWeight.w900
                          : FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              formatDurationMs(widget.track.durationMs),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayingBarsIcon extends StatefulWidget {
  const _PlayingBarsIcon({super.key, required this.color});

  final Color color;

  @override
  State<_PlayingBarsIcon> createState() => _PlayingBarsIconState();
}

class _PlayingBarsIconState extends State<_PlayingBarsIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = _controller.value * math.pi * 2;
        return SizedBox(
          width: 22,
          height: 22,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var index = 0; index < 4; index += 1) ...[
                _PlayingBar(
                  color: widget.color,
                  height: _barHeight(phase, index),
                ),
                if (index != 3) const SizedBox(width: 2),
              ],
            ],
          ),
        );
      },
    );
  }

  double _barHeight(double phase, int index) {
    final wave = math.sin(phase + index * 1.35);
    return 6 + ((wave + 1) / 2) * 13;
  }
}

class _PlayingBar extends StatelessWidget {
  const _PlayingBar({required this.color, required this.height});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 3,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

String _trackIndexLabel(int index, Track track) {
  final number = track.trackNumber;
  if (number != null && number > 0) {
    return number.toString().padLeft(2, '0');
  }
  return (index + 1).toString().padLeft(2, '0');
}
