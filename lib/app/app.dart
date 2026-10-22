import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:snap_layouts/snap_layouts.dart';
import 'package:window_manager/window_manager.dart';

import '../app/state/app_controller.dart';
import 'l10n/app_strings.dart';
import '../app/state/theme_controller.dart';
import '../app/theme/app_theme.dart';
import '../domain/models/project.dart';
import '../ui/widgets/theme_settings_dialog.dart';
import '../ui/widgets/chrome_surface.dart';
import '../ui/widgets/user_guide.dart';
import '../ui/widgets/support_author_dialog.dart';
import '../ui/widgets/app_about_dialog.dart';
import '../ui/views/database_management_page.dart';
import '../ui/views/project_list_view.dart';
import '../ui/views/project_workspace_view.dart';

class PdmReaderApp extends StatelessWidget {
  const PdmReaderApp({
    super.key,
    this.controller,
    this.startup,
    required this.themeController,
  }) : assert((controller == null) != (startup == null));

  final AppController? controller;
  final Future<AppController>? startup;
  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'PDM Viewer',
          debugShowCheckedModeBanner: false,
          locale: themeController.locale,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: themeController.themeMode,
          theme: AppTheme.build(
            contrast: themeController.contrast,
            accentColor: themeController.accentColor,
            presetId: themeController.presetId,
            seedColor: themeController.seedColor,
            fontFamily: themeController.fontFamily,
            brightness: Brightness.light,
            backgroundColor: themeController.customBackgroundColor,
            foregroundColor: themeController.customForegroundColor,
          ),
          darkTheme: AppTheme.build(
            contrast: themeController.contrast,
            accentColor: themeController.accentColor,
            presetId: themeController.presetId,
            seedColor: themeController.seedColor,
            fontFamily: themeController.fontFamily,
            brightness: Brightness.dark,
            backgroundColor: themeController.customBackgroundColor,
            foregroundColor: themeController.customForegroundColor,
          ),
          builder: (context, child) => _WindowsSemanticsWorkaround(
            child: child ?? const SizedBox.shrink(),
          ),
          home: startup == null
              ? ProjectShell(
                  controller: controller!,
                  themeController: themeController,
                )
              : _StartupHome(
                  startup: startup!,
                  themeController: themeController,
                ),
        );
      },
    );
  }
}

class _StartupHome extends StatelessWidget {
  const _StartupHome({required this.startup, required this.themeController});

  final Future<AppController> startup;
  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppController>(
      future: startup,
      builder: (context, snapshot) {
        final ready = snapshot.hasData;
        return ColoredBox(
          key: const ValueKey('startup-background'),
          color: themeController.resolvedBackgroundColor,
          child: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: ready
                ? ProjectShell(
                    key: const ValueKey('home'),
                    controller: snapshot.data!,
                    themeController: themeController,
                  )
                : _StartupPlaceholder(error: snapshot.error),
          ),
        );
      },
    );
  }
}

class _StartupPlaceholder extends StatelessWidget {
  const _StartupPlaceholder({this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppTheme.backgroundGradient(context),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 42),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 260,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PDM Viewer',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 28),
                          for (final width in [180.0, 140.0, 160.0])
                            Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: Container(
                                width: width,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: colors.onSurface.withValues(
                                    alpha: 0.06,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 10),
                  Expanded(
                    child: Center(
                      child: error == null
                          ? LText(
                              '正在加载项目…',
                              style: TextStyle(color: colors.onSurfaceVariant),
                            )
                          : Padding(
                              padding: const EdgeInsets.all(24),
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  context.tr('应用启动失败，请检查配置或数据文件。\n\n$error'),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProjectShell extends StatefulWidget {
  const ProjectShell({
    super.key,
    required this.controller,
    required this.themeController,
  });

  final AppController controller;
  final ThemeController themeController;

  @override
  State<ProjectShell> createState() => _ProjectShellState();
}

class _ProjectShellState extends State<ProjectShell> with WindowListener {
  static const double _minSidebarWidth = 240;
  static const double _maxSidebarWidth = 400;
  static const double _dividerWidth = 10;
  static const double _titleBarHeight = 42;
  static const Duration _sidebarAnimationDuration = Duration(milliseconds: 220);

  double _sidebarWidth = 260;
  bool _startupPromptVisible = false;
  bool _startupGuideChecked = false;
  bool _userGuideVisible = false;
  final UserGuideController _userGuide = UserGuideController();
  bool _isMaximized = false;
  bool _sidebarVisible = true;
  bool _manualStartupCheckInProgress = false;
  bool _isResizingSidebar = false;
  _ShellContent _activeContent = _ShellContent.workspace;
  DatabaseManagementSection _databaseSection =
      DatabaseManagementSection.drivers;
  final _databasePageKey = GlobalKey<DatabaseManagementPageState>();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _syncWindowState();
      if (!mounted) return;
      if (!widget.controller.hasSeenUserGuide) await _showUserGuide();
      if (!mounted) return;
      _startupGuideChecked = true;
      _handleControllerChanged();
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    widget.controller.removeListener(_handleControllerChanged);
    _userGuide.dispose();
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (!mounted) {
      return;
    }
    setState(() {
      _isMaximized = true;
    });
  }

  @override
  void onWindowUnmaximize() {
    if (!mounted) {
      return;
    }
    setState(() {
      _isMaximized = false;
    });
  }

  @override
  void onWindowRestore() {
    if (!mounted) {
      return;
    }
    setState(() {
      _isMaximized = false;
    });
  }

  Future<void> _syncWindowState() async {
    final maximized = await windowManager.isMaximized();
    if (!mounted) {
      return;
    }
    setState(() {
      _isMaximized = maximized;
    });
  }

  void _handleControllerChanged() {
    if (!_startupGuideChecked ||
        _userGuideVisible ||
        _startupPromptVisible ||
        _manualStartupCheckInProgress ||
        !widget.controller.hasPendingStartupReloadPrompt ||
        widget.controller.pendingStartupFileChanges.isEmpty ||
        !mounted) {
      return;
    }

    _showStartupReloadPrompt();
  }

  Future<void> _showUserGuide() async {
    if (_userGuideVisible || _startupPromptVisible || !mounted) return;
    _userGuideVisible = true;
    try {
      final waitForSidebar = !_sidebarVisible;
      setState(() {
        _sidebarVisible = true;
        _activeContent = _ShellContent.workspace;
      });
      if (!widget.controller.isRootExpanded) {
        widget.controller.toggleRootExpansion();
      }
      if (waitForSidebar) await Future<void>.delayed(_sidebarAnimationDuration);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await _userGuide.start();
      if (!mounted) return;
      if (!widget.controller.hasSeenUserGuide) {
        await widget.controller.markUserGuideSeen();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: LText('向导状态保存失败，下次启动可能再次显示。')));
      }
    } finally {
      _userGuideVisible = false;
      _handleControllerChanged();
    }
  }

  Future<void> _showStartupReloadPrompt() async {
    if (_startupPromptVisible || !mounted) {
      return;
    }

    _startupPromptVisible = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _startupPromptVisible = false;
        return;
      }

      final shouldReload = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _StartupPdmReloadDialog(
          changes: widget.controller.pendingStartupFileChanges,
        ),
      );

      _startupPromptVisible = false;
      if (!mounted) {
        return;
      }

      if (shouldReload == true) {
        await widget.controller.reloadChangedPdmFiles();
      } else {
        widget.controller.dismissStartupReloadPrompt();
      }
    });
  }

  Future<void> _checkPdmChangesFromMenu() async {
    if (_startupPromptVisible || _manualStartupCheckInProgress) {
      return;
    }

    _manualStartupCheckInProgress = true;
    try {
      await widget.controller.checkForChangedPdmFilesOnStartup();
      if (!mounted) {
        return;
      }

      if (widget.controller.pendingStartupFileChanges.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: LText('未检测到 PDM 文件变更。')));
        return;
      }

      await _showStartupReloadPrompt();
    } finally {
      _manualStartupCheckInProgress = false;
    }
  }

  void _resizeSidebar(double delta, double totalWidth) {
    final maxWidth = (totalWidth * 0.6).clamp(
      _minSidebarWidth,
      _maxSidebarWidth,
    );
    setState(() {
      _sidebarWidth = (_sidebarWidth + delta).clamp(_minSidebarWidth, maxWidth);
    });
  }

  Future<void> _showThemeColorDialog() async {
    final appearance = await showDialog<ThemeSettingsSelection>(
      context: context,
      builder: (dialogContext) => ThemeSettingsDialog(
        initial: ThemeSettingsSelection(
          contrast: widget.themeController.contrast,
          accentColor: widget.themeController.accentColor,
          presetId: widget.themeController.presetId,
          seedColor: widget.themeController.seedColor,
          fontFamily: widget.themeController.fontFamily,
          brightness: widget.themeController.brightness,
          themeMode: widget.themeController.themeMode,
          backgroundColor: widget.themeController.customBackgroundColor,
          foregroundColor: widget.themeController.customForegroundColor,
        ),
      ),
    );

    if (appearance != null) {
      await widget.themeController.setAppearance(
        contrast: appearance.contrast,
        accentColor: appearance.accentColor,
        presetId: appearance.presetId,
        seedColor: appearance.seedColor,
        brightness: appearance.brightness,
        themeMode: appearance.themeMode,
        backgroundColor: appearance.backgroundColor,
        foregroundColor: appearance.foregroundColor,
        fontFamily: appearance.fontFamily,
      );
    }
  }

  Future<void> _showAboutDialog() async {
    await showAppAboutDialog(context);
  }

  Future<void> _openDatabasePage(DatabaseManagementSection section) async {
    if (!mounted) {
      return;
    }
    final page = _databasePageKey.currentState;
    if (_activeContent == _ShellContent.database && page != null) {
      if (await page.selectSection(section) && mounted) {
        _databaseSection = section;
      }
      return;
    }
    setState(() {
      _activeContent = _ShellContent.database;
      _databaseSection = section;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return UserGuideScope(
          controller: _userGuide,
          child: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                _WindowsSemanticsWorkaround(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: AppTheme.backgroundGradient(context),
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Column(
                        children: [
                          _WindowMenuBar(
                            height: _titleBarHeight,
                            isMaximized: _isMaximized,
                            onThemePressed: _showThemeColorDialog,
                            onCheckPdmChanges: _checkPdmChangesFromMenu,
                            onShowAbout: _showAboutDialog,
                            onShowUserGuide: _showUserGuide,
                            locale: widget.themeController.locale,
                            onLocaleChanged: (locale) async {
                              try {
                                await widget.themeController.setLocale(locale);
                              } catch (error) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '${context.tr('语言设置保存失败')}\n$error',
                                    ),
                                  ),
                                );
                              }
                            },
                            onShowDrivers: () => _openDatabasePage(
                              DatabaseManagementSection.drivers,
                            ),
                            onShowDataSources: () => _openDatabasePage(
                              DatabaseManagementSection.dataSources,
                            ),
                            onShowReverse: () => _openDatabasePage(
                              DatabaseManagementSection.reverse,
                            ),
                            sidebarVisible: _sidebarVisible,
                            onToggleSidebar: () {
                              setState(() {
                                _sidebarVisible = !_sidebarVisible;
                              });
                            },
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final availableWidth = constraints.maxWidth;
                                final maxSidebarWidth = (availableWidth * 0.6)
                                    .clamp(_minSidebarWidth, _maxSidebarWidth);
                                final sidebarWidth = _sidebarWidth.clamp(
                                  _minSidebarWidth,
                                  maxSidebarWidth,
                                );

                                if (_activeContent == _ShellContent.database) {
                                  return DatabaseManagementPage(
                                    key: _databasePageKey,
                                    controller: widget.controller,
                                    initialSection: _databaseSection,
                                    onBack: () {
                                      setState(() {
                                        _activeContent =
                                            _ShellContent.workspace;
                                      });
                                    },
                                  );
                                }

                                return Stack(
                                  children: [
                                    Row(
                                      children: [
                                        AnimatedContainer(
                                          duration: _isResizingSidebar
                                              ? Duration.zero
                                              : _sidebarAnimationDuration,
                                          curve: Curves.easeOutCubic,
                                          width: _sidebarVisible
                                              ? sidebarWidth
                                              : 0,
                                          child: ClipRect(
                                            child: OverflowBox(
                                              alignment: Alignment.centerLeft,
                                              minWidth: 0,
                                              maxWidth: sidebarWidth,
                                              child: SizedBox(
                                                width: sidebarWidth,
                                                child: IgnorePointer(
                                                  ignoring: !_sidebarVisible,
                                                  child: ProjectListView(
                                                    controller:
                                                        widget.controller,
                                                    suppressHover:
                                                        _isResizingSidebar,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: ProjectWorkspaceView(
                                            controller: widget.controller,
                                          ),
                                        ),
                                      ],
                                    ),
                                    AnimatedPositioned(
                                      duration: _isResizingSidebar
                                          ? Duration.zero
                                          : _sidebarAnimationDuration,
                                      curve: Curves.easeOutCubic,
                                      left:
                                          (_sidebarVisible ? sidebarWidth : 0) -
                                          _dividerWidth / 2,
                                      top: 0,
                                      bottom: 0,
                                      width: _dividerWidth,
                                      child: IgnorePointer(
                                        ignoring: !_sidebarVisible,
                                        child: _DragDivider(
                                          onDrag: (delta) => _resizeSidebar(
                                            delta.dx,
                                            constraints.maxWidth,
                                          ),
                                          onDragStateChanged: (dragging) {
                                            if (_isResizingSidebar ==
                                                    dragging ||
                                                !mounted) {
                                              return;
                                            }
                                            setState(
                                              () =>
                                                  _isResizingSidebar = dragging,
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: _WindowsSemanticsWorkaround(
                    child: UserGuideOverlay(
                      controller: _userGuide,
                      hasProjects: widget.controller.projects.isNotEmpty,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WindowMenuBar extends StatelessWidget {
  static const double _macosTrafficLightInset = 84;

  const _WindowMenuBar({
    required this.height,
    required this.isMaximized,
    required this.onThemePressed,
    required this.onCheckPdmChanges,
    required this.onShowAbout,
    required this.onShowUserGuide,
    required this.onShowDrivers,
    required this.onShowDataSources,
    required this.onShowReverse,
    required this.sidebarVisible,
    required this.onToggleSidebar,
    required this.locale,
    required this.onLocaleChanged,
  });

  final double height;
  final bool isMaximized;
  final Future<void> Function() onThemePressed;
  final Future<void> Function() onCheckPdmChanges;
  final Future<void> Function() onShowAbout;
  final Future<void> Function() onShowUserGuide;
  final Future<void> Function() onShowDrivers;
  final Future<void> Function() onShowDataSources;
  final Future<void> Function() onShowReverse;
  final bool sidebarVisible;
  final VoidCallback onToggleSidebar;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  Widget build(BuildContext context) {
    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    final brightness = Theme.of(context).brightness;

    return _WindowsSemanticsWorkaround(
      child: ChromeSurface(
        border: Border(
          bottom: BorderSide(color: AppTheme.outlineSoft(context)),
        ),
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              SizedBox(width: isMacOS ? _macosTrafficLightInset : 10),
              _WindowToggleButton(
                tooltip: sidebarVisible ? '隐藏项目树' : '显示项目树',
                icon: sidebarVisible
                    ? Icons.view_sidebar_outlined
                    : Icons.view_sidebar,
                selected: sidebarVisible,
                onPressed: onToggleSidebar,
              ),
              const SizedBox(width: 6),
              MenuBar(
                style: MenuStyle(
                  visualDensity: const VisualDensity(
                    horizontal: -2,
                    vertical: -2,
                  ),
                  padding: WidgetStateProperty.all(EdgeInsets.zero),
                  backgroundColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  surfaceTintColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  shadowColor: const WidgetStatePropertyAll(Colors.transparent),
                ),
                children: [
                  SubmenuButton(
                    menuChildren: [
                      MenuItemButton(
                        onPressed: onCheckPdmChanges,
                        child: const LText('检查 PDM 变更'),
                      ),
                      MenuItemButton(
                        onPressed: () async {
                          await windowManager.close();
                        },
                        child: const LText('退出'),
                      ),
                    ],
                    child: const LText('文件'),
                  ),
                  SubmenuButton(
                    menuChildren: [
                      MenuItemButton(
                        onPressed: onShowDrivers,
                        child: const LText('驱动管理'),
                      ),
                      MenuItemButton(
                        onPressed: onShowDataSources,
                        child: const LText('数据源管理'),
                      ),
                      MenuItemButton(
                        onPressed: onShowReverse,
                        child: const LText('逆向生成 PDM'),
                      ),
                    ],
                    child: const LText('数据库'),
                  ),
                  SubmenuButton(
                    menuChildren: [
                      MenuItemButton(
                        onPressed: onThemePressed,
                        child: const LText('主题'),
                      ),
                    ],
                    child: const UserGuideAnchor(
                      target: UserGuideTarget.theme,
                      child: LText('主题'),
                    ),
                  ),
                  SubmenuButton(
                    menuChildren: [
                      MenuItemButton(
                        onPressed: onShowUserGuide,
                        child: const LText('使用向导'),
                      ),
                      SubmenuButton(
                        menuChildren: [
                          for (final language in const {
                            'zh': '简体中文',
                            'en': 'English',
                          }.entries)
                            MenuItemButton(
                              leadingIcon: SizedBox(
                                width: 18,
                                child: locale.languageCode == language.key
                                    ? const Icon(Icons.check, size: 18)
                                    : null,
                              ),
                              onPressed: () =>
                                  onLocaleChanged(Locale(language.key)),
                              child: Text(language.value),
                            ),
                        ],
                        child: const LText('语言'),
                      ),
                      MenuItemButton(
                        onPressed: onShowAbout,
                        child: const LText('关于'),
                      ),
                      MenuItemButton(
                        onPressed: () => showSupportAuthorDialog(context),
                        child: const LText('赞赏作者'),
                      ),
                    ],
                    child: const UserGuideAnchor(
                      target: UserGuideTarget.help,
                      child: LText('帮助'),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DragToMoveArea(
                  child: Container(
                    height: double.infinity,
                    color: Colors.transparent,
                  ),
                ),
              ),
              if (!isMacOS) ...[
                _WindowActionButton(
                  tooltip: context.tr('最小化'),
                  icon: Icons.remove,
                  onPressed: () async {
                    await windowManager.minimize();
                  },
                ),
                if (isWindows)
                  SizedBox(
                    width: 46,
                    height: 32,
                    child: isMaximized
                        ? SnapLayoutsButton.unmaximize(
                            brightness: brightness,
                            onPressed: () async {
                              await windowManager.unmaximize();
                            },
                          )
                        : SnapLayoutsButton.maximize(
                            brightness: brightness,
                            onPressed: () async {
                              await windowManager.maximize();
                            },
                          ),
                  )
                else
                  _WindowActionButton(
                    tooltip: isMaximized ? '还原' : '最大化',
                    icon: isMaximized ? Icons.filter_none : Icons.crop_square,
                    onPressed: () async {
                      if (isMaximized) {
                        await windowManager.unmaximize();
                      } else {
                        await windowManager.maximize();
                      }
                    },
                  ),
                _WindowActionButton(
                  tooltip: context.tr('关闭'),
                  icon: Icons.close,
                  hoverColor: const Color(0xFFE81123),
                  hoverForegroundColor: Colors.white,
                  onPressed: () async {
                    await windowManager.close();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _ShellContent { workspace, database }

class _WindowsSemanticsWorkaround extends StatelessWidget {
  const _WindowsSemanticsWorkaround({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return child;
    }
    return ExcludeSemantics(child: child);
  }
}

class _WindowActionButton extends StatefulWidget {
  const _WindowActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.hoverColor,
    this.hoverForegroundColor,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onPressed;
  final Color? hoverColor;
  final Color? hoverForegroundColor;

  @override
  State<_WindowActionButton> createState() => _WindowActionButtonState();
}

class _WindowToggleButton extends StatefulWidget {
  const _WindowToggleButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  State<_WindowToggleButton> createState() => _WindowToggleButtonState();
}

class _WindowToggleButtonState extends State<_WindowToggleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final fillColor = widget.selected
        ? AppTheme.selectionFill(context)
        : (_hovered ? AppTheme.hoverFill(context) : Colors.transparent);
    final foregroundColor = widget.selected
        ? AppTheme.primaryOf(context)
        : Theme.of(context).colorScheme.onSurface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: IconButton(
        tooltip: context.tr(widget.tooltip),
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        constraints: const BoxConstraints.tightFor(width: 34, height: 28),
        padding: EdgeInsets.zero,
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: AppTheme.controlRadiusOf(context),
            ),
          ),
          backgroundColor: WidgetStateProperty.all(fillColor),
          foregroundColor: WidgetStateProperty.all(foregroundColor),
          side: WidgetStateProperty.all(
            BorderSide(color: AppTheme.outlineSoft(context)),
          ),
        ),
        onPressed: widget.onPressed,
        icon: Icon(widget.icon, size: 16),
      ),
    );
  }
}

class _WindowActionButtonState extends State<_WindowActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.hoverColor ?? AppTheme.hoverFill(context);
    final hoverForegroundColor =
        widget.hoverForegroundColor ?? AppTheme.primaryOf(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: IconButton(
        tooltip: context.tr(widget.tooltip),
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        constraints: const BoxConstraints.tightFor(width: 40, height: 32),
        padding: EdgeInsets.zero,
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: AppTheme.controlRadiusOf(context),
            ),
          ),
          backgroundColor: WidgetStateProperty.all(
            _hovered ? hoverColor : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.all(
            _hovered
                ? hoverForegroundColor
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        onPressed: () async {
          await widget.onPressed();
        },
        icon: Icon(widget.icon, size: 16),
      ),
    );
  }
}

class _StartupPdmReloadDialog extends StatelessWidget {
  const _StartupPdmReloadDialog({required this.changes});

  final List<StartupPdmChange> changes;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const LText('检测到 PDM 文件变更'),
      content: SizedBox(
        width: 760,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LText('以下文件与上次成功导入时相比已发生变化，是否重新加载这些文件？'),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: changes.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = changes[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            item.projectName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: Text(
                            item.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 4,
                          child: SelectableText(item.path, maxLines: 1),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: Text(
                            context.tr(_startupChangeStatusLabel(item.status)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const LText('暂不处理'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const LText('重新加载'),
        ),
      ],
    );
  }
}

String _startupChangeStatusLabel(StartupPdmChangeStatus status) {
  switch (status) {
    case StartupPdmChangeStatus.modified:
      return '内容已变更';
    case StartupPdmChangeStatus.missingOrUnreadable:
      return '文件不存在或无读取权限';
    case StartupPdmChangeStatus.baselineMissing:
      return '尚未建立导入基线';
  }
}

class _DragDivider extends StatelessWidget {
  const _DragDivider({required this.onDrag, required this.onDragStateChanged});

  final ValueChanged<Offset> onDrag;
  final ValueChanged<bool> onDragStateChanged;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => onDragStateChanged(true),
        onPanUpdate: (details) => onDrag(details.delta),
        onPanEnd: (_) => onDragStateChanged(false),
        onPanCancel: () => onDragStateChanged(false),
        child: SizedBox(
          width: _ProjectShellState._dividerWidth,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
