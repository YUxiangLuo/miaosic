enum LlmServiceFormat {
  openai('openai', 'OpenAI-compatible', 'https://api.openai.com/v1'),
  anthropic('anthropic', 'Anthropic-compatible', 'https://api.anthropic.com');

  const LlmServiceFormat(this.dbValue, this.label, this.defaultBaseUrl);

  final String dbValue;
  final String label;
  final String defaultBaseUrl;

  static LlmServiceFormat fromDb(String? value) {
    for (final format in LlmServiceFormat.values) {
      if (format.dbValue == value) {
        return format;
      }
    }
    return LlmServiceFormat.openai;
  }
}

class LlmSettings {
  const LlmSettings({
    required this.format,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  const LlmSettings.defaults()
    : format = LlmServiceFormat.openai,
      baseUrl = 'https://api.openai.com/v1',
      apiKey = '',
      model = '';

  final LlmServiceFormat format;
  final String baseUrl;
  final String apiKey;
  final String model;

  Map<String, Object?> toJson() {
    return {
      'format': format.dbValue,
      'base_url': baseUrl,
      'api_key': apiKey,
      'model': model,
    };
  }

  static LlmSettings fromJson(Map<String, Object?> json) {
    final defaults = const LlmSettings.defaults();
    final format = LlmServiceFormat.fromDb(json['format'] as String?);
    final baseUrl = (json['base_url'] as String?)?.trim();
    final apiKey = json['api_key'] as String?;
    final model = json['model'] as String?;
    return LlmSettings(
      format: format,
      baseUrl: baseUrl == null || baseUrl.isEmpty
          ? format.defaultBaseUrl
          : baseUrl,
      apiKey: apiKey ?? defaults.apiKey,
      model: model ?? defaults.model,
    );
  }

  LlmSettings normalized() {
    return LlmSettings(
      format: format,
      baseUrl: baseUrl.trim(),
      apiKey: apiKey.trim(),
      model: model.trim(),
    );
  }
}
