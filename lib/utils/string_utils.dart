import 'dart:convert';

import 'package:flutter/services.dart';

/// Loads and serves localized strings from the bundled Spanish JSON file.
class StringUtils {
  static const String _assetPath = 'lib/l10n/es.json';
  static Map<String, String> _localizedStrings = <String, String>{};

  /// Loads localization values before the application renders.
  static Future<void> load() async {
    final String jsonContent = await rootBundle.loadString(_assetPath);
    final Map<String, dynamic> decodedJson =
        jsonDecode(jsonContent) as Map<String, dynamic>;
    _localizedStrings = decodedJson.map(
      (String key, dynamic value) => MapEntry<String, String>(
        key,
        value.toString(),
      ),
    );
  }

  /// Returns a localized string or the key itself when it is missing.
  static String get(String key) {
    return _localizedStrings[key] ?? key;
  }

  /// Returns a localized string with named placeholders replaced.
  static String format(String key, Map<String, String> replacements) {
    String value = get(key);
    replacements.forEach((String placeholder, String replacement) {
      value = value.replaceAll('{$placeholder}', replacement);
    });
    return value;
  }
}
