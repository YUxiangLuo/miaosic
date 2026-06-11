import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'rust_audio_player.dart';

class PlaybackController extends ChangeNotifier {
  PlaybackController() {
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      unawaited(_pollState());
    });
  }

  final RustAudioPlayer? _player = RustAudioPlayer.tryLoad();
  late final Timer _pollTimer;

  Track? _currentTrack;
  List<Track> _queue = const [];
  int _queueIndex = -1;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _completedSeq = 0;
  bool _polling = false;
  bool _reportedBackendUnavailable = false;
  String? _lastPollError;

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
    final toggled = _playing
        ? _runPlaybackOperation('pause', (player) => player.pause())
        : _runPlaybackOperation('play', (player) => player.play());
    if (!toggled) {
      return;
    }
    _playing = !_playing;
    notifyListeners();
    await _pollState();
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

  Future<void> seek(Duration position) async {
    final didSeek = _runPlaybackOperation(
      'seek',
      (player) => player.seek(position),
    );
    if (!didSeek) {
      return;
    }
    _position = position;
    notifyListeners();
    await _pollState();
  }

  Future<void> stopIfCurrentRemoved(Iterable<String> removedPaths) async {
    final current = _currentTrack;
    if (current == null || !removedPaths.contains(current.path)) {
      return;
    }
    _queue = const [];
    _queueIndex = -1;
    _currentTrack = null;
    _playing = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();
    _runPlaybackOperation('stop', (player) => player.stop());
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
    _playing = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();

    final opened = _runPlaybackOperation(
      'open',
      (player) => player.open(track.path, play: play),
    );
    if (!opened) {
      return;
    }
    await _pollState(resetCompletionBaseline: true);
  }

  Future<void> _pollState({bool resetCompletionBaseline = false}) async {
    final player = _player;
    if (player == null || _polling) {
      return;
    }
    _polling = true;
    var shouldAdvance = false;
    try {
      final state = player.state();
      _lastPollError = null;
      final previousCompletedSeq = _completedSeq;
      _completedSeq = state.completedSeq;
      shouldAdvance =
          !resetCompletionBaseline &&
          _currentTrack != null &&
          state.completedSeq > previousCompletedSeq;
      _applyState(state);
    } catch (error, stackTrace) {
      final message = error.toString();
      if (_lastPollError != message) {
        _lastPollError = message;
        debugPrint('Rust playback state poll failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    } finally {
      _polling = false;
    }
    if (shouldAdvance) {
      await playNextFromQueue();
    }
  }

  void _applyState(RustPlaybackState state) {
    final changed =
        _playing != state.playing ||
        _position != state.position ||
        _duration != state.duration;
    _playing = state.playing;
    _position = state.position;
    _duration = state.duration;
    if (changed) {
      notifyListeners();
    }
  }

  bool _runPlaybackOperation(
    String operation,
    void Function(RustAudioPlayer player) action,
  ) {
    final player = _backend;
    if (player == null) {
      return false;
    }
    try {
      action(player);
      return true;
    } catch (error, stackTrace) {
      debugPrint('Rust playback $operation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  RustAudioPlayer? get _backend {
    final player = _player;
    if (player == null && !_reportedBackendUnavailable) {
      _reportedBackendUnavailable = true;
      debugPrint(
        'Rust playback backend is unavailable. Build native/music_core first.',
      );
    }
    return player;
  }

  @override
  void dispose() {
    _pollTimer.cancel();
    final player = _player;
    if (player != null) {
      try {
        player.stop();
      } catch (_) {
        // The app is tearing down; there is no user-visible recovery here.
      }
    }
    super.dispose();
  }
}
