import 'package:flutter/material.dart';

enum ComponentDesign { material, fluent, macos, workbench }

/// Shared widget vocabulary; changing a profile never changes page state.
@immutable
class ComponentStyle extends ThemeExtension<ComponentStyle> {
  const ComponentStyle({
    required this.design,
    required this.controlRadius,
    required this.buttonRadius,
    required this.searchRadius,
    required this.menuRadius,
    required this.dialogRadius,
    required this.controlHeight,
    required this.inputPadding,
    required this.focusWidth,
    required this.menuElevation,
    required this.dialogElevation,
    required this.scrollbarWidth,
    required this.motionDuration,
  });

  final ComponentDesign design;
  final double controlRadius;
  final double buttonRadius;
  final double searchRadius;
  final double menuRadius;
  final double dialogRadius;
  final double controlHeight;
  final EdgeInsets inputPadding;
  final double focusWidth;
  final double menuElevation;
  final double dialogElevation;
  final double scrollbarWidth;
  final Duration motionDuration;

  static const workbench = ComponentStyle(
    design: ComponentDesign.workbench,
    controlRadius: 6,
    buttonRadius: 6,
    searchRadius: 6,
    menuRadius: 8,
    dialogRadius: 12,
    controlHeight: 36,
    inputPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    focusWidth: 1,
    menuElevation: 3,
    dialogElevation: 0,
    scrollbarWidth: 6,
    motionDuration: Duration(milliseconds: 150),
  );

  static const material = ComponentStyle(
    design: ComponentDesign.material,
    controlRadius: 8,
    buttonRadius: 100,
    searchRadius: 100,
    menuRadius: 12,
    dialogRadius: 28,
    controlHeight: 36,
    inputPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    focusWidth: 2,
    menuElevation: 3,
    dialogElevation: 0,
    scrollbarWidth: 6,
    motionDuration: Duration(milliseconds: 200),
  );

  static const fluent = ComponentStyle(
    design: ComponentDesign.fluent,
    controlRadius: 4,
    buttonRadius: 4,
    searchRadius: 4,
    menuRadius: 8,
    dialogRadius: 8,
    controlHeight: 32,
    inputPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    focusWidth: 2,
    menuElevation: 8,
    dialogElevation: 12,
    scrollbarWidth: 4,
    motionDuration: Duration(milliseconds: 150),
  );

  static const macos = ComponentStyle(
    design: ComponentDesign.macos,
    controlRadius: 5,
    buttonRadius: 5,
    searchRadius: 6,
    menuRadius: 6,
    dialogRadius: 12,
    controlHeight: 28,
    inputPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    focusWidth: 3,
    menuElevation: 10,
    dialogElevation: 16,
    scrollbarWidth: 7,
    motionDuration: Duration(milliseconds: 120),
  );

  static ComponentStyle forPreset(String? id) => switch (id) {
    'workbench' => workbench,
    'fluent' => fluent,
    'macos' => macos,
    _ => material,
  };

  static ComponentStyle of(BuildContext context) =>
      Theme.of(context).extension<ComponentStyle>() ?? material;

  bool get isMaterial => design == ComponentDesign.material || isWorkbench;
  bool get isWorkbench => design == ComponentDesign.workbench;
  bool get isFluent => design == ComponentDesign.fluent;
  bool get isMacos => design == ComponentDesign.macos;

  BorderRadius get controlBorderRadius => BorderRadius.circular(controlRadius);
  BorderRadius get searchBorderRadius => BorderRadius.circular(searchRadius);
  BorderRadius get badgeBorderRadius =>
      BorderRadius.circular(isMaterial ? 100 : controlRadius);
  OutlinedBorder get buttonShape =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(buttonRadius));

  Color selectionFill(ColorScheme scheme) => isMaterial
      ? scheme.secondaryContainer
      : isMacos
      ? scheme.primary
      : scheme.primaryContainer;

  Color selectionForeground(ColorScheme scheme) => isMaterial
      ? scheme.onSecondaryContainer
      : isMacos
      ? scheme.onPrimary
      : scheme.onSurface;

  BoxDecoration tabIndicator(ColorScheme scheme) => isMaterial
      ? BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.primary, width: 2)),
        )
      : isFluent
      ? BoxDecoration(
          border: Border(top: BorderSide(color: scheme.primary, width: 2)),
        )
      : BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        );

  @override
  ComponentStyle copyWith() => this;

  @override
  ComponentStyle lerp(covariant ComponentStyle? other, double t) =>
      other == null || t < 0.5 ? this : other;
}
