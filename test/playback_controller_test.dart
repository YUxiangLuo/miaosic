import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:miaosic/audio_output_settings.dart';
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
  Completer<void>? blockNextDeviceSwitch;
  Future<void> _deviceSwitchQueue = Future.value();

  void emitDevices(List<AudioDevice> nextDevices) {
    state = state.copyWith(audioDevices: nextDevices);
    audioDevicesController.add(nextDevices);
  }

  Future<void> waitForDeviceSwitches() => _deviceSwitchQueue;

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
