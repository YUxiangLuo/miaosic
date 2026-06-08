import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'library_widgets.dart';
import 'models.dart';

const _albumCaseRadius = 8.0;
const _albumHoverDuration = Duration(milliseconds: 140);
const _albumHoverCurve = Curves.easeOutCubic;
const _albumGridScrollThreshold = 8.0;
const _albumGridPageScrollFraction = 0.88;
const _albumGridScrollDuration = Duration(milliseconds: 260);
const _albumGridJumpButtonDuration = Duration(milliseconds: 140);

class AlbumGrid extends StatefulWidget {
  const AlbumGrid({
    super.key,
    required this.albums,
    required this.tracksByFolder,
    required this.scrollController,
    required this.keyboardShortcutsEnabled,
    required this.onOpen,
  });

  final List<AlbumSummary> albums;
  final Map<String, List<Track>> tracksByFolder;
  final ScrollController scrollController;
  final bool keyboardShortcutsEnabled;
  final void Function(AlbumSummary album, List<Track> tracks) onOpen;

  @override
  State<AlbumGrid> createState() => _AlbumGridState();
}

class _AlbumGridState extends State<AlbumGrid> {
  bool _canJumpToTop = false;
  bool _canJumpToBottom = false;
  bool _jumpButtonUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_updateJumpButtons);
    _scheduleJumpButtonUpdate();
  }

  @override
  void didUpdateWidget(covariant AlbumGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_updateJumpButtons);
      widget.scrollController.addListener(_updateJumpButtons);
    }
    if (oldWidget.albums.length != widget.albums.length ||
        oldWidget.scrollController != widget.scrollController) {
      _scheduleJumpButtonUpdate();
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_updateJumpButtons);
    super.dispose();
  }

  void _scheduleJumpButtonUpdate() {
    if (_jumpButtonUpdateScheduled) {
      return;
    }
    _jumpButtonUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpButtonUpdateScheduled = false;
      if (mounted) {
        _updateJumpButtons();
      }
    });
  }

  void _updateJumpButtons() {
    if (!widget.scrollController.hasClients) {
      _setJumpButtonState(canJumpToTop: false, canJumpToBottom: false);
      return;
    }
    _updateJumpButtonsFromMetrics(widget.scrollController.position);
  }

  void _updateJumpButtonsFromMetrics(ScrollMetrics metrics) {
    final scrollable = metrics.maxScrollExtent > _albumGridScrollThreshold;
    _setJumpButtonState(
      canJumpToTop: scrollable && metrics.pixels > _albumGridScrollThreshold,
      canJumpToBottom:
          scrollable &&
          metrics.pixels < metrics.maxScrollExtent - _albumGridScrollThreshold,
    );
  }

  void _setJumpButtonState({
    required bool canJumpToTop,
    required bool canJumpToBottom,
  }) {
    if (_canJumpToTop == canJumpToTop && _canJumpToBottom == canJumpToBottom) {
      return;
    }
    setState(() {
      _canJumpToTop = canJumpToTop;
      _canJumpToBottom = canJumpToBottom;
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    _updateJumpButtonsFromMetrics(notification.metrics);
    return false;
  }

  bool _handleScrollMetricsNotification(
    ScrollMetricsNotification notification,
  ) {
    _updateJumpButtonsFromMetrics(notification.metrics);
    return false;
  }

  void _scrollTo(double target) {
    if (!widget.scrollController.hasClients) {
      return;
    }
    final position = widget.scrollController.position;
    final clamped = target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((clamped - position.pixels).abs() < 1) {
      return;
    }
    widget.scrollController.animateTo(
      clamped,
      duration: _albumGridScrollDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollToTop() {
    if (widget.scrollController.hasClients) {
      _scrollTo(widget.scrollController.position.minScrollExtent);
    }
  }

  void _scrollToBottom() {
    if (widget.scrollController.hasClients) {
      _scrollTo(widget.scrollController.position.maxScrollExtent);
    }
  }

  void _scrollPage(int direction) {
    if (!widget.scrollController.hasClients) {
      return;
    }
    final position = widget.scrollController.position;
    _scrollTo(
      position.pixels +
          position.viewportDimension * _albumGridPageScrollFraction * direction,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.albums.isEmpty) {
      return const EmptyState(message: 'No album folders detected');
    }

    final grid = LayoutBuilder(
      builder: (context, constraints) {
        _scheduleJumpButtonUpdate();
        final width = constraints.maxWidth;
        const gridPadding = 26.0;
        const crossAxisSpacing = 30.0;
        const mainAxisSpacing = 36.0;
        final columns = math.min(6, math.max(2, (width / 220).floor()));
        final usableWidth =
            width - (gridPadding * 2) - (crossAxisSpacing * (columns - 1));
        final tileWidth = math.max(0.0, usableWidth / columns);
        return Stack(
          children: [
            NotificationListener<ScrollMetricsNotification>(
              onNotification: _handleScrollMetricsNotification,
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleScrollNotification,
                child: GridView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.all(gridPadding),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: crossAxisSpacing,
                    mainAxisSpacing: mainAxisSpacing,
                    mainAxisExtent: tileWidth,
                  ),
                  itemCount: widget.albums.length,
                  itemBuilder: (context, index) {
                    final album = widget.albums[index];
                    final tracks =
                        widget.tracksByFolder[album.folderPath] ??
                        const <Track>[];
                    return _AlbumTile(
                      album: album,
                      onTap: tracks.isEmpty
                          ? null
                          : () => widget.onOpen(album, tracks),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              right: 24,
              bottom: 24,
              child: SafeArea(
                child: _AlbumGridJumpButtons(
                  showTop: _canJumpToTop,
                  showBottom: _canJumpToBottom,
                  onTop: _scrollToTop,
                  onBottom: _scrollToBottom,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (!widget.keyboardShortcutsEnabled) {
      return grid;
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.space): () => _scrollPage(1),
        const SingleActivator(LogicalKeyboardKey.space, shift: true): () =>
            _scrollPage(-1),
      },
      child: Focus(autofocus: true, child: grid),
    );
  }
}

class _AlbumGridJumpButtons extends StatelessWidget {
  const _AlbumGridJumpButtons({
    required this.showTop,
    required this.showBottom,
    required this.onTop,
    required this.onBottom,
  });

  final bool showTop;
  final bool showBottom;
  final VoidCallback onTop;
  final VoidCallback onBottom;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AlbumGridJumpButton(
          visible: showTop,
          tooltip: 'Back to top',
          icon: Icons.keyboard_double_arrow_up,
          onPressed: onTop,
        ),
        if (showTop && showBottom) const SizedBox(height: 10),
        _AlbumGridJumpButton(
          visible: showBottom,
          tooltip: 'Back to bottom',
          icon: Icons.keyboard_double_arrow_down,
          onPressed: onBottom,
        ),
      ],
    );
  }
}

class _AlbumGridJumpButton extends StatelessWidget {
  const _AlbumGridJumpButton({
    required this.visible,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final bool visible;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: _albumGridJumpButtonDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final scale = Tween<double>(begin: 0.92, end: 1).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
      child: visible
          ? IconButton.filledTonal(
              key: ValueKey(tooltip),
              tooltip: tooltip,
              mouseCursor: SystemMouseCursors.click,
              onPressed: onPressed,
              icon: Icon(icon),
              style: IconButton.styleFrom(
                fixedSize: const Size.square(46),
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.92),
                foregroundColor: Theme.of(context).colorScheme.onSurface,
              ),
            )
          : const SizedBox.shrink(key: ValueKey('hidden')),
    );
  }
}

class _AlbumTile extends StatefulWidget {
  const _AlbumTile({required this.album, required this.onTap});

  final AlbumSummary album;
  final VoidCallback? onTap;

  @override
  State<_AlbumTile> createState() => _AlbumTileState();
}

class _AlbumTileState extends State<_AlbumTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    final hovering = interactive && _hovered;
    return AnimatedScale(
      scale: hovering ? 1.035 : 1,
      duration: _albumHoverDuration,
      curve: _albumHoverCurve,
      child: InkWell(
        borderRadius: BorderRadius.circular(_albumCaseRadius),
        mouseCursor: interactive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onHover: interactive
            ? (hovered) => setState(() => _hovered = hovered)
            : null,
        onTap: widget.onTap,
        child: _AlbumJewelCase(
          coverArtPath: widget.album.coverArtPath,
          hovered: hovering,
        ),
      ),
    );
  }
}

class _AlbumJewelCase extends StatelessWidget {
  const _AlbumJewelCase({required this.coverArtPath, required this.hovered});

  final String? coverArtPath;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: _albumHoverDuration,
      curve: _albumHoverCurve,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_albumCaseRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: hovered ? 0.14 : 0.10),
            blurRadius: hovered ? 24 : 14,
            offset: Offset(0, hovered ? 12 : 7),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: hovered ? 0.72 : 0.56),
            blurRadius: 1,
            offset: const Offset(-1, -1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_albumCaseRadius),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.maxWidth;
            final leftEdgeWidth = math.max(6.0, side * 0.040);
            final edgeWidth = math.max(3.0, side * 0.018);
            return Stack(
              fit: StackFit.expand,
              children: [
                Artwork(
                  path: coverArtPath,
                  size: double.infinity,
                  icon: Icons.album,
                  radius: 0,
                ),
                _PlasticShellTint(hovered: hovered),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: leftEdgeWidth,
                  child: const _SubtleCaseLeftEdge(),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: edgeWidth,
                  child: const _CaseRightEdge(),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: edgeWidth,
                  child: const _CaseBottomEdge(),
                ),
                const _CaseBottomHighlight(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlasticShellTint extends StatelessWidget {
  const _PlasticShellTint({required this.hovered});

  final bool hovered;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.white.withValues(alpha: hovered ? 0.58 : 0.42),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: hovered ? 0.25 : 0.18),
            Colors.white.withValues(alpha: hovered ? 0.08 : 0.05),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.045),
          ],
          stops: const [0, 0.34, 0.68, 1],
        ),
      ),
    );
  }
}

class _SubtleCaseLeftEdge extends StatelessWidget {
  const _SubtleCaseLeftEdge();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Colors.black.withValues(alpha: 0.035)),
              ),
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.22),
                  Colors.white.withValues(alpha: 0.06),
                  Colors.black.withValues(alpha: 0.035),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 3,
          top: 0,
          bottom: 0,
          width: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
        ),
      ],
    );
  }
}

class _CaseRightEdge extends StatelessWidget {
  const _CaseRightEdge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.10)],
        ),
      ),
    );
  }
}

class _CaseBottomEdge extends StatelessWidget {
  const _CaseBottomEdge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.10)],
        ),
      ),
    );
  }
}

class _CaseBottomHighlight extends StatelessWidget {
  const _CaseBottomHighlight();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: 18,
            right: 18,
            bottom: 12,
            height: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
