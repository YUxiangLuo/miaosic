import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:miaosic/audio_output_settings.dart';

void main() {
  test('normalizes blank device names to system default', () {
    const settings = AudioOutputSettings(
      deviceName: '  ',
      deviceDescription: ' USB DAC ',
    );

    final normalized = settings.normalized();

    expect(normalized.deviceName, AudioOutputSettings.autoDeviceName);
    expect(normalized.deviceDescription, 'USB DAC');
    expect(normalized.isAuto, isTrue);
  });

  test('round trips through json', () {
    const settings = AudioOutputSettings(
      mode: AudioOutputMode.systemServer,
      deviceName: 'pipewire/alsa_output.usb-dac',
      deviceDescription: 'USB DAC',
    );

    final loaded = AudioOutputSettings.fromJson(settings.toJson());

    expect(loaded.deviceName, settings.deviceName);
    expect(loaded.deviceDescription, settings.deviceDescription);
    expect(loaded.mode, AudioOutputMode.systemServer);
    expect(loaded.lockVolumeTo100, isFalse);
  });

  test('creates settings from an audio device', () {
    final settings = AudioOutputSettings.fromDevice(
      const AudioDevice('pipewire/dac', 'External DAC'),
    );

    expect(settings.deviceName, 'pipewire/dac');
    expect(settings.deviceDescription, 'External DAC');
    expect(settings.mode, AudioOutputMode.systemServer);
  });

  test('defaults to direct ALSA with audiophile options enabled', () {
    const settings = AudioOutputSettings.defaults();

    expect(settings.mode, AudioOutputMode.directAlsa);
    expect(settings.lockVolumeTo100, isTrue);
    expect(settings.disableReplayGain, isTrue);
    expect(settings.preferGapless, isTrue);
  });

  test('infers direct ALSA mode for legacy ALSA records', () {
    final loaded = AudioOutputSettings.fromJson(const {
      'device_name': 'alsa/sysdefault:CARD=OTG',
      'device_description': 'USB DAC',
    });

    expect(loaded.mode, AudioOutputMode.directAlsa);
    expect(loaded.deviceName, 'alsa/sysdefault:CARD=OTG');
  });

  test('direct ALSA mode rejects non ALSA device names', () {
    const settings = AudioOutputSettings(
      mode: AudioOutputMode.directAlsa,
      deviceName: 'pipewire/dac',
      deviceDescription: 'USB DAC',
    );

    expect(
      settings.normalized().deviceName,
      AudioOutputSettings.autoDeviceName,
    );
  });
}
