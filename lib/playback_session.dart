import 'dart:math' as math;

import 'models.dart';

/// One immutable playback selection, including its source and actual play order.
class PlaybackSession {
  PlaybackSession._({
    required this.kind,
    required this.folderPath,
    required this.tracks,
    required this.queue,
    required this.index,
    required this.shuffled,
  });

  factory PlaybackSession.start({
    LastPlaybackKind? kind,
    String folderPath = '',
    required List<Track> tracks,
    Track? startTrack,
    List<Track>? queue,
    bool shuffled = false,
    math.Random? random,
  }) {
    final order = List<Track>.of(queue ?? tracks);
    if (order.isEmpty) throw ArgumentError('A playback session needs tracks');
    if (shuffled && queue == null) order.shuffle(random);
    final index = order.indexWhere((track) => track.path == startTrack?.path);
    return PlaybackSession._(
      kind: kind,
      folderPath: folderPath,
      tracks: List.unmodifiable(tracks),
      queue: List.unmodifiable(order),
      index: index < 0 ? 0 : index,
      shuffled: shuffled,
    );
  }

  final LastPlaybackKind? kind;
  final String folderPath;
  final List<Track> tracks;
  final List<Track> queue;
  final int index;
  final bool shuffled;

  Track get currentTrack => queue[index];

  PlaybackSession at(int nextIndex) {
    RangeError.checkValidIndex(nextIndex, queue);
    return PlaybackSession._(
      kind: kind,
      folderPath: folderPath,
      tracks: tracks,
      queue: queue,
      index: nextIndex,
      shuffled: shuffled,
    );
  }

  PlaybackSession? retainTracks(bool Function(Track) keep) {
    final remaining = queue.where(keep).toList(growable: false);
    if (remaining.length == queue.length) return this;
    return withQueue(remaining);
  }

  PlaybackSession? withQueue(List<Track> nextQueue) {
    final nextIndex = nextQueue.indexWhere(
      (track) => track.path == currentTrack.path,
    );
    if (nextIndex < 0) return null;
    final paths = nextQueue.map((track) => track.path).toSet();
    return PlaybackSession._(
      kind: kind,
      folderPath: folderPath,
      tracks: List.unmodifiable(
        tracks.where((track) => paths.contains(track.path)),
      ),
      queue: List.unmodifiable(nextQueue),
      index: nextIndex,
      shuffled: shuffled,
    );
  }

  LastPlaybackState? savedState({required bool playing}) {
    final source = kind;
    if (source == null) return null;
    return LastPlaybackState(
      kind: source,
      folderPath: folderPath,
      trackPath: currentTrack.path,
      playing: playing,
      shuffled: shuffled,
    );
  }
}

String lastPlaybackStateKey(LastPlaybackState state) =>
    '${state.kind.dbValue}\n${state.folderPath}\n${state.trackPath}\n${state.playing}\n${state.shuffled}';
