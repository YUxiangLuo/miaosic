import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'artwork_resolver.dart';
import 'library_formatters.dart';
import 'library_widgets.dart';
import 'models.dart';

const _playlistPlaybackSpaceActivator = SingleActivator(
  LogicalKeyboardKey.space,
  includeRepeats: false,
);
const _playlistControlAccent = Color(0xff9ee6d4);
const _playlistControlRadius = 8.0;
const _playlistControlButtonSize = 48.0;

class PlaylistPlaybackView extends StatelessWidget {
  const PlaylistPlaybackView({
    super.key,
    required this.folder,
    required this.tracks,
    required this.trackCoverCache,
    required this.currentTrack,
    required this.playbackActive,
    required this.playing,
    required this.onClose,
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
  final Track? currentTrack;
  final bool playbackActive;
  final bool playing;
  final VoidCallback onClose;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffleAll;
  final VoidCallback? onPrevious;
  final VoidCallback? onTogglePlayback;
  final VoidCallback? onNext;
  final ValueChanged<Track> onPlayTrack;

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      onClose();
      return KeyEventResult.handled;
    }
    if (_playlistPlaybackSpaceActivator.accepts(
      event,
      HardwareKeyboard.instance,
    )) {
      final action = playbackActive ? onTogglePlayback : onPlayAll;
      if (action != null) {
        action();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final coverPaths = _playlistCoverPaths();
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Material(
        color: Colors.black,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xff14211f), Color(0xff050706)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _PlaylistPlaybackHeader(
                  folder: folder,
                  coverPaths: coverPaths,
                  playbackActive: playbackActive,
                  playing: playing,
                  onClose: onClose,
                  onPlayAll: onPlayAll,
                  onShuffleAll: onShuffleAll,
                  onPrevious: onPrevious,
                  onTogglePlayback: onTogglePlayback,
                  onNext: onNext,
                ),
                Expanded(
                  child: tracks.isEmpty
                      ? const _PlaylistPlaybackEmptyState()
                      : _PlaylistPlaybackTable(
                          tracks: tracks,
                          trackCoverCache: trackCoverCache,
                          currentTrack: currentTrack,
                          playing: playing,
                          onPlayTrack: onPlayTrack,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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

class _PlaylistPlaybackHeader extends StatelessWidget {
  const _PlaylistPlaybackHeader({
    required this.folder,
    required this.coverPaths,
    required this.playbackActive,
    required this.playing,
    required this.onClose,
    required this.onPlayAll,
    required this.onShuffleAll,
    required this.onPrevious,
    required this.onTogglePlayback,
    required this.onNext,
  });

  final FolderSummary folder;
  final List<String> coverPaths;
  final bool playbackActive;
  final bool playing;
  final VoidCallback onClose;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffleAll;
  final VoidCallback? onPrevious;
  final VoidCallback? onTogglePlayback;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 960;
        final controls = _PlaylistPlaybackControls(
          playbackActive: playbackActive,
          playing: playing,
          onPlayAll: onPlayAll,
          onShuffleAll: onShuffleAll,
          onPrevious: onPrevious,
          onTogglePlayback: onTogglePlayback,
          onNext: onNext,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Back to library',
                    onPressed: onClose,
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                  const SizedBox(width: 18),
                  _PlaylistPlaybackCover(coverPaths: coverPaths, size: 96),
                  const SizedBox(width: 20),
                  Expanded(child: _PlaylistPlaybackTitle(folder: folder)),
                  if (!compact) ...[const SizedBox(width: 16), controls],
                ],
              ),
              if (compact) ...[const SizedBox(height: 16), controls],
            ],
          ),
        );
      },
    );
  }
}

class _PlaylistPlaybackTitle extends StatelessWidget {
  const _PlaylistPlaybackTitle({required this.folder});

  final FolderSummary folder;

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
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            _HeaderMetric(
              icon: Icons.music_note,
              label: '${folder.trackCount} tracks',
            ),
            _HeaderMetric(
              icon: Icons.album,
              label: '${folder.albumCount} albums',
            ),
            _HeaderMetric(
              icon: Icons.person,
              label: '${folder.artistCount} artists',
            ),
          ],
        ),
      ],
    );
  }
}

class _PlaylistPlaybackControls extends StatelessWidget {
  const _PlaylistPlaybackControls({
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
      return _PlaylistControlBar(
        children: [
          _PlaylistControlButton(
            tooltip: 'Play',
            icon: Icons.play_arrow_rounded,
            onPressed: onPlayAll,
            prominent: true,
          ),
          const _PlaylistControlDivider(),
          _PlaylistControlButton(
            tooltip: 'Shuffle',
            icon: Icons.shuffle_rounded,
            onPressed: onShuffleAll,
          ),
        ],
      );
    }

    return _PlaylistControlBar(
      children: [
        _PlaylistControlButton(
          tooltip: 'Previous',
          icon: Icons.skip_previous_rounded,
          onPressed: onPrevious,
        ),
        const _PlaylistControlDivider(),
        _PlaylistControlButton(
          tooltip: playing ? 'Pause' : 'Play',
          icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          onPressed: onTogglePlayback,
          prominent: true,
        ),
        const _PlaylistControlDivider(),
        _PlaylistControlButton(
          tooltip: 'Next',
          icon: Icons.skip_next_rounded,
          onPressed: onNext,
        ),
        const _PlaylistControlDivider(),
        _PlaylistControlButton(
          tooltip: 'Shuffle',
          icon: Icons.shuffle_rounded,
          onPressed: onShuffleAll,
        ),
      ],
    );
  }
}

class _PlaylistControlBar extends StatelessWidget {
  const _PlaylistControlBar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(_playlistControlRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class _PlaylistControlButton extends StatelessWidget {
  const _PlaylistControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.prominent = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(_playlistControlButtonSize),
        minimumSize: const Size.square(_playlistControlButtonSize),
        maximumSize: const Size.square(_playlistControlButtonSize),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_playlistControlRadius),
        ),
        backgroundColor: prominent
            ? _playlistControlAccent
            : Colors.transparent,
        foregroundColor: prominent
            ? const Color(0xff07110f)
            : Colors.white.withValues(alpha: 0.9),
        disabledBackgroundColor: prominent
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.transparent,
        disabledForegroundColor: Colors.white.withValues(alpha: 0.26),
        hoverColor: prominent
            ? Colors.black.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.08),
        highlightColor: prominent
            ? Colors.black.withValues(alpha: 0.11)
            : Colors.white.withValues(alpha: 0.10),
      ),
    );
  }
}

class _PlaylistControlDivider extends StatelessWidget {
  const _PlaylistControlDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: Colors.white.withValues(alpha: 0.12),
      ),
    );
  }
}

class _PlaylistPlaybackTable extends StatelessWidget {
  const _PlaylistPlaybackTable({
    required this.tracks,
    required this.trackCoverCache,
    required this.currentTrack,
    required this.playing,
    required this.onPlayTrack,
  });

  final List<Track> tracks;
  final Map<String, String?> trackCoverCache;
  final Track? currentTrack;
  final bool playing;
  final ValueChanged<Track> onPlayTrack;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showArtist = constraints.maxWidth >= 600;
        final showAlbum = constraints.maxWidth >= 760;
        return Column(
          children: [
            _PlaylistTableHeader(showArtist: showArtist, showAlbum: showAlbum),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                itemCount: tracks.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  final selected = currentTrack?.path == track.path;
                  return _PlaylistTableRow(
                    index: index,
                    track: track,
                    artworkPath: resolveTrackArtwork(track, trackCoverCache),
                    selected: selected,
                    playing: selected && playing,
                    showArtist: showArtist,
                    showAlbum: showAlbum,
                    onTap: () => onPlayTrack(track),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlaylistTableHeader extends StatelessWidget {
  const _PlaylistTableHeader({
    required this.showArtist,
    required this.showAlbum,
  });

  final bool showArtist;
  final bool showAlbum;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Colors.white.withValues(alpha: 0.46),
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
      child: Row(
        children: [
          SizedBox(width: 44, child: Text('#', style: style)),
          const SizedBox(width: 52),
          const SizedBox(width: 14),
          Expanded(flex: 5, child: Text('TITLE', style: style)),
          if (showArtist) ...[
            const SizedBox(width: 16),
            Expanded(flex: 3, child: Text('ARTIST', style: style)),
          ],
          if (showAlbum) ...[
            const SizedBox(width: 16),
            Expanded(flex: 3, child: Text('ALBUM', style: style)),
          ],
          const SizedBox(width: 16),
          SizedBox(
            width: 68,
            child: Text('TIME', textAlign: TextAlign.right, style: style),
          ),
        ],
      ),
    );
  }
}

class _PlaylistTableRow extends StatelessWidget {
  const _PlaylistTableRow({
    required this.index,
    required this.track,
    required this.artworkPath,
    required this.selected,
    required this.playing,
    required this.showArtist,
    required this.showAlbum,
    required this.onTap,
  });

  final int index;
  final Track track;
  final String? artworkPath;
  final bool selected;
  final bool playing;
  final bool showArtist;
  final bool showAlbum;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Colors.white.withValues(alpha: selected ? 1 : 0.88);
    final secondary = Colors.white.withValues(alpha: selected ? 0.78 : 0.55);
    final background = selected
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.transparent;
    return Material(
      color: background,
      child: InkWell(
        onTap: onTap,
        hoverColor: Colors.white.withValues(alpha: selected ? 0.08 : 0.06),
        splashColor: Colors.white.withValues(alpha: 0.10),
        highlightColor: Colors.white.withValues(alpha: 0.08),
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Center(
                  child: playing
                      ? Icon(Icons.graphic_eq, size: 18, color: primary)
                      : Text(
                          (index + 1).toString().padLeft(2, '0'),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: secondary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                ),
              ),
              Artwork(path: artworkPath, size: 42, icon: Icons.music_note),
              const SizedBox(width: 14),
              Expanded(
                flex: 5,
                child: _TrackCell(
                  title: track.title,
                  subtitle: showArtist ? track.fileName : track.artist,
                  titleColor: primary,
                  subtitleColor: secondary,
                ),
              ),
              if (showArtist) ...[
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (showAlbum) ...[
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: Text(
                    track.album.isEmpty ? track.folderName : track.album,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 16),
              SizedBox(
                width: 68,
                child: Text(
                  formatDurationMs(track.durationMs),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackCell extends StatelessWidget {
  const _TrackCell({
    required this.title,
    required this.subtitle,
    required this.titleColor,
    required this.subtitleColor,
  });

  final String title;
  final String subtitle;
  final Color titleColor;
  final Color subtitleColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: titleColor,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: subtitleColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PlaylistPlaybackCover extends StatelessWidget {
  const _PlaylistPlaybackCover({required this.coverPaths, required this.size});

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
              Expanded(child: _CoverGridTile(path: padded[0])),
              Expanded(child: _CoverGridTile(path: padded[1])),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _CoverGridTile(path: padded[2])),
              Expanded(child: _CoverGridTile(path: padded[3])),
            ],
          ),
        ),
      ],
    );
  }
}

class _CoverGridTile extends StatelessWidget {
  const _CoverGridTile({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Artwork(
      path: path,
      size: double.infinity,
      icon: Icons.music_note,
      radius: 0,
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.62)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.64),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaylistPlaybackEmptyState extends StatelessWidget {
  const _PlaylistPlaybackEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.queue_music,
            size: 52,
            color: Colors.white.withValues(alpha: 0.34),
          ),
          const SizedBox(height: 12),
          Text(
            'No tracks found',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
