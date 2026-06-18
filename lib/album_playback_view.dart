import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'library_formatters.dart';
import 'library_widgets.dart';
import 'models.dart';

part 'album_playback_artwork.dart';
part 'album_playback_background.dart';
part 'album_playback_dock.dart';
part 'album_track_list.dart';

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
const _albumDiscMorphDuration = Duration(milliseconds: 520);
const _albumDiscRotationDuration = Duration(seconds: 18);
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

class AlbumPlaybackNowPlaying {
  const AlbumPlaybackNowPlaying({
    required this.coverArtPath,
    required this.playing,
  });

  final String? coverArtPath;
  final bool playing;
}

class AlbumPlaybackView extends StatefulWidget {
  const AlbumPlaybackView({
    super.key,
    required this.album,
    required this.tracks,
    required this.currentTrack,
    required this.playing,
    this.nowPlayingAlbum,
    required this.onClose,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
    this.onOpenNowPlayingAlbum,
    required this.canSwitchPreviousAlbum,
    required this.canSwitchNextAlbum,
    required this.onSwitchPreviousAlbum,
    required this.onSwitchNextAlbum,
    this.favoriteTrackPaths = const {},
    required this.onPlayTrack,
    this.onToggleFavoriteTrack,
  });

  final AlbumSummary album;
  final List<Track> tracks;
  final Track? currentTrack;
  final bool playing;
  final AlbumPlaybackNowPlaying? nowPlayingAlbum;
  final VoidCallback onClose;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;
  final VoidCallback? onOpenNowPlayingAlbum;
  final bool canSwitchPreviousAlbum;
  final bool canSwitchNextAlbum;
  final VoidCallback? onSwitchPreviousAlbum;
  final VoidCallback? onSwitchNextAlbum;
  final Set<String> favoriteTrackPaths;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track>? onToggleFavoriteTrack;

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

  void _handleAlbumKeySwitch(LogicalKeyboardKey key) {
    final direction = switch (key) {
      LogicalKeyboardKey.arrowLeft => -1,
      LogicalKeyboardKey.arrowRight => 1,
      _ => 0,
    };
    if (direction == 0) {
      return;
    }

    final canSwitch = direction < 0
        ? widget.canSwitchPreviousAlbum
        : widget.canSwitchNextAlbum;
    final callback = direction < 0
        ? widget.onSwitchPreviousAlbum
        : widget.onSwitchNextAlbum;
    if (!canSwitch || callback == null) {
      return;
    }

    setState(() => _albumTransitionDirection = direction);
    callback();
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        _albumPlaybackConsumedTraversalKeys.contains(event.logicalKey)) {
      _handleAlbumKeySwitch(event.logicalKey);
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
    final albumActive = currentIndex >= 0;
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
                                  active: albumActive,
                                  playing: widget.playing,
                                  favoriteTrackPaths: widget.favoriteTrackPaths,
                                  onAlbumWheel: _handleAlbumWheel,
                                  onPlayTrack: widget.onPlayTrack,
                                  onToggleFavoriteTrack:
                                      widget.onToggleFavoriteTrack,
                                );
                              }
                              return _AlbumPlaybackWideLayout(
                                album: widget.album,
                                tracks: widget.tracks,
                                currentTrack: currentTrack,
                                availableWidth: constraints.maxWidth,
                                availableHeight: constraints.maxHeight,
                                transitionDirection: transitionDirection,
                                active: albumActive,
                                playing: widget.playing,
                                favoriteTrackPaths: widget.favoriteTrackPaths,
                                onAlbumWheel: _handleAlbumWheel,
                                onPlayTrack: widget.onPlayTrack,
                                onToggleFavoriteTrack:
                                    widget.onToggleFavoriteTrack,
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
                    playing: widget.playing,
                    nowPlayingAlbum: widget.nowPlayingAlbum,
                    canPrevious: canPrevious,
                    canNext: canNext,
                    onPrevious: widget.onPrevious,
                    onToggle: _handlePlayPauseCommand,
                    onNext: widget.onNext,
                    onOpenNowPlayingAlbum: widget.onOpenNowPlayingAlbum,
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
    required this.active,
    required this.playing,
    required this.favoriteTrackPaths,
    required this.onAlbumWheel,
    required this.onPlayTrack,
    required this.onToggleFavoriteTrack,
  });

  final AlbumSummary album;
  final List<Track> tracks;
  final Track? currentTrack;
  final double availableWidth;
  final double availableHeight;
  final int transitionDirection;
  final bool active;
  final bool playing;
  final Set<String> favoriteTrackPaths;
  final ValueChanged<PointerScrollEvent> onAlbumWheel;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track>? onToggleFavoriteTrack;

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
            active: active,
            playing: playing,
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
              favoriteTrackPaths: favoriteTrackPaths,
              height: metrics.coverSize,
              onPlayTrack: onPlayTrack,
              onToggleFavoriteTrack: onToggleFavoriteTrack,
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
    required this.active,
    required this.playing,
    required this.favoriteTrackPaths,
    required this.onAlbumWheel,
    required this.onPlayTrack,
    required this.onToggleFavoriteTrack,
  });

  final AlbumSummary album;
  final List<Track> tracks;
  final Track? currentTrack;
  final double coverSize;
  final int transitionDirection;
  final bool active;
  final bool playing;
  final Set<String> favoriteTrackPaths;
  final ValueChanged<PointerScrollEvent> onAlbumWheel;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track>? onToggleFavoriteTrack;

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
            active: active,
            playing: playing,
            onWheel: onAlbumWheel,
          ),
          const SizedBox(height: 28),
          _FadingAlbumTrackList(
            albumFolderPath: album.folderPath,
            tracks: tracks,
            currentTrack: currentTrack,
            playing: playing,
            favoriteTrackPaths: favoriteTrackPaths,
            height: 360,
            onPlayTrack: onPlayTrack,
            onToggleFavoriteTrack: onToggleFavoriteTrack,
          ),
        ],
      ),
    );
  }
}
