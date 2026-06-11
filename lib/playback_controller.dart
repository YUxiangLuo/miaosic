import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import 'audio_output_settings.dart';
import 'models.dart';

typedef MpvPropertySetter =
    Future<void> Function(String property, String value);
typedef MpvPropertyGetter = Future<String> Function(String property);

class PlaybackController extends ChangeNotifier {
  PlaybackController({
    Player? player,
    MpvPropertySetter? setMpvProperty,
    MpvPropertyGetter? getMpvProperty,
  }) : _player = player ?? Player(),
       _setMpvPropertyOverride = setMpvProperty,
       _getMpvPropertyOverride = getMpvProperty {
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
    _audioParamsSub = _player.stream.audioParams.listen((params) {
      _audioParams = params;
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
    _audioDevice = _player.state.audioDevice;
    _audioDevices = _normalizeAudioDevices(_player.state.audioDevices);
    _audioParams = _player.state.audioParams;
  }

  static const _autoDevice = AudioDevice(
    AudioOutputSettings.autoDeviceName,
    '',
  );

  final Player _player;
  final MpvPropertySetter? _setMpvPropertyOverride;
  final MpvPropertyGetter? _getMpvPropertyOverride;

  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<bool> _completedSub;
  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration> _durationSub;
  late final StreamSubscription<AudioParams> _audioParamsSub;
  late final StreamSubscription<AudioDevice> _audioDeviceSub;
  late final StreamSubscription<List<AudioDevice>> _audioDevicesSub;

  Track? _currentTrack;
  List<Track> _queue = const [];
  int _queueIndex = -1;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  AudioParams _audioParams = const AudioParams();
  AudioDevice _audioDevice = _autoDevice;
  List<AudioDevice> _audioDevices = const [_autoDevice];
  AudioOutputSettings _preferredAudioOutputSettings =
      const AudioOutputSettings.defaults();
  String? _audioOutputWarning;
  String? _audioOutputError;
  final Map<String, String> _forcedMpvPropertyRestoreValues = {};
  bool _restoringPreferredAudioDevice = false;
  bool _disposed = false;

  Track? get currentTrack => _currentTrack;
  bool get playing => _playing;
  Duration get position => _position;
  Duration get duration => _duration;
  AudioParams get audioParams => _audioParams;
  AudioDevice get audioDevice => _audioDevice;
  List<AudioDevice> get audioDevices => _audioDevices;
  AudioOutputSettings get preferredAudioOutputSettings =>
      _preferredAudioOutputSettings;
  String? get audioOutputWarning => _audioOutputWarning;
  String? get audioOutputError => _audioOutputError;

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
      final propertyWarning = await _applyExperimentalAudioProperties(
        normalized,
      );
      _syncAudioOutputWarning();
      _setAudioPropertyWarningIfRelevant(propertyWarning);
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
    return applyAudioOutputSettings(
      AudioOutputSettings.fromDevice(
        device,
        base: _preferredAudioOutputSettings,
      ),
    );
  }

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
            unawaited(
              _applyExperimentalAudioProperties(
                _preferredAudioOutputSettings,
              ).then((warning) {
                if (_disposed) {
                  return;
                }
                _setAudioPropertyWarningIfRelevant(warning);
                notifyListeners();
              }),
            );
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

  Future<String?> _applyExperimentalAudioProperties(
    AudioOutputSettings settings,
  ) async {
    final failures = <String>[];
    Future<bool> setProperty(String property, String value) async {
      try {
        await _setNativeMpvProperty(property, value);
        return true;
      } catch (error) {
        failures.add('$property: $error');
        return false;
      }
    }

    await _applyManagedMpvProperty(
      property: 'volume',
      enabled: settings.lockVolumeTo100,
      enabledValue: '100',
      defaultRestoreValue: '100',
      setProperty: setProperty,
    );
    await _applyManagedMpvProperty(
      property: 'replaygain',
      enabled: settings.disableReplayGain,
      enabledValue: 'no',
      defaultRestoreValue: 'no',
      setProperty: setProperty,
    );
    await _applyManagedMpvProperty(
      property: 'gapless-audio',
      enabled: settings.preferGapless,
      enabledValue: 'yes',
      defaultRestoreValue: 'weak',
      setProperty: setProperty,
    );

    if (failures.isEmpty) {
      return null;
    }
    return 'Some audiophile options were not applied: ${failures.join('; ')}';
  }

  void _setAudioPropertyWarningIfRelevant(String? warning) {
    if (warning != null && _audioOutputWarning == null) {
      _audioOutputWarning = warning;
    }
  }

  Future<void> _applyManagedMpvProperty({
    required String property,
    required bool enabled,
    required String enabledValue,
    required String defaultRestoreValue,
    required Future<bool> Function(String property, String value) setProperty,
  }) async {
    if (enabled) {
      final hadRestoreValue = _forcedMpvPropertyRestoreValues.containsKey(
        property,
      );
      if (!hadRestoreValue) {
        final currentValue = await _getNativeMpvPropertyOrDefault(
          property,
          defaultRestoreValue,
        );
        _forcedMpvPropertyRestoreValues[property] = currentValue;
      }
      final applied = await setProperty(property, enabledValue);
      if (!applied && !hadRestoreValue) {
        _forcedMpvPropertyRestoreValues.remove(property);
      }
      return;
    }

    final restoreValue = _forcedMpvPropertyRestoreValues[property];
    if (restoreValue == null) {
      return;
    }
    final restored = await setProperty(property, restoreValue);
    if (restored) {
      _forcedMpvPropertyRestoreValues.remove(property);
    }
  }

  Future<void> _setNativeMpvProperty(String property, String value) async {
    final override = _setMpvPropertyOverride;
    if (override != null) {
      await override(property, value);
      return;
    }
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty(property, value);
      return;
    }
    throw UnsupportedError('native mpv properties are not available');
  }

  Future<String> _getNativeMpvPropertyOrDefault(
    String property,
    String defaultValue,
  ) async {
    try {
      final override = _getMpvPropertyOverride;
      if (override != null) {
        final value = await override(property);
        return value.trim().isEmpty ? defaultValue : value;
      }
      final platform = _player.platform;
      if (platform is NativePlayer) {
        final value = await platform.getProperty(property);
        return value.trim().isEmpty ? defaultValue : value;
      }
    } catch (_) {
      // Best effort: restoration still resets to mpv's documented default.
    }
    return defaultValue;
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
    unawaited(_audioParamsSub.cancel());
    unawaited(_audioDeviceSub.cancel());
    unawaited(_audioDevicesSub.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }
}
