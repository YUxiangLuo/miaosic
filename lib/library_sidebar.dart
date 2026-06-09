import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'library_types.dart';
import 'library_widgets.dart';

enum SidebarNowPlayingKind { album, playlist }

class SidebarNowPlaying {
  const SidebarNowPlaying.album({
    required this.coverArtPath,
    required this.playing,
  }) : kind = SidebarNowPlayingKind.album,
       playlistCoverArtPaths = const [];

  const SidebarNowPlaying.playlist({
    required this.playlistCoverArtPaths,
    required this.playing,
  }) : kind = SidebarNowPlayingKind.playlist,
       coverArtPath = null;

  final SidebarNowPlayingKind kind;
  final String? coverArtPath;
  final List<String?> playlistCoverArtPaths;
  final bool playing;
}

class LibrarySidebar extends StatelessWidget {
  const LibrarySidebar({
    super.key,
    required this.selected,
    required this.albums,
    required this.playlists,
    required this.nowPlaying,
    required this.onOpenLibrary,
    required this.onOpenNowPlaying,
    required this.onSelected,
  });

  final LibraryView selected;
  final int albums;
  final int playlists;
  final SidebarNowPlaying? nowPlaying;
  final VoidCallback onOpenLibrary;
  final VoidCallback? onOpenNowPlaying;
  final ValueChanged<LibraryView> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 212,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.equalizer, color: scheme.onPrimary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Miaosic',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (final view in LibraryView.values)
              _SidebarItem(
                view: view,
                selected: selected == view,
                count: switch (view) {
                  LibraryView.albums => albums,
                  LibraryView.playlists => playlists,
                },
                onTap: () => onSelected(view),
              ),
            const Spacer(),
            if (nowPlaying != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: _NowPlayingEntry(
                  nowPlaying: nowPlaying!,
                  onTap: onOpenNowPlaying,
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: _SidebarFooterActions(onOpenLibrary: onOpenLibrary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarFooterActions extends StatelessWidget {
  const _SidebarFooterActions({required this.onOpenLibrary});

  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SidebarActionButton(
          tooltip: 'Library settings',
          icon: Icons.storage,
          onPressed: onOpenLibrary,
        ),
        const SizedBox(width: 10),
        const _SidebarActionButton(
          tooltip: 'Toggle dark mode',
          icon: Icons.brightness_6,
          onPressed: null,
        ),
        const SizedBox(width: 10),
        const _SidebarActionButton(
          tooltip: 'Settings',
          icon: Icons.settings,
          onPressed: null,
        ),
      ],
    );
  }
}

class _SidebarActionButton extends StatelessWidget {
  const _SidebarActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 21),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.view,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final LibraryView view;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                view.icon,
                size: 20,
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  view.label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              Text(
                count.toString(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NowPlayingEntry extends StatefulWidget {
  const _NowPlayingEntry({required this.nowPlaying, required this.onTap});

  final SidebarNowPlaying nowPlaying;
  final VoidCallback? onTap;

  @override
  State<_NowPlayingEntry> createState() => _NowPlayingEntryState();
}

class _NowPlayingEntryState extends State<_NowPlayingEntry>
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
  void didUpdateWidget(covariant _NowPlayingEntry oldWidget) {
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
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
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
                  color: scheme.primary.withValues(alpha: 0.10 + pulse * 0.08),
                  blurRadius: 14 + pulse * 6,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: child,
        );
      },
      child: Material(
        color: Colors.transparent,
        child: AspectRatio(
          aspectRatio: 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: widget.onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: widget.nowPlaying.playing
                      ? scheme.primary.withValues(alpha: 0.55)
                      : scheme.outlineVariant,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _NowPlayingArtwork(nowPlaying: widget.nowPlaying),
                  ),
                  if (widget.nowPlaying.playing)
                    Center(
                      child: _MiniPlayingBars(
                        controller: _controller,
                        color: scheme.onPrimary,
                        backgroundColor: scheme.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NowPlayingArtwork extends StatelessWidget {
  const _NowPlayingArtwork({required this.nowPlaying});

  final SidebarNowPlaying nowPlaying;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: switch (nowPlaying.kind) {
        SidebarNowPlayingKind.album => Artwork(
          path: nowPlaying.coverArtPath,
          size: double.infinity,
          icon: Icons.album,
          radius: 0,
        ),
        SidebarNowPlayingKind.playlist => _NowPlayingPlaylistCollage(
          paths: nowPlaying.playlistCoverArtPaths,
        ),
      },
    );
  }
}

class _NowPlayingPlaylistCollage extends StatelessWidget {
  const _NowPlayingPlaylistCollage({required this.paths});

  final List<String?> paths;

  @override
  Widget build(BuildContext context) {
    final padded = paths.take(4).toList(growable: true);
    while (padded.length < 4) {
      padded.add(null);
    }
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _PlaylistCollageTile(path: padded[0])),
              Expanded(child: _PlaylistCollageTile(path: padded[1])),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _PlaylistCollageTile(path: padded[2])),
              Expanded(child: _PlaylistCollageTile(path: padded[3])),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlaylistCollageTile extends StatelessWidget {
  const _PlaylistCollageTile({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    return Artwork(
      path: path,
      size: double.infinity,
      icon: Icons.queue_music,
      radius: 0,
    );
  }
}

class _MiniPlayingBars extends StatelessWidget {
  const _MiniPlayingBars({
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
            color: backgroundColor.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var index = 0; index < 3; index += 1) ...[
                _MiniPlayingBar(
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
    final phase = value * 6.283185307179586 + index * 1.4;
    return 4 + ((1 + math.sin(phase)) / 2) * 8;
  }
}

class _MiniPlayingBar extends StatelessWidget {
  const _MiniPlayingBar({required this.color, required this.height});

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
