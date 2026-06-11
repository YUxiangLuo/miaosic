import 'package:media_kit/media_kit.dart';

class AudioOutputSettings {
  const AudioOutputSettings({
    required this.deviceName,
    required this.deviceDescription,
  });

  const AudioOutputSettings.defaults()
    : deviceName = autoDeviceName,
      deviceDescription = '';

  static const autoDeviceName = 'auto';

  final String deviceName;
  final String deviceDescription;

  bool get isAuto => deviceName == autoDeviceName;

  AudioOutputSettings normalized() {
    final normalizedName = deviceName.trim();
    return AudioOutputSettings(
      deviceName: normalizedName.isEmpty ? autoDeviceName : normalizedName,
      deviceDescription: deviceDescription.trim(),
    );
  }

  Map<String, Object?> toJson() {
    final normalized = this.normalized();
    return {
      'device_name': normalized.deviceName,
      'device_description': normalized.deviceDescription,
    };
  }

  static AudioOutputSettings fromJson(Map<String, Object?> json) {
    return AudioOutputSettings(
      deviceName: json['device_name'] as String? ?? autoDeviceName,
      deviceDescription: json['device_description'] as String? ?? '',
    ).normalized();
  }

  factory AudioOutputSettings.fromDevice(AudioDevice device) {
    return AudioOutputSettings(
      deviceName: device.name,
      deviceDescription: device.description,
    ).normalized();
  }
}
