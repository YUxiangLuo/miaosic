import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'artwork_resolver.dart';
import 'library_widgets.dart';
import 'models.dart';
import 'track_views.dart';

class PlaylistList extends StatelessWidget {
  const PlaylistList({
    super.key,
    required this.folders,
    required this.tracksByFolder,
    required this.trackCoverCache,
    required this.scrollController,
    required this.onOpen,
  });

  final List<FolderSummary> folders;
  final Map<String, List<Track>> tracksByFolder;
  final Map<String, String?> trackCoverCache;
  final ScrollController scrollController;
  final ValueChanged<FolderSummary> onOpen;

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty) {
      return const EmptyState(message: 'No playlist folders detected');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 22.0;
        const spacing = 14.0;
        final availableWidth = math.max(
          1.0,
          constraints.maxWidth - horizontalPadding * 2,
        );
        final columns = math.min(
          4,
          math.max(1, (availableWidth / 440).floor()),
        );
        final cardWidth = math.max(
          1.0,
          (availableWidth - spacing * (columns - 1)) / columns,
        );
        const cardHeight = 220.0;
        return GridView.builder(
          key: const PageStorageKey<String>('playlist-list'),
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            16,
            horizontalPadding,
            22,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: cardWidth / cardHeight,
          ),
          itemCount: folders.length,
          itemBuilder: (context, index) {
            final folder = folders[index];
            final tracks = tracksByFolder[folder.path] ?? const <Track>[];
            return _PlaylistRow(
              folder: folder,
              tracks: tracks,
              trackCoverCache: trackCoverCache,
              onOpen: () => onOpen(folder),
            );
          },
        );
      },
    );
  }
}

class PlaylistDetail extends StatelessWidget {
  const PlaylistDetail({
    super.key,
    required this.folder,
    required this.tracks,
    required this.trackCoverCache,
    required this.playbackActive,
    required this.playing,
    required this.onBack,
    required this.onPlayAll,
    required this.onShuffleAll,
    required this.onPrevious,
    required this.onTogglePlayback,
    required this.onNext,
    required this.onPlayTrack,
  });

  final FolderSummary folder;
  final List<Track> tracks;
  final Map<String, String?> trackCoverCache;
  final bool playbackActive;
  final bool playing;
  final VoidCallback onBack;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffleAll;
  final VoidCallback? onPrevious;
  final VoidCallback? onTogglePlayback;
  final VoidCallback? onNext;
  final ValueChanged<Track> onPlayTrack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back to playlists',
                onPressed: onBack,
                constraints: const BoxConstraints.tightFor(
                  width: 38,
                  height: 38,
                ),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 10),
              Artwork(
                path: folder.coverArtPath,
                size: 76,
                icon: Icons.queue_music,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          fit: FlexFit.loose,
                          child: Text(
                            folder.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _PlaylistHeaderControls(
                          playbackActive: playbackActive,
                          playing: playing,
                          onPlayAll: onPlayAll,
                          onShuffleAll: onShuffleAll,
                          onPrevious: onPrevious,
                          onTogglePlayback: onTogglePlayback,
                          onNext: onNext,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _PlaylistMetric(
                          icon: Icons.music_note,
                          label: '${folder.trackCount} tracks',
                        ),
                        _PlaylistMetric(
                          icon: Icons.album,
                          label: '${folder.albumCount} albums',
                        ),
                        _PlaylistMetric(
                          icon: Icons.person,
                          label: '${folder.artistCount} artists',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: PlaylistTrackList(
            tracks: tracks,
            trackCoverCache: trackCoverCache,
            onPlay: onPlayTrack,
          ),
        ),
      ],
    );
  }
}

class _PlaylistHeaderControls extends StatelessWidget {
  const _PlaylistHeaderControls({
    required this.playbackActive,
    required this.playing,
    required this.onPlayAll,
    required this.onShuffleAll,
    required this.onPrevious,
    required this.onTogglePlayback,
    required this.onNext,
  });

  final bool playbackActive;
  final bool playing;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffleAll;
  final VoidCallback? onPrevious;
  final VoidCallback? onTogglePlayback;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    if (!playbackActive) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: onPlayAll,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Play'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onShuffleAll,
            icon: const Icon(Icons.shuffle),
            label: const Text('Shuffle'),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Previous',
          onPressed: onPrevious,
          icon: const Icon(Icons.skip_previous),
        ),
        const SizedBox(width: 4),
        FilledButton.icon(
          onPressed: onTogglePlayback,
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          label: Text(playing ? 'Pause' : 'Play'),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Next',
          onPressed: onNext,
          icon: const Icon(Icons.skip_next),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: onShuffleAll,
          icon: const Icon(Icons.shuffle),
          label: const Text('Shuffle'),
        ),
      ],
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
    return InkWell(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: _buildContent(context, scheme, coverPaths),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ColorScheme scheme,
    List<String> coverPaths,
  ) {
    final previewTracks = tracks.take(3).toList(growable: false);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PlaylistCoverCollage(coverPaths: coverPaths),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 16, runSpacing: 8, children: _playlistMetrics()),
              const Spacer(),
              if (previewTracks.isNotEmpty) ...[
                for (final track in previewTracks)
                  _PlaylistPreviewTrack(track: track),
              ] else
                Text(
                  'No tracks found',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
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

class _PlaylistCoverCollage extends StatelessWidget {
  const _PlaylistCoverCollage({required this.coverPaths});

  final List<String> coverPaths;

  @override
  Widget build(BuildContext context) {
    final paths = coverPaths.take(4).toList(growable: false);
    return SizedBox.square(
      dimension: 188,
      child: ClipRRect(
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
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '${track.title} · ${track.artist}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
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
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
