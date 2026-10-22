import 'package:flutter/services.dart';

class SystemFontService {
  static const _channel = MethodChannel('pdm_viewer/system_fonts');
  static List<String>? _cachedFamilies;

  static Future<List<String>> loadFamilies() async {
    if (_cachedFamilies case final families?) {
      return families;
    }
    final families = await _channel.invokeListMethod<String>('listFamilies');
    final sorted =
        (families ?? <String>[])
            .where((family) => family.isNotEmpty && !family.startsWith('@'))
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _cachedFamilies = List.unmodifiable(sorted);
    return _cachedFamilies!;
  }
}
