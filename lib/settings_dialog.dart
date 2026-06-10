import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'llm_settings.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.llmSettings,
    required this.onSaveLlmSettings,
  });

  final LlmSettings llmSettings;
  final Future<void> Function(LlmSettings settings) onSaveLlmSettings;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late LlmServiceFormat _format;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = widget.llmSettings;
    _format = settings.format;
    _baseUrlController = TextEditingController(text: settings.baseUrl);
    _apiKeyController = TextEditingController(text: settings.apiKey);
    _modelController = TextEditingController(text: settings.model);
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
    setState(() => _saving = true);
    try {
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

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: Focus(
        autofocus: true,
        child: AlertDialog(
          title: const Text('Settings'),
          contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
