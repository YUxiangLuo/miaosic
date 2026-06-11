import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'audio_output_settings.dart';
import 'llm_settings.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.llmSettings,
    required this.onSaveLlmSettings,
    required this.audioOutputSettings,
    required this.audioDevices,
    required this.activeAudioDevice,
    required this.onSaveAudioOutputSettings,
    this.audioOutputWarning,
    this.audioOutputError,
    required this.audioParams,
  });

  final LlmSettings llmSettings;
  final Future<void> Function(LlmSettings settings) onSaveLlmSettings;
  final AudioOutputSettings audioOutputSettings;
  final List<AudioDevice> audioDevices;
  final AudioDevice activeAudioDevice;
  final Future<void> Function(AudioOutputSettings settings)
  onSaveAudioOutputSettings;
  final String? audioOutputWarning;
  final String? audioOutputError;
  final AudioParams audioParams;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late LlmServiceFormat _format;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late AudioOutputMode _audioMode;
  late String _audioDeviceName;
  late bool _lockVolumeTo100;
  late bool _disableReplayGain;
  late bool _preferGapless;

  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final settings = widget.llmSettings;
    _format = settings.format;
    _baseUrlController = TextEditingController(text: settings.baseUrl);
    _apiKeyController = TextEditingController(text: settings.apiKey);
    _modelController = TextEditingController(text: settings.model);
    final audioSettings = widget.audioOutputSettings.normalized();
    _audioMode = audioSettings.mode;
    _audioDeviceName = audioSettings.deviceName;
    _lockVolumeTo100 = audioSettings.lockVolumeTo100;
    _disableReplayGain = audioSettings.disableReplayGain;
    _preferGapless = audioSettings.preferGapless;
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _handleFormatChanged(LlmServiceFormat? format) {
    if (format == null || format == _format) {
      return;
    }
    final previousDefault = _format.defaultBaseUrl;
    setState(() {
      _format = format;
      final currentBaseUrl = _baseUrlController.text.trim();
      if (currentBaseUrl.isEmpty || currentBaseUrl == previousDefault) {
        _baseUrlController.text = format.defaultBaseUrl;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onSaveAudioOutputSettings(_selectedAudioOutputSettings());
      await widget.onSaveLlmSettings(
        LlmSettings(
          format: _format,
          baseUrl: _baseUrlController.text,
          apiKey: _apiKeyController.text,
          model: _modelController.text,
        ).normalized(),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _saveError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _close() {
    if (_saving) {
      return;
    }
    Navigator.of(context).pop();
  }

  void _handleAudioDeviceChanged(String? deviceName) {
    if (deviceName == null || deviceName == _audioDeviceName) {
      return;
    }
    setState(() {
      _audioDeviceName = deviceName;
      _saveError = null;
    });
  }

  void _handleAudioModeChanged(AudioOutputMode? mode) {
    if (mode == null || mode == _audioMode) {
      return;
    }
    setState(() {
      _audioMode = mode;
      _audioDeviceName = AudioOutputSettings.autoDeviceName;
      _saveError = null;
    });
  }

  AudioOutputSettings _selectedAudioOutputSettings() {
    if (_audioDeviceName == AudioOutputSettings.autoDeviceName) {
      return AudioOutputSettings(
        mode: _audioMode,
        deviceName: AudioOutputSettings.autoDeviceName,
        deviceDescription: '',
        lockVolumeTo100: _lockVolumeTo100,
        disableReplayGain: _disableReplayGain,
        preferGapless: _preferGapless,
      ).normalized();
    }
    for (final device in _audioDeviceOptions) {
      if (device.name == _audioDeviceName) {
        return AudioOutputSettings.fromDevice(
          device,
          mode: _audioMode,
          base: AudioOutputSettings(
            mode: _audioMode,
            deviceName: _audioDeviceName,
            deviceDescription: device.description,
            lockVolumeTo100: _lockVolumeTo100,
            disableReplayGain: _disableReplayGain,
            preferGapless: _preferGapless,
          ),
        );
      }
    }
    return AudioOutputSettings(
      mode: _audioMode,
      deviceName: _audioDeviceName,
      deviceDescription: widget.audioOutputSettings.deviceDescription,
      lockVolumeTo100: _lockVolumeTo100,
      disableReplayGain: _disableReplayGain,
      preferGapless: _preferGapless,
    ).normalized();
  }

  List<AudioDevice> get _audioDeviceOptions {
    final byName = <String, AudioDevice>{
      AudioOutputSettings.autoDeviceName: const AudioDevice(
        AudioOutputSettings.autoDeviceName,
        '',
      ),
    };
    for (final device in _userFacingAudioDevices(
      widget.audioDevices,
      mode: _audioMode,
    )) {
      final name = device.name.trim();
      if (name.isEmpty) {
        continue;
      }
      byName[name] = AudioDevice(name, device.description.trim());
    }
    if (!byName.containsKey(_audioDeviceName)) {
      byName[_audioDeviceName] = AudioDevice(
        _audioDeviceName,
        widget.audioOutputSettings.deviceDescription,
      );
    }
    return byName.values.toList(growable: false);
  }

  String _audioDeviceLabel(AudioDevice device) {
    if (device.name == AudioOutputSettings.autoDeviceName) {
      return _audioMode == AudioOutputMode.directAlsa
          ? 'No direct DAC selected'
          : 'System default';
    }
    final description = _cleanAudioDeviceDescription(device.description);
    final label = description.isEmpty || description == device.name
        ? _shortAudioDeviceName(device.name)
        : description;
    final backend = _audioBackendLabel(device.name);
    if (backend == null) {
      return label;
    }
    return '$label - $backend';
  }

  String? get _audioOutputMessage {
    return _saveError ?? widget.audioOutputError ?? widget.audioOutputWarning;
  }

  String get _audiophileOptionsSummary {
    final enabled = [
      _lockVolumeTo100,
      _disableReplayGain,
      _preferGapless,
    ].where((option) => option).length;
    return '$enabled of 3 enabled';
  }

  String get _audioParamsLabel {
    final params = widget.audioParams;
    final parts = <String>[
      if (params.format != null && params.format!.isNotEmpty) params.format!,
      if (params.sampleRate != null) '${params.sampleRate} Hz',
      if (params.hrChannels != null && params.hrChannels!.isNotEmpty)
        params.hrChannels!
      else if (params.channels != null && params.channels!.isNotEmpty)
        params.channels!,
    ];
    if (parts.isEmpty) {
      return 'Output: waiting for playback';
    }
    return 'Output: ${parts.join(' / ')}';
  }

  @override
  Widget build(BuildContext context) {
    final audioOutputMessage = _audioOutputMessage;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: Focus(
        autofocus: true,
        child: AlertDialog(
          title: const Text('Settings'),
          contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Audiophile output',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<AudioOutputMode>(
                    initialValue: _audioMode,
                    decoration: const InputDecoration(
                      labelText: 'Output path',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: AudioOutputMode.directAlsa,
                        child: Text('Direct ALSA DAC'),
                      ),
                      DropdownMenuItem(
                        value: AudioOutputMode.systemServer,
                        child: Text('System audio server'),
                      ),
                    ],
                    onChanged: _saving ? null : _handleAudioModeChanged,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _audioDeviceName,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Device',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final device in _audioDeviceOptions)
                        DropdownMenuItem(
                          value: device.name,
                          child: Text(
                            _audioDeviceLabel(device),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _saving ? null : _handleAudioDeviceChanged,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Current: ${_audioDeviceLabel(widget.activeAudioDevice)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _audioParamsLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: const Text('Audiophile options'),
                    subtitle: Text(_audiophileOptionsSummary),
                    children: [
                      SwitchListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        value: _lockVolumeTo100,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Lock volume at 100'),
                        onChanged: _saving
                            ? null
                            : (value) {
                                setState(() => _lockVolumeTo100 = value);
                              },
                      ),
                      SwitchListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        value: _disableReplayGain,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Disable ReplayGain'),
                        onChanged: _saving
                            ? null
                            : (value) {
                                setState(() => _disableReplayGain = value);
                              },
                      ),
                      SwitchListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        value: _preferGapless,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Prefer gapless'),
                        onChanged: _saving
                            ? null
                            : (value) {
                                setState(() => _preferGapless = value);
                              },
                      ),
                    ],
                  ),
                  if (audioOutputMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      audioOutputMessage,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Text(
                    'LLM',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<LlmServiceFormat>(
                    initialValue: _format,
                    decoration: const InputDecoration(
                      labelText: 'Service format',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final format in LlmServiceFormat.values)
                        DropdownMenuItem(
                          value: format,
                          child: Text(format.label),
                        ),
                    ],
                    onChanged: _saving ? null : _handleFormatChanged,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _baseUrlController,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Base URL',
                      hintText: 'https://api.openai.com/v1',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyController,
                    enabled: !_saving,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'API key',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _modelController,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      hintText: 'Provider model name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : _close,
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save, size: 18),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

List<AudioDevice> _userFacingAudioDevices(
  Iterable<AudioDevice> devices, {
  required AudioOutputMode mode,
}) {
  final normalized = _dedupeAudioDevices(devices)
      .where((device) => device.name != AudioOutputSettings.autoDeviceName)
      .toList(growable: false);
  if (mode == AudioOutputMode.directAlsa) {
    return normalized.where(_isUserFacingAlsaDevice).toList(growable: false);
  }

  final pipewireDevices = normalized
      .where((device) => _isConcreteBackendDevice(device.name, 'pipewire'))
      .toList(growable: false);
  if (pipewireDevices.isNotEmpty) {
    return pipewireDevices;
  }

  final pulseDevices = normalized
      .where((device) => _isConcreteBackendDevice(device.name, 'pulse'))
      .toList(growable: false);
  if (pulseDevices.isNotEmpty) {
    return pulseDevices;
  }

  final alsaDevices = normalized
      .where(_isUserFacingAlsaDevice)
      .toList(growable: false);
  if (alsaDevices.isNotEmpty) {
    return alsaDevices;
  }

  return normalized
      .where((device) => !_isBackendDefault(device.name))
      .toList(growable: false);
}

List<AudioDevice> _dedupeAudioDevices(Iterable<AudioDevice> devices) {
  final byName = <String, AudioDevice>{};
  for (final device in devices) {
    final name = device.name.trim();
    if (name.isEmpty) {
      continue;
    }
    byName[name] = AudioDevice(name, device.description.trim());
  }
  return byName.values.toList(growable: false);
}

bool _isConcreteBackendDevice(String name, String backend) {
  return name.startsWith('$backend/');
}

bool _isBackendDefault(String name) {
  return name == 'pipewire' ||
      name == 'pulse' ||
      name == 'alsa' ||
      name == 'jack';
}

bool _isUserFacingAlsaDevice(AudioDevice device) {
  final name = device.name;
  if (!name.startsWith('alsa/')) {
    return false;
  }
  final selector = name.substring('alsa/'.length);
  if (_hiddenAlsaSelectors.contains(selector)) {
    return false;
  }
  return selector.startsWith('sysdefault') ||
      selector.startsWith('front:CARD=') ||
      selector.startsWith('iec958:CARD=') ||
      selector.startsWith('hdmi:CARD=');
}

const _hiddenAlsaSelectors = {
  'default',
  'dmix',
  'dsnoop',
  'jack',
  'lavrate',
  'null',
  'oss',
  'pipewire',
  'pulse',
  'samplerate',
  'speexrate',
  'upmix',
  'usbstream',
  'vdownmix',
};

String _cleanAudioDeviceDescription(String description) {
  return description
      .trim()
      .replaceFirst(
        RegExp(r'\s*\((alsa|jack|pipewire|pulse)\)$', caseSensitive: false),
        '',
      )
      .trim();
}

String _shortAudioDeviceName(String name) {
  final slashIndex = name.indexOf('/');
  if (slashIndex >= 0 && slashIndex + 1 < name.length) {
    return name.substring(slashIndex + 1);
  }
  return name;
}

String? _audioBackendLabel(String name) {
  final slashIndex = name.indexOf('/');
  final backend = slashIndex < 0 ? name : name.substring(0, slashIndex);
  return switch (backend) {
    'pipewire' => 'PipeWire',
    'pulse' => 'PulseAudio',
    'alsa' => 'ALSA',
    'jack' => 'JACK',
    _ => null,
  };
}
