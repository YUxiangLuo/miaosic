import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import 'audio_output_settings.dart';
import 'models.dart';
import 'playback_session.dart';

class PlaybackController extends ChangeNotifier {
  PlaybackController({Player? player}) : _player = player ?? Player() {
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
    _audioDeviceSub = _player.stream.audioDevice.listen((device) {
      _audioDevice = device;
      notifyListeners();
    });
    _audioDevicesSub = _player.stream.audioDevices.listen((devices) {
      _audioDevices = _normalizeAudioDevices(devices);
      _syncAudioOutputWarning();
      _restorePreferredAudioDeviceIfAvailable();
      notifyListeners();
    });
    _playbackErrorSub = _player.stream.error.listen((error) {
      final message = error.trim();
      if (message.isNotEmpty) {
        _setPlaybackError('Playback error: $message');
      }
    });
    _audioDevice = _player.state.audioDevice;
    _audioDevices = _normalizeAudioDevices(_player.state.audioDevices);
  }

  static const _autoDevice = AudioDevice(
    AudioOutputSettings.autoDeviceName,
    '',
  );

  final Player _player;

  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<bool> _completedSub;
  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration> _durationSub;
  late final StreamSubscription<AudioDevice> _audioDeviceSub;
  late final StreamSubscription<List<AudioDevice>> _audioDevicesSub;
  late final StreamSubscription<String> _playbackErrorSub;

  PlaybackSession? _session;
  PlaybackSession? get session => _session;
  Track? get _currentTrack => _session?.currentTrack;
  List<Track> get _queue => _session?.queue ?? const [];
  int get _queueIndex => _session?.index ?? -1;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  AudioDevice _audioDevice = _autoDevice;
  List<AudioDevice> _audioDevices = const [_autoDevice];
  AudioOutputSettings _preferredAudioOutputSettings =
      const AudioOutputSettings.defaults();
  String? _audioOutputWarning;
  String? _audioOutputError;
  String? _playbackError;
  int _playbackErrorRevision = 0;
  int _latestOpenRequestId = 0;
  _PendingPlaybackOpen? _pendingOpen;
  bool _restoringPreferredAudioDevice = false;
  bool _disposed = false;

  Track? get currentTrack => _currentTrack;
  List<Track> get queue => _queue;
  bool get playing => _playing;
  Duration get position => _position;
  Duration get duration => _duration;
  AudioDevice get audioDevice => _audioDevice;
  List<AudioDevice> get audioDevices => _audioDevices;
  AudioOutputSettings get preferredAudioOutputSettings =>
      _preferredAudioOutputSettings;
  String? get audioOutputWarning => _audioOutputWarning;
  String? get audioOutputError => _audioOutputError;
  String? get playbackError => _playbackError;
  int get playbackErrorRevision => _playbackErrorRevision;

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
    await playSession(
      PlaybackSession.start(tracks: queue, startTrack: track),
      play: play,
    );
  }

  Future<void> playSession(PlaybackSession session, {bool play = true}) =>
      _playQueueAt(session, play: play);

  Future<void> togglePlayPause(List<Track> defaultQueue) async {
    if (_currentTrack == null) {
      final first = defaultQueue.isEmpty ? null : defaultQueue.first;
      if (first != null) {
        await playQueueFrom(defaultQueue, first);
      }
      return;
    }
    _clearPlaybackError(notify: false);
    try {
      if (_playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
    } catch (error) {
      _setPlaybackError('Could not change playback state: $error');
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
    await _playQueueAt(_session!.at(index), play: true);
  }

  Future<void> seek(Duration position) async {
    _clearPlaybackError(notify: false);
    try {
      await _player.seek(position);
    } catch (error) {
      _setPlaybackError('Could not seek: $error');
    }
  }

  void clearPlaybackError() {
    _clearPlaybackError(notify: true);
  }

  Future<void> applyAudioOutputSettings(AudioOutputSettings settings) async {
    final normalized = settings.normalized();
    final previousSettings = _preferredAudioOutputSettings;
    final previousWarning = _audioOutputWarning;
    _preferredAudioOutputSettings = normalized;
    _audioOutputError = null;
    _syncAudioOutputWarning();
    final target = _targetDeviceFor(normalized);

    try {
      await _player.setAudioDevice(target);
      _syncAudioOutputWarning();
      _restorePreferredAudioDeviceIfAvailable();
      notifyListeners();
    } catch (error) {
      _preferredAudioOutputSettings = previousSettings;
      _audioOutputWarning = previousWarning;
      _audioOutputError = 'Could not switch audio output: $error';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setAudioOutputDevice(AudioDevice device) {
    return applyAudioOutputSettings(AudioOutputSettings.fromDevice(device));
  }

  Future<void> removeTracksFromQueue(Iterable<String> removedPaths) async {
    final removed = removedPaths.toSet();
    await _retainSessionTracks((_, track) => !removed.contains(track.path));
  }

  /// Apply catalog changes to both the live session and any open rollback state.
  Future<void> reconcileLibrary({
    required Set<String> trackPaths,
    required Set<String> favoritePaths,
  }) => _retainSessionTracks(
    (session, track) =>
        trackPaths.contains(track.path) &&
        (session.kind != LastPlaybackKind.favorites ||
            favoritePaths.contains(track.path)),
  );

  Future<void> _retainSessionTracks(
    bool Function(PlaybackSession, Track) keep,
  ) async {
    final pending = _pendingOpen;
    final previous = pending?.previousSession;
    if (previous != null) {
      pending!.previousSession = previous.retainTracks(
        (track) => keep(previous, track),
      );
    }
    final current = _session;
    if (current == null) return;
    final next = current.retainTracks((track) => keep(current, track));
    if (identical(next, current)) return;
    if (next == null) {
      await stopIfCurrentRemoved([current.currentTrack.path]);
    } else {
      _session = next;
      notifyListeners();
    }
  }

  Future<void> replaceQueueKeepingPosition(List<Track> queue) async {
    final current = _session;
    if (current == null) return;
    final next = current.withQueue(queue);
    if (next == null) {
      await stopIfCurrentRemoved([current.currentTrack.path]);
    } else {
      _session = next;
      notifyListeners();
    }
  }

  Future<void> stopIfCurrentRemoved(Iterable<String> removedPaths) async {
    final current = _currentTrack;
    if (current == null || !removedPaths.contains(current.path)) return;
    _latestOpenRequestId += 1;
    _pendingOpen = null;
    _session = null;
    _playing = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();
    try {
      await _player.stop();
    } catch (error) {
      _setPlaybackError('Could not stop removed track: $error');
    }
  }

  Future<void> _playQueueAt(PlaybackSession next, {required bool play}) async {
    final requestId = ++_latestOpenRequestId;
    final pending = _PendingPlaybackOpen(_session);
    _pendingOpen = pending;
    final previousPosition = _position;
    final previousDuration = _duration;
    final track = next.currentTrack;
    _clearPlaybackError(notify: false);
    _session = next;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();
    try {
      await _player.open(Media(track.path), play: play);
    } catch (error) {
      if (_disposed || requestId != _latestOpenRequestId) return;
      // Catalog changes also prune the rollback session while opening is pending.
      if (pending.hadPreviousSession && pending.previousSession == null) {
        _setPlaybackError('Could not play ${track.fileName}: $error');
        await stopIfCurrentRemoved([track.path]);
        return;
      }
      _session = pending.previousSession;
      _position = previousPosition;
      _duration = previousDuration;
      _setPlaybackError('Could not play ${track.fileName}: $error');
    } finally {
      if (requestId == _latestOpenRequestId) _pendingOpen = null;
    }
  }

  void _setPlaybackError(String message) {
    if (_disposed) {
      return;
    }
    _playbackError = message;
    _playbackErrorRevision += 1;
    notifyListeners();
  }

  void _clearPlaybackError({required bool notify}) {
    if (_playbackError == null) {
      return;
    }
    _playbackError = null;
    if (notify && !_disposed) {
      notifyListeners();
    }
  }

  AudioDevice _targetDeviceFor(AudioOutputSettings settings) {
    if (settings.isAuto) {
      return _autoDevice;
    }
    for (final device in _audioDevices) {
      if (device.name == settings.deviceName) {
        return device;
      }
    }
    return _autoDevice;
  }

  void _restorePreferredAudioDeviceIfAvailable() {
    if (_restoringPreferredAudioDevice ||
        _preferredAudioOutputSettings.isAuto ||
        _audioOutputWarning != null ||
        _audioDevice.name == _preferredAudioOutputSettings.deviceName) {
      return;
    }

    final target = _targetDeviceFor(_preferredAudioOutputSettings);
    if (target.name != _preferredAudioOutputSettings.deviceName) {
      return;
    }

    _restoringPreferredAudioDevice = true;
    unawaited(
      _player
          .setAudioDevice(target)
          .then((_) {
            if (_disposed) {
              return;
            }
            _audioDevice = target;
            _audioOutputError = null;
            _syncAudioOutputWarning();
            notifyListeners();
          })
          .catchError((Object error) {
            if (_disposed) {
              return;
            }
            _audioOutputError = 'Could not switch audio output: $error';
            notifyListeners();
          })
          .whenComplete(() {
            _restoringPreferredAudioDevice = false;
          }),
    );
  }

  void _syncAudioOutputWarning() {
    if (_preferredAudioOutputSettings.isAuto ||
        _audioDevices.any(
          (device) => device.name == _preferredAudioOutputSettings.deviceName,
        )) {
      _audioOutputWarning = null;
      return;
    }
    _audioOutputWarning =
        'Saved audio device is not currently available. Using system default.';
  }

  static List<AudioDevice> _normalizeAudioDevices(List<AudioDevice> devices) {
    final byName = <String, AudioDevice>{_autoDevice.name: _autoDevice};
    for (final device in devices) {
      final name = device.name.trim();
      if (name.isEmpty) {
        continue;
      }
      byName[name] = AudioDevice(name, device.description.trim());
    }
    return List.unmodifiable(byName.values);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_playingSub.cancel());
    unawaited(_completedSub.cancel());
    unawaited(_positionSub.cancel());
    unawaited(_durationSub.cancel());
    unawaited(_audioDeviceSub.cancel());
    unawaited(_audioDevicesSub.cancel());
    unawaited(_playbackErrorSub.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }
}

class _PendingPlaybackOpen {
  _PendingPlaybackOpen(this.previousSession)
    : hadPreviousSession = previousSession != null;

  PlaybackSession? previousSession;
  final bool hadPreviousSession;
}
