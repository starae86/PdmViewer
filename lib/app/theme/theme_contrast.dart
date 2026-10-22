import 'package:flutter/material.dart';

enum ThemeContrast {
  low('低'),
  medium('中'),
  high('高');

  const ThemeContrast(this.label);
  final String label;

  static ThemeContrast fromName(Object? name) =>
      values.where((value) => value.name == name).firstOrNull ?? medium;
}

/// Shared contrast tokens for widgets not covered by Material color roles.
@immutable
class ContrastStyle extends ThemeExtension<ContrastStyle> {
  const ContrastStyle(this.level);

  final ThemeContrast level;

  static ContrastStyle of(BuildContext context) =>
      Theme.of(context).extension<ContrastStyle>() ??
      const ContrastStyle(ThemeContrast.medium);

  double get textOpacity => switch (level) {
    ThemeContrast.low => 0.78,
    ThemeContrast.medium => 0.85,
    ThemeContrast.high => 0.95,
  };
  double get outlineOpacity => switch (level) {
    ThemeContrast.low => 0.44,
    ThemeContrast.medium => 0.55,
    ThemeContrast.high => 0.70,
  };
  double get dividerOpacity => switch (level) {
    ThemeContrast.low => 0.18,
    ThemeContrast.medium => 0.30,
    ThemeContrast.high => 0.44,
  };
  double get hoverOpacity => switch (level) {
    ThemeContrast.low => 0.08,
    ThemeContrast.medium => 0.12,
    ThemeContrast.high => 0.18,
  };
  double get selectionOpacity => switch (level) {
    ThemeContrast.low => 0.14,
    ThemeContrast.medium => 0.22,
    ThemeContrast.high => 0.32,
  };
  double selectionAlpha(Brightness brightness) =>
      selectionOpacity + (brightness == Brightness.dark ? 0.06 : 0);
  double get activeMatchOpacity => switch (level) {
    ThemeContrast.low => 0.24,
    ThemeContrast.medium => 0.30,
    ThemeContrast.high => 0.40,
  };

  Color layer(Color color, Color surface) =>
      Color.lerp(surface, color, switch (level) {
        ThemeContrast.low => 0.65,
        ThemeContrast.medium => 1.0,
        ThemeContrast.high => 1.35,
      })!;

  static double _ratio(Color a, Color b) {
    final x = a.computeLuminance();
    final y = b.computeLuminance();
    return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
  }

  Color accent(Color color, Color surface) {
    if (level == ThemeContrast.medium) return color;
    final extreme =
        _ratio(Colors.black, surface) > _ratio(Colors.white, surface)
        ? Colors.black
        : Colors.white;
    final current = _ratio(color, surface);
    final maximum = _ratio(extreme, surface);
    final target = level == ThemeContrast.high
        ? (current + (maximum - current) * 0.25).clamp(
            maximum < 7 ? maximum : 7.0,
            maximum,
          )
        : current < 4.5
        ? current * 0.8
        : (current * 0.8).clamp(4.5, maximum);
    final increasing = target > current;
    final endpoint = increasing ? extreme : surface;
    var lower = 0.0;
    var upper = 1.0;
    // Find the closest opaque tone without altering the stored seed color.
    for (var i = 0; i < 20; i++) {
      final middle = (lower + upper) / 2;
      final ratio = _ratio(Color.lerp(color, endpoint, middle)!, surface);
      if (increasing ? ratio < target : ratio > target) {
        lower = middle;
      } else {
        upper = middle;
      }
    }
    return Color.lerp(color, endpoint, increasing ? upper : lower)!;
  }

  Color onAccent(Color color, Color preferred) {
    if (_ratio(color, preferred) >= 4.5) return preferred;
    return _ratio(color, Colors.black) > _ratio(color, Colors.white)
        ? Colors.black
        : Colors.white;
  }

  @override
  ContrastStyle copyWith({ThemeContrast? level}) =>
      ContrastStyle(level ?? this.level);

  @override
  ContrastStyle lerp(covariant ContrastStyle? other, double t) =>
      other == null || t < 0.5 ? this : other;
}
