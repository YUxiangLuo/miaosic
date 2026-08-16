import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'favorite_views.dart';
import 'library_screen_selectors.dart';
import 'library_widgets.dart';
import 'models.dart';

const _favoritesPlaybackSpaceActivator = SingleActivator(
  LogicalKeyboardKey.space,
  includeRepeats: false,
);

class FavoritesPlaybackView extends StatelessWidget {
  const FavoritesPlaybackView({
    super.key,
    required this.tracks,
    required this.trackCoverCache,
    required this.currentTrack,
    required this.playbackActive,
    required this.playing,
    required this.onClose,
    this.onOpenNowPlaying,
    required this.onPlayAll,
    required this.onShuffleAll,
    required this.onPrevious,
    required this.onTogglePlayback,
    required this.onNext,
    required this.onPlayTrack,
    required this.onToggleFavorite,
  });

  final List<Track> tracks;
  final Map<String, String?> trackCoverCache;
  final Track? currentTrack;
  final bool playbackActive;
  final bool playing;
  final VoidCallback onClose;
  final VoidCallback? onOpenNowPlaying;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffleAll;
  final VoidCallback? onPrevious;
  final VoidCallback? onTogglePlayback;
  final VoidCallback? onNext;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track> onToggleFavorite;

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      onClose();
      return KeyEventResult.handled;
    }
    if (_favoritesPlaybackSpaceActivator.accepts(
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
    final theme = Theme.of(context);
    final coverPaths = favoriteCoverArtPaths(
      tracks: tracks,
      trackCoverCache: trackCoverCache,
    );
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Material(
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Back to library',
                      onPressed: onClose,
                      icon: const Icon(Icons.keyboard_arrow_down),
                    ),
                    if (onOpenNowPlaying != null) ...[
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Back to now playing',
                        onPressed: onOpenNowPlaying,
                        icon: const Icon(Icons.graphic_eq),
                      ),
                    ],
                    const SizedBox(width: 12),
                    PlaylistCoverCollage(
                      paths: coverPaths,
                      size: 44,
                      radius: 8,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FavoriteTrackList(
                  tracks: tracks,
                  trackCoverCache: trackCoverCache,
                  currentTrack: currentTrack,
                  playbackActive: playbackActive,
                  playing: playing,
                  onPlayAll: onPlayAll,
                  onShuffleAll: onShuffleAll,
                  onPrevious: onPrevious,
                  onTogglePlayback: onTogglePlayback,
                  onNext: onNext,
                  onPlayTrack: onPlayTrack,
                  onToggleFavorite: onToggleFavorite,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
