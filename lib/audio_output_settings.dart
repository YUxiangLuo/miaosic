import 'package:media_kit/media_kit.dart';

enum AudioOutputMode {
  systemServer('system_server'),
  directAlsa('direct_alsa');

  const AudioOutputMode(this.dbValue);

  final String dbValue;

  static AudioOutputMode fromDb(String? value, {required String deviceName}) {
    for (final mode in AudioOutputMode.values) {
      if (mode.dbValue == value) {
        return mode;
      }
    }
    if (deviceName.startsWith('alsa/')) {
      return AudioOutputMode.directAlsa;
    }
    return AudioOutputMode.systemServer;
  }
}

class AudioOutputSettings {
  const AudioOutputSettings({
    this.mode = AudioOutputMode.systemServer,
    required this.deviceName,
    required this.deviceDescription,
    this.lockVolumeTo100 = false,
    this.disableReplayGain = false,
    this.preferGapless = false,
  });

  const AudioOutputSettings.defaults()
    : mode = AudioOutputMode.directAlsa,
      deviceName = autoDeviceName,
      deviceDescription = '',
      lockVolumeTo100 = true,
      disableReplayGain = true,
      preferGapless = true;

  static const autoDeviceName = 'auto';

  final AudioOutputMode mode;
  final String deviceName;
  final String deviceDescription;
  final bool lockVolumeTo100;
  final bool disableReplayGain;
  final bool preferGapless;

  bool get isAuto => deviceName == autoDeviceName;
  bool get isDirectAlsa => mode == AudioOutputMode.directAlsa;

  AudioOutputSettings normalized() {
    final normalizedName = deviceName.trim();
    final nextDeviceName = normalizedName.isEmpty
        ? autoDeviceName
        : normalizedName;
    return AudioOutputSettings(
      mode: mode,
      deviceName:
          mode == AudioOutputMode.directAlsa &&
              nextDeviceName != autoDeviceName &&
              !nextDeviceName.startsWith('alsa/')
          ? autoDeviceName
          : nextDeviceName,
      deviceDescription: deviceDescription.trim(),
      lockVolumeTo100: lockVolumeTo100,
      disableReplayGain: disableReplayGain,
      preferGapless: preferGapless,
    );
  }

  Map<String, Object?> toJson() {
    final normalized = this.normalized();
    return {
      'mode': normalized.mode.dbValue,
      'device_name': normalized.deviceName,
      'device_description': normalized.deviceDescription,
      'lock_volume_to_100': normalized.lockVolumeTo100,
      'disable_replay_gain': normalized.disableReplayGain,
      'prefer_gapless': normalized.preferGapless,
    };
  }

  static AudioOutputSettings fromJson(Map<String, Object?> json) {
    final defaults = const AudioOutputSettings.defaults();
    final deviceName = json['device_name'] as String? ?? autoDeviceName;
    return AudioOutputSettings(
      mode: AudioOutputMode.fromDb(
        json['mode'] as String?,
        deviceName: deviceName,
      ),
      deviceName: deviceName,
      deviceDescription: json['device_description'] as String? ?? '',
      lockVolumeTo100:
          json['lock_volume_to_100'] as bool? ?? defaults.lockVolumeTo100,
      disableReplayGain:
          json['disable_replay_gain'] as bool? ?? defaults.disableReplayGain,
      preferGapless: json['prefer_gapless'] as bool? ?? defaults.preferGapless,
    ).normalized();
  }

  factory AudioOutputSettings.fromDevice(
    AudioDevice device, {
    AudioOutputMode? mode,
    AudioOutputSettings? base,
  }) {
    final defaults = base ?? const AudioOutputSettings.defaults();
    return AudioOutputSettings(
      mode:
          mode ??
          (device.name.startsWith('alsa/')
              ? AudioOutputMode.directAlsa
              : AudioOutputMode.systemServer),
      deviceName: device.name,
      deviceDescription: device.description,
      lockVolumeTo100: defaults.lockVolumeTo100,
      disableReplayGain: defaults.disableReplayGain,
      preferGapless: defaults.preferGapless,
    ).normalized();
  }

  AudioOutputSettings copyWith({
    AudioOutputMode? mode,
    String? deviceName,
    String? deviceDescription,
    bool? lockVolumeTo100,
    bool? disableReplayGain,
    bool? preferGapless,
  }) {
    return AudioOutputSettings(
      mode: mode ?? this.mode,
      deviceName: deviceName ?? this.deviceName,
      deviceDescription: deviceDescription ?? this.deviceDescription,
      lockVolumeTo100: lockVolumeTo100 ?? this.lockVolumeTo100,
      disableReplayGain: disableReplayGain ?? this.disableReplayGain,
      preferGapless: preferGapless ?? this.preferGapless,
    ).normalized();
  }
}
