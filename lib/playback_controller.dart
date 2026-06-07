import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import 'models.dart';

class PlaybackController extends ChangeNotifier {
  PlaybackController() {
    _playingSub = _player.stream.playing.listen((playing) {
      _playing = playing;
      notifyListeners();
    });
    _completedSub = _player.stream.completed.listen((completed) {
      if (completed) {
        unawaited(playNextFromQueue());
      }
    });
    _positionSub = _player.stream.position.listen((position) {
      _position = position;
      notifyListeners();
    });
    _durationSub = _player.stream.duration.listen((duration) {
      _duration = duration;
      notifyListeners();
    });
  }

  final Player _player = Player();

  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<bool> _completedSub;
  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration> _durationSub;

  Track? _currentTrack;
  List<Track> _queue = const [];
  int _queueIndex = -1;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  Track? get currentTrack => _currentTrack;
  bool get playing => _playing;
  Duration get position => _position;
  Duration get duration => _duration;

  bool isCurrentQueue(List<Track> queue) {
    final current = _currentTrack;
    if (current == null ||
        _queueIndex < 0 ||
        _queueIndex >= _queue.length ||
        _queue.length != queue.length ||
        _queue[_queueIndex].path != current.path) {
      return false;
    }
    for (var i = 0; i < queue.length; i += 1) {
      if (_queue[i].path != queue[i].path) {
        return false;
      }
    }
    return true;
  }

  Future<void> playQueueFrom(List<Track> queue, Track track) async {
    await _openQueueFrom(queue, track, play: true);
  }

  Future<void> restoreQueueFrom(
    List<Track> queue,
    Track track, {
    required bool play,
  }) async {
    await _openQueueFrom(queue, track, play: play);
  }

  Future<void> _openQueueFrom(
    List<Track> queue,
    Track track, {
    required bool play,
  }) async {
    if (queue.isEmpty) {
      return;
    }
    final index = queue.indexWhere((candidate) => candidate.path == track.path);
    final nextIndex = index < 0 ? 0 : index;
    await _playQueueAt(List.unmodifiable(queue), nextIndex, play: play);
  }

  Future<void> togglePlayPause(List<Track> defaultQueue) async {
    if (_currentTrack == null) {
      final first = defaultQueue.isEmpty ? null : defaultQueue.first;
      if (first != null) {
        await playQueueFrom(defaultQueue, first);
      }
      return;
    }
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> skip(int delta, List<Track> defaultQueue) async {
    if (_queue.isNotEmpty && _queueIndex >= 0) {
      await playQueueAt(_queueIndex + delta);
      return;
    }
    if (defaultQueue.isEmpty) {
      return;
    }
    final current = _currentTrack;
    final currentIndex = current == null
        ? -1
        : defaultQueue.indexWhere((track) => track.path == current.path);
    final nextIndex = currentIndex < 0
        ? 0
        : (currentIndex + delta).clamp(0, defaultQueue.length - 1);
    await playQueueFrom(defaultQueue, defaultQueue[nextIndex]);
  }

  Future<void> playNextFromQueue() async {
    if (_queue.isEmpty || _queueIndex < 0) {
      return;
    }
    final nextIndex = _queueIndex + 1;
    if (nextIndex >= _queue.length) {
      return;
    }
    await playQueueAt(nextIndex);
  }

  Future<void> playQueueAt(int index) async {
    if (index < 0 || index >= _queue.length) {
      return;
    }
    await _playQueueAt(_queue, index, play: true);
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> stopIfCurrentRemoved(Iterable<String> removedPaths) async {
    final current = _currentTrack;
    if (current == null || !removedPaths.contains(current.path)) {
      return;
    }
    _queue = const [];
    _queueIndex = -1;
    _currentTrack = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();
    await _player.stop();
  }

  Future<void> _playQueueAt(
    List<Track> queue,
    int index, {
    required bool play,
  }) async {
    final track = queue[index];
    _queue = queue;
    _queueIndex = index;
    _currentTrack = track;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();
    await _player.open(Media(track.path), play: play);
  }

  @override
  void dispose() {
    unawaited(_playingSub.cancel());
    unawaited(_completedSub.cancel());
    unawaited(_positionSub.cancel());
    unawaited(_durationSub.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }
}
