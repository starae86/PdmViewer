import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../app/l10n/app_strings.dart';

import '../../app/theme/app_theme.dart';

enum UserGuideTarget { createProject, importPdm, search, theme, help }

class UserGuideController extends ChangeNotifier {
  final _keys = {
    for (final target in UserGuideTarget.values)
      target: GlobalKey(debugLabel: 'guide-${target.name}'),
  };
  bool active = false;
  bool suspended = false;
  int step = 0;
  int session = 0;
  Completer<void>? _completion;

  UserGuideTarget get target => UserGuideTarget.values[step];
  GlobalKey keyFor(UserGuideTarget target) => _keys[target]!;

  Future<void> start() {
    if (active) return _completion!.future;
    _completion = Completer<void>();
    active = true;
    suspended = false;
    step = 0;
    session++;
    notifyListeners();
    return _completion!.future;
  }

  void finish() {
    if (!active) return;
    active = false;
    suspended = false;
    _completion?.complete();
    notifyListeners();
  }

  void next() {
    if (step == UserGuideTarget.values.length - 1) {
      finish();
    } else {
      step++;
      notifyListeners();
    }
  }

  void previous() {
    if (step == 0) return;
    step--;
    notifyListeners();
  }

  Future<void> performAction(
    UserGuideTarget action,
    Future<void> Function() callback, {
    required bool Function() shouldAdvance,
  }) async {
    final guided = active && target == action;
    if (guided) {
      suspended = true;
      notifyListeners();
    }
    try {
      await callback();
    } finally {
      if (guided && active) {
        suspended = false;
        if (shouldAdvance()) {
          next();
        } else {
          notifyListeners();
        }
      }
    }
  }

  @override
  void dispose() {
    if (active) _completion?.complete();
    active = false;
    super.dispose();
  }
}

class UserGuideScope extends InheritedNotifier<UserGuideController> {
  const UserGuideScope({
    super.key,
    required UserGuideController controller,
    required super.child,
  }) : super(notifier: controller);

  static UserGuideController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UserGuideScope>()?.notifier;
}

class UserGuideAnchor extends StatelessWidget {
  const UserGuideAnchor({super.key, required this.target, required this.child});

  final UserGuideTarget target;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final guide = UserGuideScope.maybeOf(context);
    return guide == null
        ? child
        : SizedBox(key: guide.keyFor(target), child: child);
  }
}

/// Lives inside the shell so native pickers and dialog routes stay above it.
class UserGuideOverlay extends StatefulWidget {
  const UserGuideOverlay({
    super.key,
    required this.controller,
    required this.hasProjects,
  });

  final UserGuideController controller;
  final bool hasProjects;

  @override
  State<UserGuideOverlay> createState() => _UserGuideOverlayState();
}

class _UserGuideOverlayState extends State<UserGuideOverlay>
    with WidgetsBindingObserver {
  final _overlayKey = GlobalKey();
  Rect? _targetRect;
  Size? _bubbleSize;
  final _bubbleKey = GlobalKey();
  bool _measurementScheduled = false;
  Timer? _retryTimer;
  int _measurementRetries = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onStepChanged);
  }

  void _onStepChanged() {
    _retryTimer?.cancel();
    _measurementRetries = 0;
    // Keep the current geometry until the next layout has been measured.
    // Clearing it paints a fully dark scrim and a fallback bubble for one frame.
    if (!widget.controller.active || widget.controller.suspended) {
      _targetRect = null;
      _bubbleSize = null;
    }
    setState(() {});
  }

  @override
  void didChangeMetrics() => _scheduleMeasurement();

  void _scheduleMeasurement() {
    if (_measurementScheduled) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted ||
          !widget.controller.active ||
          widget.controller.suspended) {
        return;
      }
      final origin =
          _overlayKey.currentContext?.findRenderObject() as RenderBox?;
      final target =
          widget.controller
                  .keyFor(widget.controller.target)
                  .currentContext
                  ?.findRenderObject()
              as RenderBox?;
      final bubble =
          _bubbleKey.currentContext?.findRenderObject() as RenderBox?;
      if (origin == null ||
          target == null ||
          !origin.hasSize ||
          !target.hasSize) {
        if (_measurementRetries++ < 20) {
          _retryTimer = Timer(const Duration(milliseconds: 50), () {
            if (mounted) setState(() {});
          });
        }
        return;
      }
      final rect =
          origin.globalToLocal(target.localToGlobal(Offset.zero)) & target.size;
      final size = bubble?.hasSize == true ? bubble!.size : null;
      if (_targetRect != rect || _bubbleSize != size) {
        setState(() {
          _targetRect = rect;
          _bubbleSize = size;
        });
      }
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onStepChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guide = widget.controller;
    if (!guide.active || guide.suspended) return const SizedBox.shrink();
    _scheduleMeasurement();
    final theme = Theme.of(context);
    final titles = ['新建项目', '导入 PDM', '搜索表和字段', '设置主题', '随时重看向导'];
    final descriptions = [
      '点击这里的 + 创建项目。操作按钮平时在鼠标悬浮时显示，向导中会保持可见。',
      '点击项目旁的 +，选择一个或多个 PDM 文件。导入完成后即可查看表结构；也可以点“下一步”先了解搜索。',
      '在这里输入表名、表注释或字段编码。右侧可切换搜索范围和表 / 字段。点击结果中的表名链接打开详情。',
      '从这里调整界面风格、浅色 / 深色模式、主题色和字体。设置会自动保存。',
      '以后可从“帮助 → 使用向导”重新查看。数据库逆向是可选功能，不影响日常查看 PDM。',
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = Offset.zero & constraints.biggest;
        final rawRect = _targetRect;
        final clippedTarget = rawRect?.inflate(4).intersect(bounds);
        final target = clippedTarget?.isEmpty == false ? clippedTarget : null;
        final width = math.min(340.0, constraints.maxWidth - 24);
        final bubbleHeight = _bubbleSize?.height ?? 240;
        final below =
            target == null ||
            target.bottom + 16 + bubbleHeight <= constraints.maxHeight - 12;
        final bubbleLeft = ((target?.left ?? 12) - 8)
            .clamp(12.0, math.max(12.0, constraints.maxWidth - width - 12))
            .toDouble();
        final bubbleTop =
            (target == null
                    ? 80.0
                    : below
                    ? target.bottom + 16
                    : target.top - bubbleHeight - 16)
                .clamp(
                  12.0,
                  math.max(12.0, constraints.maxHeight - bubbleHeight - 12),
                )
                .toDouble();
        // Measure the initial coachmark without painting fallback geometry.
        // Offstage still lays out the bubble and overlay for the next frame.
        return Offstage(
          offstage: target == null || _bubbleSize == null,
          child: Stack(
            key: _overlayKey,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _GuideScrimPainter(target: target),
                  ),
                ),
              ),
              // Only the highlighted control and the coachmark accept pointer input.
              if (target != null) ...[
                _block(Rect.fromLTRB(0, 0, bounds.width, target.top)),
                _block(
                  Rect.fromLTRB(0, target.bottom, bounds.width, bounds.height),
                ),
                _block(
                  Rect.fromLTRB(0, target.top, target.left, target.bottom),
                ),
                _block(
                  Rect.fromLTRB(
                    target.right,
                    target.top,
                    bounds.width,
                    target.bottom,
                  ),
                ),
                Positioned.fromRect(
                  rect: target,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: const ValueKey('user-guide-highlight'),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
                        borderRadius: AppTheme.controlRadiusOf(context),
                      ),
                    ),
                  ),
                ),
              ] else
                _block(bounds),
              if (target != null)
                Positioned(
                  left: (target.center.dx - 8).clamp(
                    bubbleLeft + 16,
                    bubbleLeft + width - 32,
                  ),
                  top: below ? bubbleTop - 8 : bubbleTop + bubbleHeight - 8,
                  child: IgnorePointer(
                    child: Transform.rotate(
                      angle: math.pi / 4,
                      child: ColoredBox(
                        color: theme.colorScheme.surfaceContainerHigh,
                        child: const SizedBox.square(dimension: 16),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: bubbleLeft,
                top: bubbleTop,
                width: width,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight - 24,
                  ),
                  child: Material(
                    key: _bubbleKey,
                    color: theme.colorScheme.surfaceContainerHigh,
                    elevation: 4,
                    shadowColor: theme.colorScheme.shadow.withValues(
                      alpha: 0.16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppTheme.controlRadiusOf(context),
                      side: BorderSide(color: AppTheme.outlineSoft(context)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  context.tr(titles[guide.step]),
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              Text(
                                '${guide.step + 1} / 5',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Flexible(
                            child: SingleChildScrollView(
                              child: Text(
                                context.tr(descriptions[guide.step]),
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ),
                          if (guide.step == 0 && !widget.hasProjects) ...[
                            const SizedBox(height: 8),
                            LText(
                              '创建项目后继续，也可以跳过向导。',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              alignment: WrapAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: guide.finish,
                                  child: const LText('跳过向导'),
                                ),
                                if (guide.step > 0)
                                  TextButton(
                                    onPressed: guide.previous,
                                    child: const LText('上一步'),
                                  ),
                                FilledButton(
                                  onPressed:
                                      guide.step == 0 && !widget.hasProjects
                                      ? null
                                      : guide.next,
                                  child: LText(guide.step == 4 ? '完成' : '下一步'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _block(Rect rect) => Positioned.fromRect(
    rect: rect,
    child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {}),
  );
}

class _GuideScrimPainter extends CustomPainter {
  const _GuideScrimPainter({required this.target});

  final Rect? target;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    if (target != null) path.addRect(target!);
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: 0.32),
    );
  }

  @override
  bool shouldRepaint(_GuideScrimPainter oldDelegate) =>
      oldDelegate.target != target;
}
