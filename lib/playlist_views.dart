import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'artwork_resolver.dart';
import 'library_widgets.dart';
import 'models.dart';

const _playlistListPageScrollFraction = 0.88;
const _playlistListScrollDuration = Duration(milliseconds: 260);

class PlaylistList extends StatefulWidget {
  const PlaylistList({
    super.key,
    required this.folders,
    required this.tracksByFolder,
    required this.trackCoverCache,
    required this.scrollController,
    required this.keyboardShortcutsEnabled,
    required this.onOpen,
  });

  final List<FolderSummary> folders;
  final Map<String, List<Track>> tracksByFolder;
  final Map<String, String?> trackCoverCache;
  final ScrollController scrollController;
  final bool keyboardShortcutsEnabled;
  final ValueChanged<FolderSummary> onOpen;

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
    if (!oldWidget.keyboardShortcutsEnabled &&
        widget.keyboardShortcutsEnabled) {
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

  @override
  Widget build(BuildContext context) {
    if (widget.folders.isEmpty) {
      return const EmptyState(message: 'No playlist folders detected');
    }

    const horizontalPadding = 22.0;
    final list = ListView.separated(
      key: const PageStorageKey<String>('playlist-list'),
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(
        horizontalPadding,
        16,
        horizontalPadding,
        22,
      ),
      itemCount: widget.folders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final folder = widget.folders[index];
        final tracks = widget.tracksByFolder[folder.path] ?? const <Track>[];
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: _PlaylistRow(
              folder: folder,
              tracks: tracks,
              trackCoverCache: widget.trackCoverCache,
              onOpen: () => widget.onOpen(folder),
            ),
          ),
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
      child: Focus(focusNode: _shortcutFocusNode, child: list),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
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
    final scheme = Theme.of(context).colorScheme;
    final coverPaths = _playlistCoverPaths();
    const radius = 8.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: onOpen,
            child: Ink(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.82),
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: compact ? 126 : 120),
                child: Padding(
                  padding: EdgeInsets.all(compact ? 12 : 14),
                  child: _buildContent(
                    context,
                    scheme,
                    coverPaths,
                    compact: compact,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    ColorScheme scheme,
    List<String> coverPaths, {
    required bool compact,
  }) {
    final previewTracks = tracks.take(3).toList(growable: false);
    final coverSize = compact ? 82.0 : 92.0;
    final titleBlock = _PlaylistTitleBlock(
      folder: folder,
      metrics: _playlistMetrics(),
    );
    final preview = _PlaylistPreviewList(tracks: previewTracks);
    final openIndicator = Icon(
      Icons.chevron_right_rounded,
      color: scheme.onSurfaceVariant.withValues(alpha: 0.78),
    );

    if (compact) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PlaylistCoverCollage(coverPaths: coverPaths, size: coverSize),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [titleBlock, const SizedBox(height: 10), preview],
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(top: 29),
            child: openIndicator,
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _PlaylistCoverCollage(coverPaths: coverPaths, size: coverSize),
        const SizedBox(width: 16),
        Expanded(flex: 5, child: titleBlock),
        const SizedBox(width: 18),
        SizedBox(
          height: 76,
          child: VerticalDivider(
            width: 1,
            thickness: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.72),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(flex: 4, child: preview),
        const SizedBox(width: 12),
        openIndicator,
      ],
    );
  }

  List<Widget> _playlistMetrics() {
    return [
      _PlaylistMetric(
        icon: Icons.music_note,
        label: '${folder.trackCount} tracks',
      ),
      _PlaylistMetric(icon: Icons.album, label: '${folder.albumCount} albums'),
      _PlaylistMetric(
        icon: Icons.person,
        label: '${folder.artistCount} artists',
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

class _PlaylistTitleBlock extends StatelessWidget {
  const _PlaylistTitleBlock({required this.folder, required this.metrics});

  final FolderSummary folder;
  final List<Widget> metrics;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          folder.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 6, children: metrics),
      ],
    );
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

class _PlaylistPreviewTrack extends StatelessWidget {
  const _PlaylistPreviewTrack({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    return Text(
      '${track.title} · ${track.artist}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textStyle,
    );
  }
}

class _PlaylistPreviewList extends StatelessWidget {
  const _PlaylistPreviewList({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (tracks.isEmpty) {
      return Text(
        'No tracks found',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < tracks.length; index += 1) ...[
          if (index > 0) const SizedBox(height: 5),
          _PlaylistPreviewTrack(track: tracks[index]),
        ],
      ],
    );
  }
}

class _PlaylistMetric extends StatelessWidget {
  const _PlaylistMetric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
