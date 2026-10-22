# Component Style Profiles

The app keeps one widget tree and one business implementation. Three immutable
`ComponentStyle` profiles are installed as a `ThemeExtension` by `AppTheme.build`.
The existing persisted `presetId` selects both the palette and the component
profile; custom accents, light/dark/system appearance, and fonts are independent.

| Profile | Buttons | Text Fields | Menus / Dialogs | Selection |
| --- | --- | --- | --- | --- |
| Material | Pill, 36px minimum | Tonal search, 8px corners | Tonal menus, 28px dialog corners | Tonal fill, bottom tab indicator |
| Fluent | 4px corners, 32px minimum | Fine outline, accent focus | Bordered elevated surfaces, 8px corners | Subtle accent fill, top tab indicator |
| macOS | 5px corners, 28px minimum | Compact padding, translucent focus ring | Compact menus, elevated 12px dialogs | Accent sidebar, neutral segmented control |

These minimum heights do not constrain larger fonts. The workspace stays flush
to the window, without introducing outer rounding, padding, or layout changes.

## Maintaining Styles

- Edit geometry, durations, selection colors, and tab indicators in
  `lib/app/theme/component_style.dart`.
- Edit palette values in `lib/app/theme/theme_preset.dart`.
- Map tokens to Flutter component themes in `lib/app/theme/app_theme.dart`.
- Custom-painted controls must use `AppTheme` context helpers instead of fixed
  radii or independent selected colors. Do not cache tokens outside `build`.
- Do not branch page state, controllers, keyboard handling, or data loading by
  visual profile. OS window controls continue to depend on the actual platform.

This is a shared-widget visual adaptation, not three native widget libraries.
All profiles use opaque chrome on every platform, without native Mica or
focus-dependent backdrop changes. The table body remains opaque. There are no
per-cell blur filters or additional native material dependencies.
System fonts remain platform-appropriate unless the user chooses a font.

## References

- Material components: https://docs.flutter.dev/ui/widgets/material
- macOS components: https://github.com/GroovinChip/macos_ui
- Fluent components: https://pub.dev/packages/fluent_ui

## Verification

`flutter test test/component_style_test.dart` verifies component geometry,
selection states, dark mode, custom accents, and state-preserving style changes.
`flutter test test/workspace_material_ui_test.dart` renders all six style and
brightness combinations at standard and compact window sizes. To capture them:

```powershell
flutter test test/workspace_material_ui_test.dart --dart-define=UI_CAPTURE_DIR=build/ui-previews
```
