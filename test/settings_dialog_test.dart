import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:miaosic/audio_output_settings.dart';
import 'package:miaosic/llm_settings.dart';
import 'package:miaosic/settings_dialog.dart';

const _systemAudioSettings = AudioOutputSettings(
  mode: AudioOutputMode.systemServer,
  deviceName: AudioOutputSettings.autoDeviceName,
  deviceDescription: '',
);

void main() {
  testWidgets('saves Anthropic-compatible LLM settings', (tester) async {
    LlmSettings? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) {
                      return SettingsDialog(
                        llmSettings: const LlmSettings.defaults(),
                        onSaveLlmSettings: (settings) async {
                          saved = settings;
                        },
                        audioOutputSettings:
                            const AudioOutputSettings.defaults(),
                        audioDevices: const [AudioDevice('auto', '')],
                        activeAudioDevice: const AudioDevice('auto', ''),
                        audioParams: const AudioParams(),
                        onSaveAudioOutputSettings: (_) async {},
                      );
                    },
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('OpenAI-compatible'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anthropic-compatible').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Base URL'),
      ' https://llm.example.com ',
    );
    await tester.enterText(find.widgetWithText(TextField, 'API key'), ' key ');
    await tester.enterText(find.widgetWithText(TextField, 'Model'), ' model ');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved?.format, LlmServiceFormat.anthropic);
    expect(saved?.baseUrl, 'https://llm.example.com');
    expect(saved?.apiKey, 'key');
    expect(saved?.model, 'model');
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('escape closes settings dialog', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) {
                      return SettingsDialog(
                        llmSettings: const LlmSettings.defaults(),
                        onSaveLlmSettings: (_) async {},
                        audioOutputSettings:
                            const AudioOutputSettings.defaults(),
                        audioDevices: const [AudioDevice('auto', '')],
                        activeAudioDevice: const AudioDevice('auto', ''),
                        audioParams: const AudioParams(),
                        onSaveAudioOutputSettings: (_) async {},
                      );
                    },
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('saves selected audio output device', (tester) async {
    AudioOutputSettings? savedAudio;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) {
                      return SettingsDialog(
                        llmSettings: const LlmSettings.defaults(),
                        onSaveLlmSettings: (_) async {},
                        audioOutputSettings: _systemAudioSettings,
                        audioDevices: const [
                          AudioDevice('auto', ''),
                          AudioDevice('pipewire/dac', 'USB DAC'),
                        ],
                        activeAudioDevice: const AudioDevice('auto', ''),
                        audioParams: const AudioParams(),
                        onSaveAudioOutputSettings: (settings) async {
                          savedAudio = settings;
                        },
                      );
                    },
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('System default').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('USB DAC - PipeWire').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(savedAudio?.deviceName, 'pipewire/dac');
    expect(savedAudio?.deviceDescription, 'USB DAC');
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('keeps dialog open when audio output save fails', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) {
                      return SettingsDialog(
                        llmSettings: const LlmSettings.defaults(),
                        onSaveLlmSettings: (_) async {},
                        audioOutputSettings: _systemAudioSettings,
                        audioDevices: const [
                          AudioDevice('auto', ''),
                          AudioDevice('pipewire/dac', 'USB DAC'),
                        ],
                        activeAudioDevice: const AudioDevice('auto', ''),
                        audioParams: const AudioParams(),
                        onSaveAudioOutputSettings: (_) async {
                          throw StateError('switch failed');
                        },
                      );
                    },
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System default').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('USB DAC - PipeWire').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.textContaining('switch failed'), findsOneWidget);
  });

  testWidgets('filters backend plugin audio devices from the picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) {
                      return SettingsDialog(
                        llmSettings: const LlmSettings.defaults(),
                        onSaveLlmSettings: (_) async {},
                        audioOutputSettings: _systemAudioSettings,
                        audioDevices: const [
                          AudioDevice('auto', ''),
                          AudioDevice('pipewire', 'Default (pipewire)'),
                          AudioDevice(
                            'pipewire/alsa_output.usb-dac',
                            'USB DAC',
                          ),
                          AudioDevice('pulse/alsa_output.usb-dac', 'USB DAC'),
                          AudioDevice('alsa', 'Default (alsa)'),
                          AudioDevice(
                            'alsa/lavrate',
                            'Rate Converter Plugin Using Libav/FFmpeg Library',
                          ),
                          AudioDevice(
                            'alsa/samplerate',
                            'Rate Converter Plugin Using Samplerate Library',
                          ),
                          AudioDevice(
                            'alsa/sysdefault:CARD=OTG',
                            'USB DAC/Default Audio Device',
                          ),
                        ],
                        activeAudioDevice: const AudioDevice('auto', ''),
                        audioParams: const AudioParams(),
                        onSaveAudioOutputSettings: (_) async {},
                      );
                    },
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System default').first);
    await tester.pumpAndSettle();

    expect(find.text('System default'), findsWidgets);
    expect(find.text('USB DAC - PipeWire'), findsOneWidget);
    expect(find.textContaining('PulseAudio'), findsNothing);
    expect(find.textContaining('ALSA'), findsNothing);
    expect(find.textContaining('Rate Converter'), findsNothing);
  });

  testWidgets('direct DAC mode filters ALSA plugin devices', (tester) async {
    AudioOutputSettings? savedAudio;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) {
                      return SettingsDialog(
                        llmSettings: const LlmSettings.defaults(),
                        onSaveLlmSettings: (_) async {},
                        audioOutputSettings:
                            const AudioOutputSettings.defaults(),
                        audioDevices: const [
                          AudioDevice('auto', ''),
                          AudioDevice('pipewire/alsa_output.usb-dac', 'DAC'),
                          AudioDevice('alsa', 'Default (alsa)'),
                          AudioDevice(
                            'alsa/lavrate',
                            'Rate Converter Plugin Using Libav/FFmpeg Library',
                          ),
                          AudioDevice(
                            'alsa/upmix',
                            'Plugin for channel upmix (4,6,8)',
                          ),
                          AudioDevice(
                            'alsa/sysdefault:CARD=OTG',
                            'E1x2 OTG, USB Audio/Default Audio Device',
                          ),
                          AudioDevice(
                            'alsa/front:CARD=OTG,DEV=0',
                            'E1x2 OTG, USB Audio/Front output',
                          ),
                        ],
                        activeAudioDevice: const AudioDevice('auto', ''),
                        audioParams: const AudioParams(
                          format: 's32',
                          sampleRate: 96000,
                          hrChannels: 'stereo',
                        ),
                        onSaveAudioOutputSettings: (settings) async {
                          savedAudio = settings;
                        },
                      );
                    },
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Audiophile output'), findsOneWidget);
    expect(find.text('Direct ALSA DAC'), findsOneWidget);
    expect(find.text('Output: s32 / 96000 Hz / stereo'), findsOneWidget);

    await tester.tap(find.text('No direct DAC selected').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('PipeWire'), findsNothing);
    expect(find.textContaining('Rate Converter'), findsNothing);
    expect(find.textContaining('upmix'), findsNothing);
    expect(
      find.text('E1x2 OTG, USB Audio/Default Audio Device - ALSA'),
      findsOneWidget,
    );

    await tester.tap(
      find.text('E1x2 OTG, USB Audio/Default Audio Device - ALSA').last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(savedAudio?.mode, AudioOutputMode.directAlsa);
    expect(savedAudio?.deviceName, 'alsa/sysdefault:CARD=OTG');
    expect(savedAudio?.lockVolumeTo100, isTrue);
    expect(savedAudio?.disableReplayGain, isTrue);
    expect(savedAudio?.preferGapless, isTrue);
  });
}
