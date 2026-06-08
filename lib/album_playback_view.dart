import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'library_formatters.dart';
import 'library_widgets.dart';
import 'models.dart';

const _fallbackAlbumColor = Color(0xff246b5b);
const _albumTrackRowHeight = 56.0;
const _albumTrackSeparatorHeight = 1.0;
const _albumTrackListVerticalPadding = 8.0;
const _wideAlbumColumnsGap = 24.0;
const _albumPlaybackDockHeightFraction = 0.2;
const _albumPlaybackDockMinHeight = 168.0;
const _albumCoverTransitionDuration = Duration(milliseconds: 90);
const _albumTrackListTransitionDuration = Duration(milliseconds: 380);
const _albumBackgroundTransitionDuration = Duration(milliseconds: 1000);
const _albumSwitchThrottleDuration = Duration(milliseconds: 90);
const _albumPlaybackSpaceActivator = SingleActivator(
  LogicalKeyboardKey.space,
  includeRepeats: false,
);
const _albumPlaybackConsumedTraversalKeys = [
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
];

_WideAlbumMetrics _wideAlbumMetrics({
  required double availableWidth,
  required double availableHeight,
}) {
  final trackListWidth = math.min(
    560.0,
    math.max(320.0, availableWidth * 0.38),
  );
  final coverSize = [
    availableWidth * 0.42,
    availableWidth - _wideAlbumColumnsGap - trackListWidth,
    availableHeight,
  ].reduce(math.min).clamp(260.0, 820.0).toDouble();
  final contentWidth = coverSize + _wideAlbumColumnsGap + trackListWidth;
  return _WideAlbumMetrics(
    coverSize: coverSize,
    trackListWidth: trackListWidth,
    contentWidth: contentWidth,
  );
}

class _WideAlbumMetrics {
  const _WideAlbumMetrics({
    required this.coverSize,
    required this.trackListWidth,
    required this.contentWidth,
  });

  final double coverSize;
  final double trackListWidth;
  final double contentWidth;
}

class AlbumPlaybackView extends StatefulWidget {
  const AlbumPlaybackView({
    super.key,
    required this.album,
    required this.tracks,
    required this.currentTrack,
    required this.playing,
    required this.onClose,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
    required this.canSwitchPreviousAlbum,
    required this.canSwitchNextAlbum,
    required this.onSwitchPreviousAlbum,
    required this.onSwitchNextAlbum,
    required this.onPlayTrack,
  });

  final AlbumSummary album;
  final List<Track> tracks;
  final Track? currentTrack;
  final bool playing;
  final VoidCallback onClose;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;
  final bool canSwitchPreviousAlbum;
  final bool canSwitchNextAlbum;
  final VoidCallback? onSwitchPreviousAlbum;
  final VoidCallback? onSwitchNextAlbum;
  final ValueChanged<Track> onPlayTrack;

  @override
  State<AlbumPlaybackView> createState() => _AlbumPlaybackViewState();
}

class _AlbumPlaybackViewState extends State<AlbumPlaybackView> {
  Color _themeColor = _fallbackAlbumColor;
  int _paletteGeneration = 0;
  int _albumTransitionDirection = 0;
  DateTime? _lastAlbumWheelSwitchAt;

  @override
  void initState() {
    super.initState();
    _loadThemeColor();
  }

  @override
  void didUpdateWidget(covariant AlbumPlaybackView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.album.coverArtPath != widget.album.coverArtPath) {
      _loadThemeColor();
    }
  }

  void _loadThemeColor() {
    final coverPath = widget.album.coverArtPath;
    final generation = ++_paletteGeneration;
    if (coverPath == null || coverPath.isEmpty) {
      setState(() => _themeColor = _fallbackAlbumColor);
      return;
    }

    _extractThemeColor(coverPath).then((color) {
      if (mounted && generation == _paletteGeneration) {
        setState(() => _themeColor = color);
      }
    });
  }

  void _handleAlbumWheel(PointerScrollEvent event) {
    if (event.scrollDelta.dy == 0) {
      return;
    }
    final direction = event.scrollDelta.dy > 0 ? 1 : -1;
    final canSwitch = direction < 0
        ? widget.canSwitchPreviousAlbum
        : widget.canSwitchNextAlbum;
    final callback = direction < 0
        ? widget.onSwitchPreviousAlbum
        : widget.onSwitchNextAlbum;
    if (!canSwitch || callback == null) {
      return;
    }

    final now = DateTime.now();
    final lastSwitchAt = _lastAlbumWheelSwitchAt;
    if (lastSwitchAt != null &&
        now.difference(lastSwitchAt) < _albumSwitchThrottleDuration) {
      return;
    }
    _lastAlbumWheelSwitchAt = now;
    setState(() => _albumTransitionDirection = direction);
    callback();
  }

  void _handlePlayPauseCommand() {
    final currentTrack = widget.currentTrack;
    final showingCurrentAlbum =
        currentTrack != null &&
        widget.tracks.any((track) => track.path == currentTrack.path);
    if (showingCurrentAlbum) {
      widget.onToggle();
      return;
    }

    if (widget.tracks.isNotEmpty) {
      widget.onPlayTrack(widget.tracks.first);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        _albumPlaybackConsumedTraversalKeys.contains(event.logicalKey)) {
      return KeyEventResult.handled;
    }
    if (_albumPlaybackSpaceActivator.accepts(
      event,
      HardwareKeyboard.instance,
    )) {
      _handlePlayPauseCommand();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final currentTrack = widget.currentTrack;
    final currentIndex = currentTrack == null
        ? -1
        : widget.tracks.indexWhere((track) => track.path == currentTrack.path);
    final canPrevious = currentIndex > 0;
    final canNext =
        currentIndex >= 0 && currentIndex < widget.tracks.length - 1;
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Material(
        color: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, viewportConstraints) {
            final dockHeight = math.max(
              viewportConstraints.maxHeight * _albumPlaybackDockHeightFraction,
              _albumPlaybackDockMinHeight,
            );
            final contentWidth = math.max(
              0.0,
              viewportConstraints.maxWidth - 56,
            );
            final contentHeight = math.max(
              0.0,
              viewportConstraints.maxHeight - dockHeight - 84,
            );
            return Stack(
              children: [
                _AlbumPlaybackBackground(
                  coverArtPath: widget.album.coverArtPath,
                  themeColor: _themeColor,
                ),
                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(28, 28, 28, dockHeight + 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Back to library',
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.keyboard_arrow_down),
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final transitionDirection =
                                  _albumTransitionDirection == 0
                                  ? 1
                                  : _albumTransitionDirection;
                              if (constraints.maxWidth < 860) {
                                return _AlbumPlaybackNarrowLayout(
                                  album: widget.album,
                                  tracks: widget.tracks,
                                  currentTrack: currentTrack,
                                  coverSize: math.min(
                                    constraints.maxWidth - 36,
                                    constraints.maxHeight * 0.52,
                                  ),
                                  transitionDirection: transitionDirection,
                                  playing: widget.playing,
                                  onAlbumWheel: _handleAlbumWheel,
                                  onPlayTrack: widget.onPlayTrack,
                                );
                              }
                              return _AlbumPlaybackWideLayout(
                                album: widget.album,
                                tracks: widget.tracks,
                                currentTrack: currentTrack,
                                availableWidth: constraints.maxWidth,
                                availableHeight: constraints.maxHeight,
                                transitionDirection: transitionDirection,
                                playing: widget.playing,
                                onAlbumWheel: _handleAlbumWheel,
                                onPlayTrack: widget.onPlayTrack,
                              );
                            },
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
                  child: _AlbumPlaybackDock(
                    album: widget.album,
                    tracks: widget.tracks,
                    playing: widget.playing,
                    canPrevious: canPrevious,
                    canNext: canNext,
                    onPrevious: widget.onPrevious,
                    onToggle: _handlePlayPauseCommand,
                    onNext: widget.onNext,
                    mainContentWidth: contentWidth,
                    mainContentHeight: contentHeight,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AlbumPlaybackWideLayout extends StatelessWidget {
  const _AlbumPlaybackWideLayout({
    required this.album,
    required this.tracks,
    required this.currentTrack,
    required this.availableWidth,
    required this.availableHeight,
    required this.transitionDirection,
    required this.playing,
    required this.onAlbumWheel,
    required this.onPlayTrack,
  });

  final AlbumSummary album;
  final List<Track> tracks;
  final Track? currentTrack;
  final double availableWidth;
  final double availableHeight;
  final int transitionDirection;
  final bool playing;
  final ValueChanged<PointerScrollEvent> onAlbumWheel;
  final ValueChanged<Track> onPlayTrack;

  @override
  Widget build(BuildContext context) {
    final metrics = _wideAlbumMetrics(
      availableWidth: availableWidth,
      availableHeight: availableHeight,
    );
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LargeAlbumArtwork(
            album: album,
            size: metrics.coverSize,
            transitionDirection: transitionDirection,
            onWheel: onAlbumWheel,
          ),
          const SizedBox(width: _wideAlbumColumnsGap),
          SizedBox(
            width: metrics.trackListWidth,
            height: metrics.coverSize,
            child: _FadingAlbumTrackList(
              albumFolderPath: album.folderPath,
              tracks: tracks,
              currentTrack: currentTrack,
              playing: playing,
              height: metrics.coverSize,
              onPlayTrack: onPlayTrack,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumPlaybackNarrowLayout extends StatelessWidget {
  const _AlbumPlaybackNarrowLayout({
    required this.album,
    required this.tracks,
    required this.currentTrack,
    required this.coverSize,
    required this.transitionDirection,
    required this.playing,
    required this.onAlbumWheel,
    required this.onPlayTrack,
  });

  final AlbumSummary album;
  final List<Track> tracks;
  final Track? currentTrack;
  final double coverSize;
  final int transitionDirection;
  final bool playing;
  final ValueChanged<PointerScrollEvent> onAlbumWheel;
  final ValueChanged<Track> onPlayTrack;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _LargeAlbumArtwork(
            album: album,
            size: coverSize,
            transitionDirection: transitionDirection,
            onWheel: onAlbumWheel,
          ),
          const SizedBox(height: 28),
          _FadingAlbumTrackList(
            albumFolderPath: album.folderPath,
            tracks: tracks,
            currentTrack: currentTrack,
            playing: playing,
            height: 360,
            onPlayTrack: onPlayTrack,
          ),
        ],
      ),
    );
  }
}

class _AlbumPlaybackDock extends StatelessWidget {
  const _AlbumPlaybackDock({
    required this.album,
    required this.tracks,
    required this.playing,
    required this.canPrevious,
    required this.canNext,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
    required this.mainContentWidth,
    required this.mainContentHeight,
  });

  final AlbumSummary album;
  final List<Track> tracks;
  final bool playing;
  final bool canPrevious;
  final bool canNext;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;
  final double mainContentWidth;
  final double mainContentHeight;

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
                  final compact =
                      constraints.maxWidth < 760 || constraints.maxHeight < 168;
                  final dockContentWidth = constraints.maxWidth;
                  final alignToCover =
                      mainContentWidth >= 860 && dockContentWidth > 0;
                  final wideMetrics = alignToCover
                      ? _wideAlbumMetrics(
                          availableWidth: mainContentWidth,
                          availableHeight: mainContentHeight,
                        )
                      : null;
                  final alignedLeftInset = wideMetrics == null
                      ? 0.0
                      : math.max(
                          0.0,
                          (dockContentWidth - wideMetrics.contentWidth) / 2,
                        );
                  final metadataMaxWidth = math.max(
                    0.0,
                    dockContentWidth - alignedLeftInset,
                  );
                  final controls = _AlbumPlaybackControls(
                    playing: playing,
                    canPrevious: canPrevious,
                    canNext: canNext,
                    onPrevious: onPrevious,
                    onToggle: onToggle,
                    onNext: onNext,
                    compact: compact,
                  );
                  return Align(
                    alignment: alignToCover
                        ? Alignment.centerLeft
                        : Alignment.center,
                    child: Padding(
                      padding: EdgeInsets.only(left: alignedLeftInset),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: metadataMaxWidth),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _AlbumDockMetadata(
                              album: album,
                              tracks: tracks,
                              compact: compact,
                            ),
                            SizedBox(height: compact ? 12 : 20),
                            controls,
                          ],
                        ),
                      ),
                    ),
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

class _AlbumDockMetadata extends StatelessWidget {
  const _AlbumDockMetadata({
    required this.album,
    required this.tracks,
    required this.compact,
  });

  final AlbumSummary album;
  final List<Track> tracks;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final titleStyle =
        (compact
                ? Theme.of(context).textTheme.headlineSmall
                : Theme.of(context).textTheme.displaySmall)
            ?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              height: 1.04,
            );
    final subtitleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: Colors.white.withValues(alpha: 0.74),
      fontWeight: FontWeight.w700,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          album.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        ),
        const SizedBox(height: 8),
        Text(
          _albumSubtitle(album, tracks),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: subtitleStyle,
        ),
      ],
    );
  }
}

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
    final backgroundAlpha = widget.selected
        ? (_hovered ? 0.18 : 0.12)
        : (_hovered ? 0.07 : 0.0);
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

class _AlbumPlaybackControls extends StatelessWidget {
  const _AlbumPlaybackControls({
    required this.playing,
    required this.canPrevious,
    required this.canNext,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
    this.compact = false,
  });

  final bool playing;
  final bool canPrevious;
  final bool canNext;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final gap = compact ? 12.0 : 18.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PlaybackIconButton(
          tooltip: 'Previous',
          icon: Icons.skip_previous,
          onPressed: canPrevious ? onPrevious : null,
          compact: compact,
        ),
        SizedBox(width: gap),
        _PlaybackIconButton(
          tooltip: playing ? 'Pause' : 'Play',
          icon: playing ? Icons.pause : Icons.play_arrow,
          prominent: true,
          onPressed: onToggle,
          compact: compact,
        ),
        SizedBox(width: gap),
        _PlaybackIconButton(
          tooltip: 'Next',
          icon: Icons.skip_next,
          onPressed: canNext ? onNext : null,
          compact: compact,
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
    this.prominent = false,
    this.compact = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool prominent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact
        ? (prominent ? 54.0 : 42.0)
        : (prominent ? 72.0 : 54.0);
    return IconButton.filled(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: compact ? (prominent ? 28 : 22) : (prominent ? 34 : 26),
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

class _LargeAlbumArtwork extends StatelessWidget {
  const _LargeAlbumArtwork({
    required this.album,
    required this.size,
    required this.transitionDirection,
    required this.onWheel,
  });

  final AlbumSummary album;
  final double size;
  final int transitionDirection;
  final ValueChanged<PointerScrollEvent> onWheel;

  @override
  Widget build(BuildContext context) {
    final artworkSize = size.clamp(260.0, 820.0).toDouble();
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          GestureBinding.instance.pointerSignalResolver.register(event, (
            resolvedEvent,
          ) {
            if (resolvedEvent is PointerScrollEvent) {
              onWheel(resolvedEvent);
            }
          });
        }
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.36),
              blurRadius: 34,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox.square(
            dimension: artworkSize,
            child: AnimatedSwitcher(
              duration: _albumCoverTransitionDuration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: _coverTransitionBuilder,
              child: KeyedSubtree(
                key: ValueKey(album.folderPath),
                child: Artwork(
                  path: album.coverArtPath,
                  size: artworkSize,
                  icon: Icons.album,
                  radius: 14,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _coverTransitionBuilder(Widget child, Animation<double> animation) {
    final entering = child.key == ValueKey(album.folderPath);
    final direction = transitionDirection == 0 ? 1 : transitionDirection;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final offset = Tween<Offset>(
      begin: Offset(entering ? direction * 0.012 : -direction * 0.006, 0),
      end: Offset.zero,
    ).animate(curved);
    return SlideTransition(position: offset, child: child);
  }
}

class _AlbumPlaybackBackground extends StatelessWidget {
  const _AlbumPlaybackBackground({
    required this.coverArtPath,
    required this.themeColor,
  });

  final String? coverArtPath;
  final Color themeColor;

  @override
  Widget build(BuildContext context) {
    final coverPath = coverArtPath;
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedContainer(
          duration: _albumBackgroundTransitionDuration,
          curve: Curves.easeInOutCubic,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                themeColor.withValues(alpha: 0.96),
                HSLColor.fromColor(
                  themeColor,
                ).withLightness(0.12).toColor().withValues(alpha: 1),
              ],
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: _albumBackgroundTransitionDuration,
          switchInCurve: Curves.easeInOutCubic,
          switchOutCurve: Curves.easeInOutCubic,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              fit: StackFit.expand,
              children: [...previousChildren, ?currentChild],
            );
          },
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: coverPath == null || coverPath.isEmpty
              ? const SizedBox.expand(
                  key: ValueKey('empty-album-background-cover'),
                )
              : _AlbumBackgroundCover(
                  key: ValueKey(coverPath),
                  coverPath: coverPath,
                ),
        ),
        AnimatedContainer(
          duration: _albumBackgroundTransitionDuration,
          curve: Curves.easeInOutCubic,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                themeColor.withValues(alpha: 0.55),
                Colors.black.withValues(alpha: 0.84),
              ],
            ),
          ),
        ),
        ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
      ],
    );
  }
}

class _AlbumBackgroundCover extends StatelessWidget {
  const _AlbumBackgroundCover({super.key, required this.coverPath});

  final String coverPath;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
        child: Transform.scale(
          scale: 1.08,
          child: Image.file(
            File(coverPath),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

Future<Color> _extractThemeColor(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) {
      return _fallbackAlbumColor;
    }
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 40);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) {
      return _fallbackAlbumColor;
    }

    double red = 0;
    double green = 0;
    double blue = 0;
    double totalWeight = 0;
    final pixels = data.buffer.asUint8List();
    for (var offset = 0; offset + 3 < pixels.length; offset += 4) {
      final alpha = pixels[offset + 3];
      if (alpha < 128) {
        continue;
      }
      final r = pixels[offset];
      final g = pixels[offset + 1];
      final b = pixels[offset + 2];
      final color = Color.fromARGB(255, r, g, b);
      final hsl = HSLColor.fromColor(color);
      final lightness = hsl.lightness;
      final saturation = hsl.saturation;
      if (lightness < 0.05 || lightness > 0.95) {
        continue;
      }
      final balance = 1 - (lightness - 0.5).abs();
      final weight = (0.25 + saturation) * balance;
      red += r * weight;
      green += g * weight;
      blue += b * weight;
      totalWeight += weight;
    }

    if (totalWeight <= 0) {
      return _fallbackAlbumColor;
    }
    final averaged = Color.fromARGB(
      255,
      (red / totalWeight).round().clamp(0, 255).toInt(),
      (green / totalWeight).round().clamp(0, 255).toInt(),
      (blue / totalWeight).round().clamp(0, 255).toInt(),
    );
    final hsl = HSLColor.fromColor(averaged);
    return hsl
        .withSaturation(math.max(0.34, hsl.saturation))
        .withLightness(hsl.lightness.clamp(0.22, 0.46).toDouble())
        .toColor();
  } catch (_) {
    return _fallbackAlbumColor;
  }
}

String _albumSubtitle(AlbumSummary album, List<Track> tracks) {
  final year = album.year;
  final yearText = year == null ? '' : ' · $year';
  return '${album.albumArtist}$yearText · ${tracks.length} tracks';
}

String _trackIndexLabel(int index, Track track) {
  final number = track.trackNumber;
  if (number != null && number > 0) {
    return number.toString().padLeft(2, '0');
  }
  return (index + 1).toString().padLeft(2, '0');
}
