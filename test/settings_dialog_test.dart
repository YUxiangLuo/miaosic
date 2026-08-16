import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:miaosic/audio_output_settings.dart';
import 'package:miaosic/settings_dialog.dart';

void main() {
  testWidgets('settings dialog only shows audio output', (tester) async {
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
                        audioOutputSettings:
                            const AudioOutputSettings.defaults(),
                        audioDevices: const [AudioDevice('auto', '')],
                        activeAudioDevice: const AudioDevice('auto', ''),
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

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Audio output'), findsOneWidget);
    expect(find.text('LLM'), findsNothing);
    expect(find.text('Service format'), findsNothing);
    expect(find.text('Base URL'), findsNothing);
    expect(find.text('API key'), findsNothing);
    expect(find.text('Model'), findsNothing);
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
                        audioOutputSettings:
                            const AudioOutputSettings.defaults(),
                        audioDevices: const [AudioDevice('auto', '')],
                        activeAudioDevice: const AudioDevice('auto', ''),
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
                        audioOutputSettings:
                            const AudioOutputSettings.defaults(),
                        audioDevices: const [
                          AudioDevice('auto', ''),
                          AudioDevice('pipewire/dac', 'USB DAC'),
                        ],
                        activeAudioDevice: const AudioDevice('auto', ''),
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
                        audioOutputSettings:
                            const AudioOutputSettings.defaults(),
                        audioDevices: const [
                          AudioDevice('auto', ''),
                          AudioDevice('pipewire/dac', 'USB DAC'),
                        ],
                        activeAudioDevice: const AudioDevice('auto', ''),
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
                        audioOutputSettings:
                            const AudioOutputSettings.defaults(),
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
}
