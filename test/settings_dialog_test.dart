import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:miaosic/audio_output_settings.dart';
import 'package:miaosic/llm_settings.dart';
import 'package:miaosic/settings_dialog.dart';

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
    await tester.tap(find.text('USB DAC (pipewire/dac)').last);
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
    await tester.tap(find.text('USB DAC (pipewire/dac)').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.textContaining('switch failed'), findsOneWidget);
  });
}
