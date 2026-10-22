import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// Uses the shared opaque chrome color for all platforms.
class ChromeSurface extends StatelessWidget {
  const ChromeSurface({super.key, required this.child, this.border});

  final Widget child;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.menuStripFill(context),
        border: border,
      ),
      child: child,
    );
  }
}
