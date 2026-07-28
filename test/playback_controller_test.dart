import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:miaosic/audio_output_settings.dart';
import 'package:miaosic/models.dart' as music;
import 'package:miaosic/playback_controller.dart';

void main() {
  test(
    'restores the preferred device if it appears while applying settings',
    () async {
      final platform = _FakePlatformPlayer();
      final controller = PlaybackController(
        player: Player(platformPlayer: platform),
      );
      addTearDown(controller.dispose);

      final blocker = Completer<void>();
      platform.blockNextDeviceSwitch = blocker;

      final apply = controller.applyAudioOutputSettings(
        const AudioOutputSettings(
          deviceName: 'pipewire/dac',
          deviceDescription: 'USB DAC',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(platform.selectedDevices.single.name, 'auto');

      platform.emitDevices(const [
        AudioDevice('auto', ''),
        AudioDevice('pipewire/dac', 'USB DAC'),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.preferredAudioOutputSettings.deviceName,
        'pipewire/dac',
      );

      blocker.complete();
      await apply;
      await platform.waitForDeviceSwitches();

      expect(platform.selectedDevices.first.name, 'auto');
      expect(platform.selectedDevices.last.name, 'pipewire/dac');
      expect(controller.audioOutputWarning, isNull);
      expect(controller.audioOutputError, isNull);
    },
  );

  test('applies an available preferred audio device', () async {
    final platform = _FakePlatformPlayer(
      devices: const [
        AudioDevice('auto', ''),
        AudioDevice('pipewire/dac', 'USB DAC'),
      ],
    );
    final controller = PlaybackController(
      player: Player(platformPlayer: platform),
    );
    addTearDown(controller.dispose);

    await controller.applyAudioOutputSettings(
      const AudioOutputSettings(
        deviceName: 'pipewire/dac',
        deviceDescription: 'USB DAC',
      ),
    );

    expect(platform.selectedDevices.last.name, 'pipewire/dac');
    expect(controller.preferredAudioOutputSettings.deviceName, 'pipewire/dac');
    expect(controller.audioOutputWarning, isNull);
    expect(controller.audioOutputError, isNull);
  });

  test(
    'falls back to system default when preferred device is missing',
    () async {
      final platform = _FakePlatformPlayer();
      final controller = PlaybackController(
        player: Player(platformPlayer: platform),
      );
      addTearDown(controller.dispose);

      await controller.applyAudioOutputSettings(
        const AudioOutputSettings(
          deviceName: 'pipewire/dac',
          deviceDescription: 'USB DAC',
        ),
      );

      expect(platform.selectedDevices.last.name, 'auto');
      expect(
        controller.preferredAudioOutputSettings.deviceName,
        'pipewire/dac',
      );
      expect(
        controller.audioOutputWarning,
        contains('not currently available'),
      );

      platform.emitDevices(const [
        AudioDevice('auto', ''),
        AudioDevice('pipewire/dac', 'USB DAC'),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(platform.selectedDevices.last.name, 'pipewire/dac');
      expect(controller.audioOutputWarning, isNull);
    },
  );

  test('clears restore errors after a later successful restore', () async {
    final platform = _FakePlatformPlayer();
    final controller = PlaybackController(
      player: Player(platformPlayer: platform),
    );
    addTearDown(controller.dispose);

    await controller.applyAudioOutputSettings(
      const AudioOutputSettings(
        deviceName: 'pipewire/dac',
        deviceDescription: 'USB DAC',
      ),
    );
    expect(controller.audioOutputWarning, contains('not currently available'));

    platform.failNextDeviceSwitch = true;
    platform.emitDevices(const [
      AudioDevice('auto', ''),
      AudioDevice('pipewire/dac', 'USB DAC'),
    ]);
    await Future<void>.delayed(Duration.zero);
    await platform.waitForDeviceSwitches();
    await Future<void>.delayed(Duration.zero);

    expect(controller.audioOutputError, contains('switch failed'));

    platform.emitDevices(const [AudioDevice('auto', '')]);
    await Future<void>.delayed(Duration.zero);
    platform.emitDevices(const [
      AudioDevice('auto', ''),
      AudioDevice('pipewire/dac', 'USB DAC'),
    ]);
    await Future<void>.delayed(Duration.zero);
    await platform.waitForDeviceSwitches();
    await Future<void>.delayed(Duration.zero);

    expect(platform.selectedDevices.last.name, 'pipewire/dac');
    expect(controller.audioOutputWarning, isNull);
    expect(controller.audioOutputError, isNull);
  });

  test('keeps previous preferred device when switching fails', () async {
    final platform = _FakePlatformPlayer(
      devices: const [
        AudioDevice('auto', ''),
        AudioDevice('pipewire/dac', 'USB DAC'),
      ],
    );
    final controller = PlaybackController(
      player: Player(platformPlayer: platform),
    );
    addTearDown(controller.dispose);

    platform.failNextDeviceSwitch = true;

    await expectLater(
      controller.applyAudioOutputSettings(
        const AudioOutputSettings(
          deviceName: 'pipewire/dac',
          deviceDescription: 'USB DAC',
        ),
      ),
      throwsStateError,
    );

    expect(
      controller.preferredAudioOutputSettings.deviceName,
      AudioOutputSettings.autoDeviceName,
    );
    expect(controller.audioOutputError, contains('switch failed'));
  });

  test(
    'rolls back the queue and exposes an error when opening fails',
    () async {
      final platform = _FakePlatformPlayer();
      final controller = PlaybackController(
        player: Player(platformPlayer: platform),
      );
      addTearDown(controller.dispose);
      final first = _track('/music/first.flac');
      final second = _track('/music/second.flac');

      await controller.playQueueFrom([first], first);
      platform.failNextOpen = true;
      await controller.playQueueFrom([second], second);

      expect(controller.currentTrack?.path, first.path);
      expect(controller.isCurrentQueue([first]), isTrue);
      expect(controller.playbackError, contains('second.flac'));
      expect(controller.playbackError, contains('open failed'));

      controller.clearPlaybackError();
      expect(controller.playbackError, isNull);
    },
  );

  test('ignores a late failure from a superseded open request', () async {
    final platform = _FakePlatformPlayer();
    final controller = PlaybackController(
      player: Player(platformPlayer: platform),
    );
    addTearDown(controller.dispose);
    final first = _track('/music/first.flac');
    final second = _track('/music/second.flac');
    final third = _track('/music/third.flac');

    await controller.playQueueFrom([first], first);

    final blockedOpen = Completer<void>();
    platform.blockNextOpen = blockedOpen;
    platform.failBlockedOpen = true;
    final supersededRequest = controller.playQueueFrom([second], second);
    await Future<void>.delayed(Duration.zero);

    await controller.playQueueFrom([third], third);
    blockedOpen.complete();
    await supersededRequest;

    expect(controller.currentTrack?.path, third.path);
    expect(controller.isCurrentQueue([third]), isTrue);
    expect(controller.playbackError, isNull);
  });

  test('assigns a new revision to repeated playback failures', () async {
    final platform = _FakePlatformPlayer();
    final controller = PlaybackController(
      player: Player(platformPlayer: platform),
    );
    addTearDown(controller.dispose);
    final track = _track('/music/first.flac');
    await controller.playQueueFrom([track], track);
    platform.playFailuresRemaining = 2;

    await controller.togglePlayPause([track]);
    final firstRevision = controller.playbackErrorRevision;
    final firstError = controller.playbackError;

    await controller.togglePlayPause([track]);

    expect(controller.playbackError, firstError);
    expect(controller.playbackErrorRevision, firstRevision + 1);
  });

  test('surfaces asynchronous backend playback errors', () async {
    final platform = _FakePlatformPlayer();
    final controller = PlaybackController(
      player: Player(platformPlayer: platform),
    );
    addTearDown(controller.dispose);

    platform.emitError('decoder failed');
    await Future<void>.delayed(Duration.zero);

    expect(controller.playbackError, 'Playback error: decoder failed');
  });
}

class _FakePlatformPlayer extends PlatformPlayer {
  _FakePlatformPlayer({this.devices = const [AudioDevice('auto', '')]})
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
  Completer<void>? blockNextDeviceSwitch;
  Completer<void>? blockNextOpen;
  Future<void> _deviceSwitchQueue = Future.value();

  void emitDevices(List<AudioDevice> nextDevices) {
    state = state.copyWith(audioDevices: nextDevices);
    audioDevicesController.add(nextDevices);
  }

  Future<void> waitForDeviceSwitches() => _deviceSwitchQueue;

  void emitError(String message) {
    errorController.add(message);
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
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
  }

  @override
  Future<void> play() async {
    if (playFailuresRemaining > 0) {
      playFailuresRemaining -= 1;
      throw StateError('play failed');
    }
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

music.Track _track(String path) {
  return music.Track(
    path: path,
    folderPath: '/music',
    title: path.split('/').last,
    artist: 'Artist',
    album: 'Album',
    albumArtist: 'Artist',
    trackNumber: 1,
    discNumber: null,
    year: 2026,
    durationMs: 120000,
    sizeBytes: 42,
    modifiedMs: 99,
    coverArtPath: null,
  );
}
