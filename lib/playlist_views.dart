import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'artwork_resolver.dart';
import 'library_widgets.dart';
import 'models.dart';

const _playlistListPageScrollFraction = 0.88;
const _playlistListScrollDuration = Duration(milliseconds: 260);
const _playlistCardGap = 18.0;
const _playlistIndicatorReservedHeight = 84.0;
const _playlistIndicatorDotSize = 36.0;
const _playlistIndicatorActiveWidth = 58.0;
const _playlistIndicatorGap = 6.0;
const _playlistIndicatorButtonPadding = 4.0;
const _playlistIndicatorBarHorizontalPadding = 16.0;
const _playlistIndicatorBarVerticalPadding = 12.0;

class PlaylistList extends StatefulWidget {
  const PlaylistList({
    super.key,
    required this.folders,
    required this.tracksByFolder,
    required this.trackCoverCache,
    required this.scrollController,
    required this.keyboardShortcutsEnabled,
    required this.onOpen,
    this.focusRequestToken,
  });

  final List<FolderSummary> folders;
  final Map<String, List<Track>> tracksByFolder;
  final Map<String, String?> trackCoverCache;
  final ScrollController scrollController;
  final bool keyboardShortcutsEnabled;
  final ValueChanged<FolderSummary> onOpen;
  final Object? focusRequestToken;

  @override
  State<PlaylistList> createState() => _PlaylistListState();
}

class _PlaylistListState extends State<PlaylistList> {
  late final FocusNode _shortcutFocusNode;

  @override
  void initState() {
    super.initState();
    _shortcutFocusNode = FocusNode(debugLabel: 'PlaylistListShortcuts');
    _scheduleShortcutFocusRequest();
  }

  @override
  void didUpdateWidget(covariant PlaylistList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.keyboardShortcutsEnabled &&
        (!oldWidget.keyboardShortcutsEnabled ||
            oldWidget.focusRequestToken != widget.focusRequestToken)) {
      _scheduleShortcutFocusRequest();
    }
  }

  @override
  void dispose() {
    _shortcutFocusNode.dispose();
    super.dispose();
  }

  void _scheduleShortcutFocusRequest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.keyboardShortcutsEnabled) {
        return;
      }
      _shortcutFocusNode.requestFocus();
    });
  }

  void _scrollPage(int direction) {
    if (!widget.scrollController.hasClients) {
      return;
    }
    final position = widget.scrollController.position;
    final target =
        position.pixels +
        position.viewportDimension *
            _playlistListPageScrollFraction *
            direction;
    final clamped = target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((clamped - position.pixels).abs() < 1) {
      return;
    }
    widget.scrollController.animateTo(
      clamped,
      duration: _playlistListScrollDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !widget.scrollController.hasClients) {
      return;
    }
    final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!widget.scrollController.hasClients) {
        return;
      }
      final position = widget.scrollController.position;
      final target = (position.pixels + delta)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((target - position.pixels).abs() < 0.5) {
        return;
      }
      position.jumpTo(target);
    });
  }

  void _scrollToPlaylist(int index, double itemExtent) {
    if (!widget.scrollController.hasClients) {
      return;
    }
    final position = widget.scrollController.position;
    final target = (index * itemExtent)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    widget.scrollController.animateTo(
      target,
      duration: _playlistListScrollDuration,
      curve: Curves.easeOutCubic,
    );
  }

  int _activePlaylistIndex(double itemExtent, int count) {
    if (count <= 1 || !widget.scrollController.hasClients) {
      return 0;
    }
    final position = widget.scrollController.position;
    if ((position.maxScrollExtent - position.pixels).abs() <= 1) {
      return count - 1;
    }
    final raw = (position.pixels / itemExtent).round();
    return raw.clamp(0, count - 1).toInt();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.folders.isEmpty) {
      return const EmptyState(message: 'No playlist folders detected');
    }

    final list = LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 520 ? 16.0 : 22.0;
        final verticalPadding = constraints.maxHeight < 520 ? 16.0 : 24.0;
        final showIndicator =
            widget.folders.length > 1 &&
            constraints.maxWidth >= 280 &&
            constraints.maxHeight >= 320;
        final bottomPadding =
            verticalPadding +
            (showIndicator ? _playlistIndicatorReservedHeight : 0);
        final cardHeight = math.max(
          220.0,
          constraints.maxHeight - verticalPadding - bottomPadding,
        );
        final cardWidth = math.min(520.0, math.max(347.0, cardHeight * 0.613));
        final itemExtent = cardWidth + _playlistCardGap;
        final playlistList = ListView.separated(
          key: const PageStorageKey<String>('playlist-list'),
          controller: widget.scrollController,
          scrollDirection: Axis.horizontal,
          scrollCacheExtent: const ScrollCacheExtent.pixels(0),
          addAutomaticKeepAlives: false,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            verticalPadding,
            horizontalPadding,
            bottomPadding,
          ),
          itemCount: widget.folders.length,
          separatorBuilder: (_, _) => const SizedBox(width: _playlistCardGap),
          itemBuilder: (context, index) {
            final folder = widget.folders[index];
            final tracks =
                widget.tracksByFolder[folder.path] ?? const <Track>[];
            return SizedBox(
              width: cardWidth,
              child: _PlaylistCard(
                folder: folder,
                tracks: tracks,
                trackCoverCache: widget.trackCoverCache,
                onOpen: () => widget.onOpen(folder),
              ),
            );
          },
        );

        if (!showIndicator) {
          return playlistList;
        }

        return AnimatedBuilder(
          animation: widget.scrollController,
          child: playlistList,
          builder: (context, child) {
            return Stack(
              children: [
                Positioned.fill(child: child!),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: math.max(8.0, verticalPadding * 0.5),
                  child: Center(
                    child: _PlaylistIndicatorBar(
                      folders: widget.folders,
                      activeIndex: _activePlaylistIndex(
                        itemExtent,
                        widget.folders.length,
                      ),
                      maxWidth: constraints.maxWidth - 36,
                      onSelect: (index) => _scrollToPlaylist(index, itemExtent),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    return CallbackShortcuts(
      bindings: widget.keyboardShortcutsEnabled
          ? <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.space): () =>
                  _scrollPage(1),
              const SingleActivator(
                LogicalKeyboardKey.space,
                shift: true,
              ): () =>
                  _scrollPage(-1),
            }
          : const <ShortcutActivator, VoidCallback>{},
      child: Focus(
        focusNode: _shortcutFocusNode,
        child: Listener(onPointerSignal: _handlePointerSignal, child: list),
      ),
    );
  }
}

class _PlaylistIndicatorBar extends StatelessWidget {
  const _PlaylistIndicatorBar({
    required this.folders,
    required this.activeIndex,
    required this.maxWidth,
    required this.onSelect,
  });

  final List<FolderSummary> folders;
  final int activeIndex;
  final double maxWidth;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final count = folders.length;
    const dotWidth = _playlistIndicatorDotSize;
    const activeWidth = _playlistIndicatorActiveWidth;
    const gap = _playlistIndicatorGap;
    const buttonPadding = _playlistIndicatorButtonPadding * 2;
    const barHorizontalPadding = _playlistIndicatorBarHorizontalPadding * 2;
    final totalWidth =
        activeWidth +
        buttonPadding +
        (dotWidth + buttonPadding) * (count - 1) +
        gap * math.max(0, count - 1);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < count; index += 1) ...[
          if (index > 0) SizedBox(width: gap),
          _PlaylistIndicatorButton(
            key: ValueKey('playlist-indicator-$index'),
            folder: folders[index],
            selected: index == activeIndex,
            width: index == activeIndex ? activeWidth : dotWidth,
            height: dotWidth,
            onTap: () => onSelect(index),
          ),
        ],
      ],
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: math.max(0, maxWidth)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _playlistIndicatorBarHorizontalPadding,
            vertical: _playlistIndicatorBarVerticalPadding,
          ),
          child: totalWidth <= maxWidth - barHorizontalPadding
              ? content
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: content,
                ),
        ),
      ),
    );
  }
}

class _PlaylistIndicatorButton extends StatelessWidget {
  const _PlaylistIndicatorButton({
    super.key,
    required this.folder,
    required this.selected,
    required this.width,
    required this.height,
    required this.onTap,
  });

  final FolderSummary folder;
  final bool selected;
  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? const Color(0xff9ee6d4)
        : Colors.white.withValues(alpha: 0.32);
    return Tooltip(
      message: folder.name,
      waitDuration: const Duration(milliseconds: 350),
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Jump to ${folder.name}',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(_playlistIndicatorButtonPadding),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.folder,
    required this.tracks,
    required this.trackCoverCache,
    required this.onOpen,
  });

  final FolderSummary folder;
  final List<Track> tracks;
  final Map<String, String?> trackCoverCache;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final coverPaths = _playlistCoverPaths();
    const radius = 16.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onOpen,
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xff1d2b27),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 520;
                final veryCompact = constraints.maxHeight < 360;
                final coverSize = compact
                    ? math.min(
                        constraints.maxWidth,
                        math.max(
                          veryCompact ? 72.0 : 100.0,
                          constraints.maxHeight * (veryCompact ? 0.28 : 0.34),
                        ),
                      )
                    : constraints.maxWidth;
                final metrics = _playlistMetrics();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: _PlaylistCoverCollage(
                        coverPaths: coverPaths,
                        size: coverSize,
                      ),
                    ),
                    SizedBox(height: veryCompact ? 8 : (compact ? 14 : 22)),
                    Text(
                      'PLAYLIST',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xff9ee6d4),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.3,
                      ),
                    ),
                    SizedBox(height: veryCompact ? 5 : 8),
                    Text(
                      folder.name,
                      maxLines: veryCompact ? 1 : (compact ? 2 : 3),
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                          ),
                    ),
                    SizedBox(height: veryCompact ? 6 : (compact ? 10 : 14)),
                    Wrap(
                      spacing: 14,
                      runSpacing: 8,
                      children: veryCompact
                          ? metrics.take(1).toList()
                          : metrics,
                    ),
                    SizedBox(height: veryCompact ? 8 : (compact ? 12 : 18)),
                    Expanded(
                      child: _PlaylistTrackPreview(
                        tracks: tracks,
                        trackCoverCache: trackCoverCache,
                        compact: compact,
                        veryCompact: veryCompact,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _playlistMetrics() {
    return [
      _PlaylistMetric(
        icon: Icons.music_note,
        label: '${folder.trackCount} tracks',
        color: Colors.white.withValues(alpha: 0.68),
      ),
      _PlaylistMetric(
        icon: Icons.album,
        label: '${folder.albumCount} albums',
        color: Colors.white.withValues(alpha: 0.68),
      ),
      _PlaylistMetric(
        icon: Icons.person,
        label: '${folder.artistCount} artists',
        color: Colors.white.withValues(alpha: 0.68),
      ),
    ];
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
}

class _PlaylistCoverCollage extends StatelessWidget {
  const _PlaylistCoverCollage({required this.coverPaths, required this.size});

  final List<String> coverPaths;
  final double size;

  @override
  Widget build(BuildContext context) {
    final paths = coverPaths.take(4).toList(growable: false);
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: paths.length <= 1
            ? Artwork(
                path: paths.isEmpty ? null : paths.first,
                size: double.infinity,
                icon: Icons.queue_music,
                radius: 0,
              )
            : _CoverGrid(paths: paths),
      ),
    );
  }
}

class _CoverGrid extends StatelessWidget {
  const _CoverGrid({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final padded = paths.toList(growable: true);
    while (padded.length < 4) {
      padded.add(paths.last);
    }
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Artwork(
                  path: padded[0],
                  size: double.infinity,
                  icon: Icons.music_note,
                  radius: 0,
                ),
              ),
              Expanded(
                child: Artwork(
                  path: padded[1],
                  size: double.infinity,
                  icon: Icons.music_note,
                  radius: 0,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Artwork(
                  path: padded[2],
                  size: double.infinity,
                  icon: Icons.music_note,
                  radius: 0,
                ),
              ),
              Expanded(
                child: Artwork(
                  path: padded[3],
                  size: double.infinity,
                  icon: Icons.music_note,
                  radius: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlaylistTrackPreview extends StatelessWidget {
  const _PlaylistTrackPreview({
    required this.tracks,
    required this.trackCoverCache,
    required this.compact,
    required this.veryCompact,
  });

  final List<Track> tracks;
  final Map<String, String?> trackCoverCache;
  final bool compact;
  final bool veryCompact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: tracks.isEmpty
            ? Center(
                child: Text(
                  'No tracks found',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.48),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final showArtistColumn = constraints.maxWidth >= 520;
                  final showAlbumColumn = constraints.maxWidth >= 700;
                  final rowHeight = veryCompact
                      ? 36.0
                      : (compact ? 44.0 : 58.0);
                  final visibleCount = constraints.hasBoundedHeight
                      ? math.min(
                          tracks.length,
                          math.max(
                            0,
                            ((constraints.maxHeight + 1) / (rowHeight + 1))
                                .floor(),
                          ),
                        )
                      : tracks.length;
                  if (visibleCount == 0) {
                    return const SizedBox.expand();
                  }
                  return Column(
                    children: [
                      for (var index = 0; index < visibleCount; index += 1) ...[
                        _PlaylistTrackPreviewRow(
                          index: index,
                          track: tracks[index],
                          artworkPath: resolveTrackArtwork(
                            tracks[index],
                            trackCoverCache,
                          ),
                          compact: compact,
                          veryCompact: veryCompact,
                          showArtistColumn: showArtistColumn,
                          showAlbumColumn: showAlbumColumn,
                        ),
                        if (index < visibleCount - 1)
                          Divider(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                      ],
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _PlaylistTrackPreviewRow extends StatelessWidget {
  const _PlaylistTrackPreviewRow({
    required this.index,
    required this.track,
    required this.artworkPath,
    required this.compact,
    required this.veryCompact,
    required this.showArtistColumn,
    required this.showAlbumColumn,
  });

  final int index;
  final Track track;
  final String? artworkPath;
  final bool compact;
  final bool veryCompact;
  final bool showArtistColumn;
  final bool showAlbumColumn;

  @override
  Widget build(BuildContext context) {
    final primary = Colors.white.withValues(alpha: 0.86);
    final secondary = Colors.white.withValues(alpha: 0.50);
    final rowHeight = veryCompact ? 36.0 : (compact ? 44.0 : 58.0);
    final artworkSize = veryCompact ? 24.0 : (compact ? 32.0 : 38.0);
    final titleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: primary,
      fontWeight: FontWeight.w900,
      height: 1.05,
    );
    final metaStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: secondary,
      fontWeight: FontWeight.w800,
      height: 1.05,
    );
    return SizedBox(
      height: rowHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: veryCompact ? 8 : 10),
        child: Row(
          children: [
            SizedBox(
              width: veryCompact ? 24 : 30,
              child: Text(
                (index + 1).toString().padLeft(2, '0'),
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: metaStyle,
              ),
            ),
            SizedBox(width: veryCompact ? 6 : 8),
            Artwork(
              path: artworkPath,
              size: artworkSize,
              icon: Icons.music_note,
              radius: 5,
            ),
            SizedBox(width: veryCompact ? 8 : 12),
            Expanded(
              flex: 5,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  if (!veryCompact) ...[
                    const SizedBox(height: 4),
                    Text(
                      _trackSubtitle(track, index),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: metaStyle,
                    ),
                  ],
                ],
              ),
            ),
            if (showArtistColumn) ...[
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: metaStyle,
                ),
              ),
            ],
            if (showAlbumColumn) ...[
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: Text(
                  track.album.isEmpty ? track.folderName : track.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: metaStyle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _trackSubtitle(Track track, int index) {
    final number = (track.trackNumber ?? index + 1).toString().padLeft(2, '0');
    if (track.artist.isEmpty) {
      return '$number. ${track.fileName}';
    }
    return '$number. ${track.artist} - ${track.fileName}';
  }
}

class _PlaylistMetric extends StatelessWidget {
  const _PlaylistMetric({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final metricColor = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: metricColor),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: metricColor),
          ),
        ),
      ],
    );
  }
}
