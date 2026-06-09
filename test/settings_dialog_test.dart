import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
