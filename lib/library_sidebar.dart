import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'library_formatters.dart';
import 'library_types.dart';
import 'library_widgets.dart';
import 'models.dart';

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
    required this.scanState,
    required this.musicRoot,
    required this.scanning,
    required this.progress,
    required this.error,
    required this.nowPlaying,
    required this.onEditMusicRoot,
    required this.onRescan,
    required this.onOpenNowPlaying,
    required this.onSelected,
  });

  final LibraryView selected;
  final int albums;
  final int playlists;
  final Map<String, Object?>? scanState;
  final String musicRoot;
  final bool scanning;
  final ScanProgress? progress;
  final String? error;
  final SidebarNowPlaying? nowPlaying;
  final VoidCallback onEditMusicRoot;
  final VoidCallback onRescan;
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
                  Text(
                    'Miaosic',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
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
              child: _LibraryStats(
                scanState: scanState,
                musicRoot: musicRoot,
                scanning: scanning,
                progress: progress,
                error: error,
                onEditMusicRoot: onEditMusicRoot,
                onRescan: onRescan,
              ),
            ),
          ],
        ),
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
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.onTap,
          child: Container(
            width: double.infinity,
            height: 82,
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
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 72,
                  child: _NowPlayingArtwork(nowPlaying: widget.nowPlaying),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _NowPlayingMotion(
                    controller: _controller,
                    playing: widget.nowPlaying.playing,
                    color: scheme.primary,
                    quietColor: scheme.outlineVariant,
                  ),
                ),
                if (widget.nowPlaying.playing) ...[
                  const SizedBox(width: 8),
                  _MiniPlayingBars(
                    controller: _controller,
                    color: scheme.onPrimary,
                    backgroundColor: scheme.primary,
                  ),
                ],
              ],
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

class _NowPlayingMotion extends StatelessWidget {
  const _NowPlayingMotion({
    required this.controller,
    required this.playing,
    required this.color,
    required this.quietColor,
  });

  final Animation<double> controller;
  final bool playing;
  final Color color;
  final Color quietColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var index = 0; index < 5; index += 1)
              _NowPlayingMotionBar(
                width: _barWidth(controller.value, index),
                color: playing
                    ? color.withValues(alpha: 0.22 + index * 0.035)
                    : quietColor.withValues(alpha: 0.55),
              ),
          ],
        );
      },
    );
  }

  double _barWidth(double value, int index) {
    if (!playing) {
      return switch (index) {
        0 => 10,
        1 => 18,
        2 => 28,
        3 => 18,
        _ => 10,
      };
    }
    final phase = value * 6.283185307179586 + index * 0.9;
    return 10 + ((1 + math.sin(phase)) / 2) * 18;
  }
}

class _NowPlayingMotionBar extends StatelessWidget {
  const _NowPlayingMotionBar({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: width,
      height: 4,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
      ),
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

class _LibraryStats extends StatelessWidget {
  const _LibraryStats({
    required this.scanState,
    required this.musicRoot,
    required this.scanning,
    required this.progress,
    required this.error,
    required this.onEditMusicRoot,
    required this.onRescan,
  });

  final Map<String, Object?>? scanState;
  final String musicRoot;
  final bool scanning;
  final ScanProgress? progress;
  final String? error;
  final VoidCallback onEditMusicRoot;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scannedAt = scanState?['scanned_at_ms'] as int?;
    final elapsedMs = scanState?['elapsed_ms'] as int?;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                scanning ? Icons.sync : Icons.storage,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                scanning ? 'Scanning' : 'Library',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Change music folder',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 30,
                  height: 30,
                ),
                onPressed: scanning ? null : onEditMusicRoot,
                icon: const Icon(Icons.edit, size: 17),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            musicRoot,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            scannedAt == null
                ? 'No scan yet'
                : 'Last scan ${formatDate(scannedAt)} · ${formatElapsed(elapsedMs)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (scanning || error != null) ...[
            const SizedBox(height: 10),
            if (scanning) LinearProgressIndicator(value: null, minHeight: 3),
            if (progress != null) ...[
              const SizedBox(height: 6),
              Text(
                '${progress!.tracksParsed} tracks',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                progress!.currentPath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (error != null)
              Text(
                error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: scanning ? null : onRescan,
              icon: scanning
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(scanning ? 'Scanning' : 'Rescan'),
            ),
          ),
        ],
      ),
    );
  }
}
