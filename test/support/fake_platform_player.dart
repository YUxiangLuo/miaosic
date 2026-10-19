import 'dart:async';

import 'package:media_kit/media_kit.dart';

class FakePlatformPlayer extends PlatformPlayer {
  FakePlatformPlayer({this.devices = const [AudioDevice('auto', '')]})
    : super(configuration: const PlayerConfiguration()) {
    state = state.copyWith(
      audioDevice: const AudioDevice('auto', ''),
      audioDevices: devices,
    );
    completer.complete();
  }

  final List<AudioDevice> devices;
  final List<AudioDevice> selectedDevices = [];
  bool failNextDeviceSwitch = false;
  bool failNextOpen = false;
  bool failBlockedOpen = false;
  int playFailuresRemaining = 0;
  int openCount = 0;
  int stopCount = 0;
  Completer<void>? blockNextDeviceSwitch;
  Completer<void>? blockNextOpen;
  Future<void> _deviceSwitchQueue = Future.value();

  void emitDevices(List<AudioDevice> nextDevices) {
    state = state.copyWith(audioDevices: nextDevices);
    audioDevicesController.add(nextDevices);
  }

  Future<void> waitForDeviceSwitches() => _deviceSwitchQueue;

  void emitPlaybackState({
    required bool playing,
    required Duration position,
    required Duration duration,
  }) {
    state = state.copyWith(
      playing: playing,
      position: position,
      duration: duration,
    );
    playingController.add(playing);
    positionController.add(position);
    durationController.add(duration);
  }

  void emitError(String message) {
    errorController.add(message);
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    openCount += 1;
    final blocker = blockNextOpen;
    blockNextOpen = null;
    if (blocker != null) {
      await blocker.future;
      if (failBlockedOpen) {
        failBlockedOpen = false;
        throw StateError('open failed');
      }
    }
    if (failNextOpen) {
      failNextOpen = false;
      throw StateError('open failed');
    }
    _setPlaying(play);
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    _setPlaying(false);
  }

  @override
  Future<void> play() async {
    if (playFailuresRemaining > 0) {
      playFailuresRemaining -= 1;
      throw StateError('play failed');
    }
    _setPlaying(true);
  }

  @override
  Future<void> pause() async => _setPlaying(false);

  @override
  Future<void> seek(Duration position) async {
    state = state.copyWith(position: position);
    positionController.add(position);
  }

  void _setPlaying(bool playing) {
    state = state.copyWith(playing: playing);
    playingController.add(playing);
  }

  @override
  Future<void> setAudioDevice(AudioDevice audioDevice) {
    final switchTask = _deviceSwitchQueue.then((_) async {
      if (failNextDeviceSwitch) {
        failNextDeviceSwitch = false;
        throw StateError('switch failed');
      }
      selectedDevices.add(audioDevice);
      final blocker = blockNextDeviceSwitch;
      blockNextDeviceSwitch = null;
      if (blocker != null) {
        await blocker.future;
      }
      state = state.copyWith(audioDevice: audioDevice);
      audioDeviceController.add(audioDevice);
    });
    _deviceSwitchQueue = switchTask.catchError((_) {});
    return switchTask;
  }
}
