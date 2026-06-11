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
      deviceName: 'pipewire/alsa_output.usb-dac',
      deviceDescription: 'USB DAC',
    );

    final loaded = AudioOutputSettings.fromJson(settings.toJson());

    expect(loaded.deviceName, settings.deviceName);
    expect(loaded.deviceDescription, settings.deviceDescription);
  });

  test('creates settings from an audio device', () {
    final settings = AudioOutputSettings.fromDevice(
      const AudioDevice('pipewire/dac', 'External DAC'),
    );

    expect(settings.deviceName, 'pipewire/dac');
    expect(settings.deviceDescription, 'External DAC');
  });
}
