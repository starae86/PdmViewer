import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'english_messages.dart';

class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;
  static const supportedLocales = [Locale('zh'), Locale('en')];
  static const delegate = _AppStringsDelegate();

  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) ??
      const AppStrings(Locale('zh'));

  String translate(String source) {
    if (locale.languageCode != 'en') return source;
    final exact = englishMessages[source];
    if (exact != null) return exact;
    for (final prefix in const ['Exception: ', 'Bad state: ']) {
      if (source.startsWith(prefix)) {
        return '$prefix${translate(source.substring(prefix.length))}';
      }
    }
    for (final message in _patterns) {
      final match = message.pattern.firstMatch(source);
      if (match == null) continue;
      return message.english.replaceAllMapped(RegExp(r'\{(\w+)\}'), (token) {
        final index = message.parameters.indexOf(token.group(1)!);
        if (index < 0) return token.group(0)!;
        final value = match.group(index + 1)!;
        return token.group(1) == 'suffix'
            ? (englishMessages[value] ?? value)
            : value;
      });
    }
    return source;
  }

  // Dynamic messages translate only the surrounding UI text, never captured data.
  static final _patternEntries =
      englishMessages.entries
          .where((entry) => RegExp(r'\{\w+\}').hasMatch(entry.key))
          .toList()
        ..sort(
          (a, b) => b.key
              .replaceAll(RegExp(r'\{\w+\}'), '')
              .length
              .compareTo(a.key.replaceAll(RegExp(r'\{\w+\}'), '').length),
        );

  static final _patterns = _patternEntries
      .map((entry) {
        final parameters = <String>[];
        final buffer = StringBuffer('^');
        var offset = 0;
        for (final token in RegExp(r'\{(\w+)\}').allMatches(entry.key)) {
          buffer.write(RegExp.escape(entry.key.substring(offset, token.start)));
          buffer.write('([\\s\\S]*?)');
          parameters.add(token.group(1)!);
          offset = token.end;
        }
        buffer.write(RegExp.escape(entry.key.substring(offset)));
        buffer.write(r'$');
        return (
          pattern: RegExp(buffer.toString()),
          parameters: parameters,
          english: entry.value,
        );
      })
      .toList(growable: false);
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) => AppStrings.supportedLocales.any(
    (value) => value.languageCode == locale.languageCode,
  );

  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture(AppStrings(locale));

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}

extension AppStringsContext on BuildContext {
  String tr(String source) => AppStrings.of(this).translate(source);
}

/// Keeps constant UI labels reactive to locale changes without translating model data.
class LText extends StatelessWidget {
  const LText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.semanticsLabel,
  });

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => Text(
    context.tr(data),
    style: style,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
    softWrap: softWrap,
    semanticsLabel: semanticsLabel == null ? null : context.tr(semanticsLabel!),
  );
}
