import 'dart:math' as math;
import 'dart:ui' as ui;

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
const _playlistDockRadius = 12.0;
const _playlistPlaybackDockHeightFraction = 0.18;
const _playlistPlaybackDockMinHeight = 148.0;

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
    this.favoriteTrackPaths = const {},
    required this.onPlayTrack,
    this.onToggleFavoriteTrack,
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
  final Set<String> favoriteTrackPaths;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track>? onToggleFavoriteTrack;

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
        child: LayoutBuilder(
          builder: (context, viewportConstraints) {
            final dockHeight = math.max(
              viewportConstraints.maxHeight *
                  _playlistPlaybackDockHeightFraction,
              _playlistPlaybackDockMinHeight,
            );
            return Stack(
              children: [
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xff14211f), Color(0xff050706)],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(28, 24, 28, dockHeight + 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Back to library',
                          onPressed: onClose,
                          icon: const Icon(Icons.keyboard_arrow_down),
                        ),
                        const SizedBox(height: 18),
                        Expanded(
                          child: tracks.isEmpty
                              ? const _PlaylistPlaybackEmptyState()
                              : _PlaylistPlaybackBody(
                                  folder: folder,
                                  coverPaths: coverPaths,
                                  tracks: tracks,
                                  trackCoverCache: trackCoverCache,
                                  currentTrack: currentTrack,
                                  playing: playing,
                                  favoriteTrackPaths: favoriteTrackPaths,
                                  onPlayTrack: onPlayTrack,
                                  onToggleFavoriteTrack: onToggleFavoriteTrack,
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
                  child: _PlaylistPlaybackDock(
                    folder: folder,
                    coverPaths: coverPaths,
                    trackCoverCache: trackCoverCache,
                    currentTrack: currentTrack,
                    playbackActive: playbackActive,
                    playing: playing,
                    onPlayAll: onPlayAll,
                    onShuffleAll: onShuffleAll,
                    onPrevious: onPrevious,
                    onTogglePlayback: onTogglePlayback,
                    onNext: onNext,
                  ),
                ),
              ],
            );
          },
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

class _PlaylistPlaybackBody extends StatelessWidget {
  const _PlaylistPlaybackBody({
    required this.folder,
    required this.coverPaths,
    required this.tracks,
    required this.trackCoverCache,
    required this.currentTrack,
    required this.playing,
    required this.favoriteTrackPaths,
    required this.onPlayTrack,
    required this.onToggleFavoriteTrack,
  });

  final FolderSummary folder;
  final List<String> coverPaths;
  final List<Track> tracks;
  final Map<String, String?> trackCoverCache;
  final Track? currentTrack;
  final bool playing;
  final Set<String> favoriteTrackPaths;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track>? onToggleFavoriteTrack;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 840;
        if (compact) {
          return Column(
            children: [
              _PlaylistCompactHeader(folder: folder, coverPaths: coverPaths),
              const SizedBox(height: 18),
              Expanded(
                child: _PlaylistPlaybackTable(
                  tracks: tracks,
                  trackCoverCache: trackCoverCache,
                  currentTrack: currentTrack,
                  playing: playing,
                  favoriteTrackPaths: favoriteTrackPaths,
                  onPlayTrack: onPlayTrack,
                  onToggleFavoriteTrack: onToggleFavoriteTrack,
                ),
              ),
            ],
          );
        }

        final panelWidth = math.min(
          360.0,
          math.max(280.0, constraints.maxWidth * 0.32),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: panelWidth,
              child: _PlaylistHeroPanel(folder: folder, coverPaths: coverPaths),
            ),
            const SizedBox(width: 26),
            Expanded(
              child: _PlaylistPlaybackTable(
                tracks: tracks,
                trackCoverCache: trackCoverCache,
                currentTrack: currentTrack,
                playing: playing,
                favoriteTrackPaths: favoriteTrackPaths,
                onPlayTrack: onPlayTrack,
                onToggleFavoriteTrack: onToggleFavoriteTrack,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlaylistHeroPanel extends StatelessWidget {
  const _PlaylistHeroPanel({required this.folder, required this.coverPaths});

  final FolderSummary folder;
  final List<String> coverPaths;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final coverSize = math.min(
              constraints.maxWidth,
              math.max(180.0, constraints.maxHeight * 0.42),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: _PlaylistPlaybackCover(
                    coverPaths: coverPaths,
                    size: coverSize,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'PLAYLIST',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _playlistControlAccent,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                _PlaylistPlaybackTitle(folder: folder),
                const Spacer(),
                Text(
                  'A local mix collected from this folder.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.54),
                    fontWeight: FontWeight.w600,
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

class _PlaylistCompactHeader extends StatelessWidget {
  const _PlaylistCompactHeader({
    required this.folder,
    required this.coverPaths,
  });

  final FolderSummary folder;
  final List<String> coverPaths;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PlaylistPlaybackCover(coverPaths: coverPaths, size: 88),
        const SizedBox(width: 18),
        Expanded(child: _PlaylistPlaybackTitle(folder: folder)),
      ],
    );
  }
}

class _PlaylistPlaybackDock extends StatelessWidget {
  const _PlaylistPlaybackDock({
    required this.folder,
    required this.coverPaths,
    required this.trackCoverCache,
    required this.currentTrack,
    required this.playbackActive,
    required this.playing,
    required this.onPlayAll,
    required this.onShuffleAll,
    required this.onPrevious,
    required this.onTogglePlayback,
    required this.onNext,
  });

  final FolderSummary folder;
  final List<String> coverPaths;
  final Map<String, String?> trackCoverCache;
  final Track? currentTrack;
  final bool playbackActive;
  final bool playing;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffleAll;
  final VoidCallback? onPrevious;
  final VoidCallback? onTogglePlayback;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.38),
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
                    22.0,
                    math.max(12.0, constraints.maxHeight * 0.12),
                  );
                  final maxPrimaryButtonWidth =
                      (constraints.maxWidth - gap * 4) / 5;
                  final primaryButtonSize = math.max(
                    72.0,
                    [
                      constraints.maxHeight * 0.72,
                      maxPrimaryButtonWidth,
                      108.0,
                    ].reduce(math.min),
                  );
                  final secondaryButtonSize = math.max(
                    56.0,
                    primaryButtonSize * 0.72,
                  );
                  final shuffleButtonSize = math.max(
                    52.0,
                    primaryButtonSize * 0.58,
                  );
                  final controlsWidth =
                      secondaryButtonSize * 2 +
                      primaryButtonSize +
                      shuffleButtonSize +
                      gap * 3;
                  final sideSlotWidth =
                      (constraints.maxWidth - controlsWidth) / 2 - gap;
                  final showPlaylistIdentity = sideSlotWidth >= 170;
                  final showCurrentTrack =
                      currentTrack != null && sideSlotWidth >= 210;

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      if (showPlaylistIdentity)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: sideSlotWidth,
                            child: _DockPlaylistIdentity(
                              folder: folder,
                              coverPaths: coverPaths,
                            ),
                          ),
                        ),
                      _PlaylistPlaybackControls(
                        playbackActive: playbackActive,
                        playing: playing,
                        onPlayAll: onPlayAll,
                        onShuffleAll: onShuffleAll,
                        onPrevious: onPrevious,
                        onTogglePlayback: onTogglePlayback,
                        onNext: onNext,
                        primaryButtonSize: primaryButtonSize,
                        secondaryButtonSize: secondaryButtonSize,
                        shuffleButtonSize: shuffleButtonSize,
                        gap: gap,
                      ),
                      if (showCurrentTrack)
                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: sideSlotWidth,
                            child: _DockCurrentTrack(
                              track: currentTrack!,
                              artworkPath: resolveTrackArtwork(
                                currentTrack!,
                                trackCoverCache,
                              ),
                            ),
                          ),
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

class _DockPlaylistIdentity extends StatelessWidget {
  const _DockPlaylistIdentity({required this.folder, required this.coverPaths});

  final FolderSummary folder;
  final List<String> coverPaths;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PlaylistPlaybackCover(coverPaths: coverPaths, size: 64),
        const SizedBox(width: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${folder.trackCount} tracks',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DockCurrentTrack extends StatelessWidget {
  const _DockCurrentTrack({required this.track, required this.artworkPath});

  final Track track;
  final String? artworkPath;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Artwork(path: artworkPath, size: 58, icon: Icons.music_note),
      ],
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
    required this.primaryButtonSize,
    required this.secondaryButtonSize,
    required this.shuffleButtonSize,
    required this.gap,
  });

  final bool playbackActive;
  final bool playing;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffleAll;
  final VoidCallback? onPrevious;
  final VoidCallback? onTogglePlayback;
  final VoidCallback? onNext;
  final double primaryButtonSize;
  final double secondaryButtonSize;
  final double shuffleButtonSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final playAction = playbackActive ? onTogglePlayback : onPlayAll;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PlaylistDockIconButton(
          tooltip: 'Previous',
          icon: Icons.skip_previous_rounded,
          onPressed: playbackActive ? onPrevious : null,
          size: secondaryButtonSize,
          iconSize: secondaryButtonSize * 0.45,
        ),
        SizedBox(width: gap),
        _PlaylistDockIconButton(
          tooltip: playbackActive && playing ? 'Pause' : 'Play',
          icon: playbackActive && playing
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          onPressed: playAction,
          prominent: true,
          size: primaryButtonSize,
          iconSize: primaryButtonSize * 0.46,
        ),
        SizedBox(width: gap),
        _PlaylistDockIconButton(
          tooltip: 'Next',
          icon: Icons.skip_next_rounded,
          onPressed: playbackActive ? onNext : null,
          size: secondaryButtonSize,
          iconSize: secondaryButtonSize * 0.45,
        ),
        SizedBox(width: gap),
        _PlaylistDockIconButton(
          tooltip: 'Shuffle',
          icon: Icons.shuffle_rounded,
          onPressed: onShuffleAll,
          size: shuffleButtonSize,
          iconSize: shuffleButtonSize * 0.44,
          accent: true,
        ),
      ],
    );
  }
}

class _PlaylistDockIconButton extends StatelessWidget {
  const _PlaylistDockIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.size,
    required this.iconSize,
    this.prominent = false,
    this.accent = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final bool prominent;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = prominent
        ? _playlistControlAccent
        : accent
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.20);
    final foregroundColor = prominent
        ? const Color(0xff07110f)
        : accent
        ? _playlistControlAccent
        : Colors.white.withValues(alpha: 0.95);
    return IconButton.filled(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: iconSize,
      style: IconButton.styleFrom(
        fixedSize: Size.square(size),
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_playlistDockRadius),
        ),
      ),
      icon: Icon(icon),
    );
  }
}

class _PlaylistPlaybackTable extends StatelessWidget {
  const _PlaylistPlaybackTable({
    required this.tracks,
    required this.trackCoverCache,
    required this.currentTrack,
    required this.playing,
    required this.favoriteTrackPaths,
    required this.onPlayTrack,
    required this.onToggleFavoriteTrack,
  });

  final List<Track> tracks;
  final Map<String, String?> trackCoverCache;
  final Track? currentTrack;
  final bool playing;
  final Set<String> favoriteTrackPaths;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track>? onToggleFavoriteTrack;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showArtist = constraints.maxWidth >= 520;
        final showAlbum = constraints.maxWidth >= 620;
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
                    favorite: favoriteTrackPaths.contains(track.path),
                    onTap: () => onPlayTrack(track),
                    onToggleFavorite: onToggleFavoriteTrack == null
                        ? null
                        : () => onToggleFavoriteTrack!(track),
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
          const SizedBox(width: 8),
          const SizedBox(width: 44),
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
    required this.favorite,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final int index;
  final Track track;
  final String? artworkPath;
  final bool selected;
  final bool playing;
  final bool showArtist;
  final bool showAlbum;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavorite;

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
              const SizedBox(width: 8),
              if (onToggleFavorite == null)
                const SizedBox(width: 44)
              else
                IconButton(
                  tooltip: favorite
                      ? 'Remove from favorites'
                      : 'Add to favorites',
                  onPressed: onToggleFavorite,
                  icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
                  color: favorite ? Colors.redAccent : secondary,
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
