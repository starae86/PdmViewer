import 'dart:io';

import 'package:flutter/material.dart';

import 'theme_preset.dart';
import 'component_style.dart';
import 'theme_contrast.dart';

class AppTheme {
  static const Color defaultSeedColor = Color(0xFF007ACC);

  static ThemeData build({
    Color seedColor = defaultSeedColor,
    String? fontFamily,
    Brightness brightness = Brightness.light,
    Color? backgroundColor,
    Color? foregroundColor,
    String? presetId,
    Color? accentColor,
    ThemeContrast contrast = ThemeContrast.medium,
  }) {
    final systemFontConfig = _resolveUiFontConfig();
    final fontConfig = _UiFontConfig(
      primaryFamily: fontFamily ?? systemFontConfig.primaryFamily,
      fallbackFamilies: systemFontConfig.fallbackFamilies,
    );
    final palette = ThemePreset.find(presetId)?.palette(brightness);
    final components = ComponentStyle.forPreset(presetId);
    final material = components.isMaterial;
    final workbench = components.isWorkbench;
    final tonalMaterial = material && !workbench;
    final contrastStyle = ContrastStyle(contrast);
    final accent =
        accentColor ??
        (tonalMaterial
            ? ThemePreset.find(presetId)?.light.accent
            : palette?.accent) ??
        seedColor;
    final background =
        backgroundColor ?? palette?.background ?? defaultBackground(brightness);
    final foreground =
        foregroundColor ?? palette?.foreground ?? defaultForeground(brightness);
    final generated = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      surface: background,
    );
    final usePresetAccent =
        !tonalMaterial && accentColor == null && palette != null;
    final customMaterialAccent = tonalMaterial && accentColor != null;
    final selection = workbench
        ? (accentColor == null
              ? palette!.selection
              : Color.alphaBlend(accent.withValues(alpha: 0.22), background))
        : null;
    final baseScheme = generated.copyWith(
      // Derive supporting tones, but keep the chosen accent exact at medium contrast.
      primary: accentColor ?? palette?.accent ?? seedColor,
      onPrimary: usePresetAccent ? palette.onAccent : null,
      primaryContainer:
          selection ?? (usePresetAccent ? palette.selection : null),
      onPrimaryContainer: workbench || usePresetAccent ? foreground : null,
      secondaryContainer:
          selection ??
          (tonalMaterial
              ? (customMaterialAccent
                    ? generated.secondaryContainer
                    : palette?.selection)
              : null),
      onSecondaryContainer: workbench || tonalMaterial ? foreground : null,
      onSurface: foreground,
      onSurfaceVariant: Color.alphaBlend(
        foreground.withValues(alpha: contrastStyle.textOpacity),
        background,
      ),
      surfaceContainerLowest: tonalMaterial
          ? generated.surfaceContainerLowest
          : background,
      surfaceContainerLow: customMaterialAccent
          ? Color.alphaBlend(
              generated.primary.withValues(alpha: 0.08),
              generated.surfaceContainerLow,
            )
          : palette?.chrome ??
                Color.alphaBlend(
                  foreground.withValues(alpha: 0.025),
                  background,
                ),
      surfaceContainer:
          (tonalMaterial ? generated.surfaceContainer : palette?.chrome) ??
          Color.alphaBlend(foreground.withValues(alpha: 0.04), background),
      surfaceContainerHigh: tonalMaterial
          ? generated.surfaceContainerHigh
          : Color.alphaBlend(
              foreground.withValues(alpha: 0.06),
              palette?.chrome ?? background,
            ),
      surfaceContainerHighest: tonalMaterial
          ? generated.surfaceContainerHighest
          : Color.alphaBlend(
              foreground.withValues(alpha: 0.08),
              palette?.chrome ?? background,
            ),
      outline: Color.alphaBlend(
        foreground.withValues(alpha: contrastStyle.outlineOpacity),
        background,
      ),
      outlineVariant: Color.alphaBlend(
        foreground.withValues(alpha: contrastStyle.dividerOpacity),
        background,
      ),
    );
    final resolvedPrimary = contrastStyle.accent(
      baseScheme.primary,
      background,
    );
    final scheme = baseScheme.copyWith(
      primary: resolvedPrimary,
      onPrimary: contrastStyle.onAccent(resolvedPrimary, baseScheme.onPrimary),
      primaryContainer: contrastStyle.layer(
        baseScheme.primaryContainer,
        background,
      ),
      secondaryContainer: contrastStyle.layer(
        baseScheme.secondaryContainer,
        background,
      ),
      surfaceContainerLow: contrastStyle.layer(
        baseScheme.surfaceContainerLow,
        background,
      ),
      surfaceContainer: contrastStyle.layer(
        baseScheme.surfaceContainer,
        background,
      ),
      surfaceContainerHigh: contrastStyle.layer(
        baseScheme.surfaceContainerHigh,
        background,
      ),
      surfaceContainerHighest: contrastStyle.layer(
        baseScheme.surfaceContainerHighest,
        background,
      ),
    );
    final base = ThemeData(
      useMaterial3: true,
      materialTapTargetSize:
          Platform.isWindows || Platform.isMacOS || Platform.isLinux
          ? MaterialTapTargetSize.shrinkWrap
          : MaterialTapTargetSize.padded,
      colorScheme: scheme,
      fontFamily: fontConfig.primaryFamily,
      fontFamilyFallback: fontConfig.fallbackFamilies,
    );

    return base.copyWith(
      extensions: [components, contrastStyle],
      splashFactory: material
          ? InkRipple.splashFactory
          : NoSplash.splashFactory,
      splashColor: material ? null : Colors.transparent,
      highlightColor: material ? null : Colors.transparent,
      canvasColor: background,
      visualDensity: VisualDensity.compact,
      iconTheme: IconThemeData(color: foreground),
      dividerColor: scheme.outlineVariant,
      dialogTheme: DialogThemeData(
        backgroundColor: material
            ? scheme.surfaceContainerHigh
            : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(components.dialogRadius),
          side: material
              ? BorderSide.none
              : BorderSide(color: scheme.outlineVariant),
        ),
        elevation: components.dialogElevation,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: material ? scheme.surfaceContainer : scheme.surfaceContainerHigh,
        elevation: components.menuElevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(components.menuRadius),
          side: material
              ? BorderSide.none
              : BorderSide(color: scheme.outlineVariant),
        ),
        surfaceTintColor: Colors.transparent,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            material ? scheme.surfaceContainer : scheme.surfaceContainerHigh,
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(components.menuRadius),
            ),
          ),
          side: WidgetStatePropertyAll(
            material
                ? BorderSide.none
                : BorderSide(color: scheme.outlineVariant),
          ),
          elevation: WidgetStatePropertyAll(components.menuElevation),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: components.controlBorderRadius,
            ),
          ),
          minimumSize: WidgetStatePropertyAll(
            Size(40, components.controlHeight),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)
                ? (components.isMacos
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.08))
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? scheme.onSurface.withValues(alpha: 0.38)
                : components.isMacos &&
                      (states.contains(WidgetState.hovered) ||
                          states.contains(WidgetState.focused))
                ? scheme.onPrimary
                : scheme.onSurface,
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: components.controlBorderRadius,
        ),
        textStyle: base.textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        waitDuration: const Duration(milliseconds: 500),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStatePropertyAll(components.scrollbarWidth),
        radius: const Radius.circular(8),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => scheme.onSurfaceVariant.withValues(
            alpha: states.contains(WidgetState.dragged)
                ? 0.65
                : states.contains(WidgetState.hovered)
                ? 0.5
                : 0.3,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      scaffoldBackgroundColor: Colors.transparent,
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: fontConfig.primaryFamily,
        fontFamilyFallback: fontConfig.fallbackFamilies,
      ),
      textTheme: base.textTheme
          .apply(
            fontFamily: fontConfig.primaryFamily,
            fontFamilyFallback: fontConfig.fallbackFamilies,
            bodyColor: foreground,
            displayColor: foreground,
          )
          .copyWith(
            displaySmall: base.textTheme.displaySmall?.copyWith(
              fontFamily: fontConfig.primaryFamily,
              fontFamilyFallback: fontConfig.fallbackFamilies,
              fontSize: 26,
              height: 1.15,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
            headlineMedium: base.textTheme.headlineMedium?.copyWith(
              fontFamily: fontConfig.primaryFamily,
              fontFamilyFallback: fontConfig.fallbackFamilies,
              fontSize: 22,
              height: 1.18,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
            titleLarge: base.textTheme.titleLarge?.copyWith(
              fontFamily: fontConfig.primaryFamily,
              fontFamilyFallback: fontConfig.fallbackFamilies,
              fontSize: 18,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
            titleSmall: base.textTheme.titleSmall?.copyWith(
              fontFamily: fontConfig.primaryFamily,
              fontFamilyFallback: fontConfig.fallbackFamilies,
              fontSize: 14,
              height: 1.2,
              fontWeight: FontWeight.w500,
              color: foreground,
            ),
            titleMedium: base.textTheme.titleMedium?.copyWith(
              fontFamily: fontConfig.primaryFamily,
              fontFamilyFallback: fontConfig.fallbackFamilies,
              fontSize: 15,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
            bodyMedium: base.textTheme.bodyMedium?.copyWith(
              fontFamily: fontConfig.primaryFamily,
              fontFamilyFallback: fontConfig.fallbackFamilies,
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
              color: foreground,
              height: 1.28,
            ),
            bodySmall: base.textTheme.bodySmall?.copyWith(
              fontFamily: fontConfig.primaryFamily,
              fontFamilyFallback: fontConfig.fallbackFamilies,
              fontSize: 12.5,
              color: scheme.onSurfaceVariant,
              height: 1.24,
            ),
            labelLarge: base.textTheme.labelLarge?.copyWith(
              fontFamily: fontConfig.primaryFamily,
              fontFamilyFallback: fontConfig.fallbackFamilies,
              fontSize: 13,
              height: 1.15,
              fontWeight: FontWeight.w500,
              color: foreground,
            ),
            labelMedium: base.textTheme.labelMedium?.copyWith(
              fontFamily: fontConfig.primaryFamily,
              fontFamilyFallback: fontConfig.fallbackFamilies,
              fontSize: 12.5,
              height: 1.15,
              fontWeight: FontWeight.w500,
              color: foreground,
            ),
            labelSmall: base.textTheme.labelSmall?.copyWith(
              fontFamily: fontConfig.primaryFamily,
              fontFamilyFallback: fontConfig.fallbackFamilies,
              fontSize: 11.5,
              height: 1.1,
              fontWeight: FontWeight.w500,
              color: foreground,
            ),
          ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            material ? 12 : components.controlRadius,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: components.controlBorderRadius,
        ),
        selectedTileColor: components.selectionFill(scheme),
        selectedColor: components.selectionForeground(scheme),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        isDense: true,
        contentPadding: components.inputPadding,
        border: OutlineInputBorder(
          borderRadius: components.controlBorderRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: components.controlBorderRadius,
          borderSide: BorderSide(
            color: material ? scheme.outline : scheme.outlineVariant,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: components.controlBorderRadius,
          borderSide: BorderSide(
            color: scheme.primary.withValues(
              alpha: components.isMacos ? 0.5 : 1,
            ),
            width: components.focusWidth,
          ),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.25),
        selectionHandleColor: scheme.primary,
      ),
      chipTheme: base.chipTheme.copyWith(
        color: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return scheme.onSurface.withValues(alpha: 0.12);
          }
          return states.contains(WidgetState.selected)
              ? components.selectionFill(scheme)
              : scheme.surfaceContainerHigh;
        }),
        labelStyle: base.textTheme.labelLarge!.copyWith(
          fontSize: 13,
          height: 1.15,
          fontWeight: FontWeight.w500,
          color: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? scheme.onSurface.withValues(alpha: 0.38)
                : states.contains(WidgetState.selected)
                ? components.selectionForeground(scheme)
                : scheme.onSurface,
          ),
        ),
        shape: components.buttonShape,
        side: material
            ? BorderSide.none
            : BorderSide(color: scheme.outlineVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
          minimumSize: Size(64, components.controlHeight),
          padding: material
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
              : components.inputPadding,
          shape: components.buttonShape,
          animationDuration: components.motionDuration,
          elevation: components.isMacos ? 1 : 0,
          overlayColor: material
              ? null
              : scheme.onPrimary.withValues(alpha: 0.1),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: components.buttonShape,
          minimumSize: Size(48, components.controlHeight),
          animationDuration: components.motionDuration,
          overlayColor: material
              ? null
              : scheme.onSurface.withValues(alpha: 0.08),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: components.buttonShape,
          minimumSize: Size(64, components.controlHeight),
          backgroundColor: workbench
              ? scheme.surfaceContainerLow
              : material
              ? null
              : scheme.surfaceContainerLowest,
          side: BorderSide(
            color: material ? scheme.outline : scheme.outlineVariant,
          ),
          animationDuration: components.motionDuration,
          overlayColor: material
              ? null
              : scheme.onSurface.withValues(alpha: 0.08),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(components.buttonShape),
          animationDuration: components.motionDuration,
          minimumSize: WidgetStatePropertyAll(
            Size(40, components.controlHeight),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(
              color: material ? scheme.outline : scheme.outlineVariant,
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? (components.isMacos
                      ? scheme.surfaceContainerLowest
                      : components.selectionFill(scheme))
                : (material ? Colors.transparent : scheme.surfaceContainerHigh),
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? scheme.onSurface.withValues(alpha: 0.38)
                : material && states.contains(WidgetState.selected)
                ? scheme.onSecondaryContainer
                : scheme.onSurface,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: components.controlBorderRadius,
            ),
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            material
                ? 2
                : components.isFluent
                ? 3
                : 4,
          ),
        ),
        side: BorderSide(color: scheme.outline, width: 1),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: material ? 0 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            material ? 16 : components.controlRadius,
          ),
        ),
      ),
    );
  }

  static Color defaultBackground(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0xFF1E1E1E) : Colors.white;

  static Color defaultForeground(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFFE5E5E5)
      : const Color(0xFF0D0D0D);

  static Color searchHighlight(BuildContext context, {bool active = false}) =>
      Color.alphaBlend(
        primaryOf(context).withValues(
          alpha: active
              ? ContrastStyle.of(context).activeMatchOpacity
              : ContrastStyle.of(context).hoverOpacity,
        ),
        surfaceOf(context),
      );

  static Color primaryOf(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  static ComponentStyle componentsOf(BuildContext context) =>
      ComponentStyle.of(context);

  static BorderRadius controlRadiusOf(BuildContext context) =>
      componentsOf(context).controlBorderRadius;

  static BorderRadius searchRadiusOf(BuildContext context) =>
      componentsOf(context).searchBorderRadius;

  static BorderRadius menuRadiusOf(BuildContext context) =>
      BorderRadius.circular(componentsOf(context).menuRadius);

  static BorderRadius badgeRadiusOf(BuildContext context) =>
      componentsOf(context).badgeBorderRadius;

  static BorderRadius tabRadiusOf(BuildContext context) => BorderRadius.only(
    topLeft: Radius.circular(componentsOf(context).controlRadius),
    topRight: Radius.circular(componentsOf(context).controlRadius),
  );

  static BoxDecoration tabIndicatorOf(BuildContext context) =>
      componentsOf(context).tabIndicator(Theme.of(context).colorScheme);

  static Color treeSelectionFill(BuildContext context) =>
      componentsOf(context).selectionFill(Theme.of(context).colorScheme);

  static Color treeSelectionForeground(BuildContext context) =>
      componentsOf(context).selectionForeground(Theme.of(context).colorScheme);

  static Color badgeFill(BuildContext context) =>
      componentsOf(context).isMaterial && !componentsOf(context).isWorkbench
      ? Theme.of(context).colorScheme.secondaryContainer
      : Theme.of(context).colorScheme.surfaceContainerHigh;

  static Color badgeForeground(BuildContext context) =>
      componentsOf(context).isMaterial
      ? Theme.of(context).colorScheme.onSecondaryContainer
      : Theme.of(context).colorScheme.onSurface;

  static Color selectionFill(BuildContext context) => Color.alphaBlend(
    primaryOf(context).withValues(
      alpha: ContrastStyle.of(
        context,
      ).selectionAlpha(Theme.of(context).brightness),
    ),
    surfaceOf(context),
  );

  static Color selectionSoft(BuildContext context) => Color.alphaBlend(
    primaryOf(
      context,
    ).withValues(alpha: ContrastStyle.of(context).hoverOpacity),
    surfaceOf(context),
  );

  static Color hoverFill(BuildContext context) => Color.alphaBlend(
    primaryOf(
      context,
    ).withValues(alpha: ContrastStyle.of(context).hoverOpacity + 0.02),
    surfaceOf(context),
  );

  static Color surfaceOf(BuildContext context) =>
      Theme.of(context).colorScheme.surface;

  static Color outlineSoft(BuildContext context) =>
      Theme.of(context).colorScheme.outlineVariant;

  static Color tabStripFill(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerLow;

  static Color menuStripFill(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerLow;

  static Color tabInactiveFill(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerLow;

  static Color tabActiveFill(BuildContext context) => surfaceOf(context);

  static Color tabInactiveForeground(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  static Color tabActiveForeground(BuildContext context) =>
      componentsOf(context).isMacos
      ? Theme.of(context).colorScheme.onSurface
      : Theme.of(context).colorScheme.primary;

  static Color tableHeaderFill(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerLow;

  static Color treeNodeFill(BuildContext context) => Colors.transparent;

  static Color treeNodeHoverFill(BuildContext context) => Color.alphaBlend(
    Theme.of(context).colorScheme.onSurface.withValues(
      alpha: ContrastStyle.of(context).hoverOpacity,
    ),
    menuStripFill(context),
  );

  static Color treeNodeHoverBorder(BuildContext context) => primaryOf(context);

  static Color tableRowFill(BuildContext context, {required bool isEven}) =>
      surfaceOf(context);

  static Color treeNodeIcon(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  static Color warningForeground(BuildContext context) =>
      Theme.of(context).colorScheme.tertiary;

  static List<Color> backgroundGradient(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (componentsOf(context).isFluent) {
      return [
        scheme.surfaceContainerLow,
        scheme.surfaceContainerLow,
        scheme.surfaceContainerLow,
      ];
    }
    return [
      scheme.surfaceContainerLowest,
      scheme.surfaceContainerLowest,
      scheme.surfaceContainerLowest,
    ];
  }
}

_UiFontConfig _resolveUiFontConfig() {
  if (Platform.isMacOS) {
    return const _UiFontConfig(
      primaryFamily: '.AppleSystemUIFont',
      fallbackFamilies: ['PingFang SC', 'Helvetica Neue'],
    );
  }
  if (Platform.isWindows) {
    return const _UiFontConfig(
      primaryFamily: 'Segoe UI',
      fallbackFamilies: ['Microsoft YaHei UI', 'Microsoft YaHei'],
    );
  }
  return const _UiFontConfig(
    primaryFamily: 'Noto Sans CJK SC',
    fallbackFamilies: ['Noto Sans SC', 'DejaVu Sans', 'sans-serif'],
  );
}

class _UiFontConfig {
  const _UiFontConfig({
    required this.primaryFamily,
    required this.fallbackFamilies,
  });

  final String primaryFamily;
  final List<String> fallbackFamilies;
}
