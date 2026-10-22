import 'package:flutter/material.dart';
import '../../app/l10n/app_strings.dart';

import '../../app/state/app_controller.dart';
import '../../app/theme/app_theme.dart';
import '../widgets/chrome_surface.dart';
import '../widgets/user_guide.dart';
import '../../domain/models/project.dart';
import 'project_workspace_view.dart';

class ProjectListView extends StatelessWidget {
  const ProjectListView({
    super.key,
    required this.controller,
    this.suppressHover = false,
  });

  final AppController controller;
  final bool suppressHover;

  @override
  Widget build(BuildContext context) {
    return ChromeSurface(
      child: Column(
        children: [
          _ProjectTreeRootNode(
            expanded: controller.isRootExpanded,
            suppressHover: suppressHover,
            onToggleExpanded: controller.toggleRootExpansion,
            onExpandAll: controller.expandAllProjectNodes,
            onCollapseAll: controller.collapseAllProjectNodes,
            onLocateActivePdm: () => _locateActivePdm(context),
            onCreateProject: () => _createProject(context),
          ),
          Expanded(
            child: controller.isRootExpanded
                ? _ProjectTreeBody(
                    controller: controller,
                    suppressHover: suppressHover,
                    onCreateProject: () => _createProject(context),
                    onEditProject: (project) => _showProjectDialog(
                      context,
                      title: '修改项目名称',
                      initialValue: project.name,
                      onSubmit: (value) =>
                          controller.renameProject(project.id, value),
                    ),
                    onDeleteProject: (project) =>
                        _confirmDeleteProject(context, project),
                    onImportPdm: (project) => _importPdm(context, project),
                    onPreviewProject: (project) =>
                        _previewProjectSql(context, project),
                    onProjectSecondaryTapDown: (project, globalPosition) =>
                        _showProjectContextMenu(
                          context,
                          project,
                          globalPosition,
                        ),
                    onDeletePdm: (project, file) =>
                        _confirmDeletePdm(context, project, file),
                    onPreviewPdm: (project, file) =>
                        _previewPdmSql(context, project, file),
                    onPdmSecondaryTapDown: (project, file, globalPosition) =>
                        _showPdmContextMenu(
                          context,
                          project,
                          file,
                          globalPosition,
                        ),
                    onOpenPdmFolder: (file) => _openPdmFolder(context, file),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _createProject(BuildContext context) async {
    final guide = UserGuideScope.maybeOf(context);
    final before = controller.projects.length;
    Future<void> create() => _showProjectDialog(
      context,
      title: '新建项目',
      onSubmit: controller.createProject,
    );
    if (guide == null) {
      await create();
    } else {
      await guide.performAction(
        UserGuideTarget.createProject,
        create,
        shouldAdvance: () => controller.projects.length > before,
      );
    }
  }

  Future<void> _locateActivePdm(BuildContext context) async {
    final fileId = await controller.locateActiveTablePdm();
    if (fileId == null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: LText('当前没有已打开的表详情。')));
    }
  }

  Future<void> _showProjectDialog(
    BuildContext context, {
    required String title,
    String initialValue = '',
    required Future<String?> Function(String value) onSubmit,
  }) async {
    final inputController = TextEditingController(text: initialValue);
    final messenger = ScaffoldMessenger.of(context);
    Future<String?>? pendingSubmit;

    Future<void> submit(BuildContext dialogContext) async {
      final value = inputController.text.trim();
      if (value.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: LText('项目名称不能为空。')));
        return;
      }

      Navigator.of(dialogContext).pop();
      pendingSubmit = onSubmit(value);
      final error = await pendingSubmit;
      if (error != null && context.mounted) {
        messenger.showSnackBar(SnackBar(content: LText(error)));
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: LText(title),
          content: TextField(
            controller: inputController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: context.tr('项目名称'),
              hintText: context.tr('例如：API 管理 / 财务中台'),
              isDense: true,
            ),
            onSubmitted: (_) => submit(dialogContext),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const LText('取消'),
            ),
            FilledButton(
              onPressed: () => submit(dialogContext),
              child: const LText('保存'),
            ),
          ],
        );
      },
    );
    await pendingSubmit;
  }

  Future<void> _confirmDeleteProject(
    BuildContext context,
    ProjectRecord project,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const LText('删除项目'),
              content: LText('确认删除项目“${project.name}”吗？其关联的 PDM 和索引会一并清理。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const LText('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const LText('删除'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    final error = await controller.deleteProject(project.id);
    if (error != null && context.mounted) {
      messenger.showSnackBar(SnackBar(content: LText(error)));
    }
  }

  Future<void> _confirmDeletePdm(
    BuildContext context,
    ProjectRecord project,
    ProjectPdmFileRecord file,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const LText('删除 PDM'),
              content: LText(
                '确认将“${file.displayName}”从项目“${project.name}”中移除吗？',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const LText('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const LText('移除'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    final error = await controller.removePdmFile(project.id, file);
    if (error != null && context.mounted) {
      messenger.showSnackBar(SnackBar(content: LText(error)));
    }
  }

  Future<void> _importPdm(BuildContext context, ProjectRecord project) async {
    final guide = UserGuideScope.maybeOf(context);
    final before = controller.projectFilesFor(project.id).length;
    Future<void> importFiles() async {
      final message = await controller.importPdmFilesForProject(
        project.id,
        dialogTitle: context.tr('选择一个或多个 PDM 文件'),
      );
      if (message != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LText(message)));
      }
    }

    if (guide == null) {
      await importFiles();
    } else {
      await guide.performAction(
        UserGuideTarget.importPdm,
        importFiles,
        shouldAdvance: () =>
            controller.projectFilesFor(project.id).length > before,
      );
    }
  }

  Future<void> _openPdmFolder(
    BuildContext context,
    ProjectPdmFileRecord file,
  ) async {
    final message = await controller.openPdmFolder(file.path);
    if (message != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: LText(message)));
    }
  }

  Future<void> _previewProjectSql(
    BuildContext context,
    ProjectRecord project,
  ) async {
    final targets = await controller.loadPreviewTargetsForProject(project.id);
    if (!context.mounted || targets.isEmpty) {
      return;
    }
    await showSqlPreviewDialog(
      context: context,
      targets: targets,
      loadDetail: controller.loadTableDetailForResult,
      loadDetails: controller.loadTableDetailsForResults,
      suggestedFileName: buildPreviewSuggestedFileNameForProject(project.name),
    );
  }

  Future<void> _previewPdmSql(
    BuildContext context,
    ProjectRecord project,
    ProjectPdmFileRecord file,
  ) async {
    final targets = await controller.loadPreviewTargetsForPdmFile(
      projectId: project.id,
      pdmFileId: file.id,
    );
    if (!context.mounted || targets.isEmpty) {
      return;
    }
    await showSqlPreviewDialog(
      context: context,
      targets: targets,
      loadDetail: controller.loadTableDetailForResult,
      loadDetails: controller.loadTableDetailsForResults,
      suggestedFileName: buildPreviewSuggestedFileNameForPdm(file.displayName),
    );
  }

  Future<void> _showProjectContextMenu(
    BuildContext context,
    ProjectRecord project,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem<String>(
          value: 'importPdm',
          height: 36,
          child: LText('新增 PDM'),
        ),
        PopupMenuItem<String>(
          value: 'renameProject',
          height: 36,
          child: LText('修改项目'),
        ),
        PopupMenuItem<String>(
          value: 'previewSql',
          height: 36,
          child: LText('预览 SQL'),
        ),
        PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'deleteProject',
          height: 36,
          child: LText('删除项目'),
        ),
      ],
    );
    if (!context.mounted) {
      return;
    }
    switch (action) {
      case 'importPdm':
        await _importPdm(context, project);
      case 'renameProject':
        await _showProjectDialog(
          context,
          title: '修改项目名称',
          initialValue: project.name,
          onSubmit: (value) => controller.renameProject(project.id, value),
        );
      case 'previewSql':
        await _previewProjectSql(context, project);
      case 'deleteProject':
        await _confirmDeleteProject(context, project);
    }
  }

  Future<void> _showPdmContextMenu(
    BuildContext context,
    ProjectRecord project,
    ProjectPdmFileRecord file,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem<String>(
          value: 'openFolder',
          height: 36,
          child: LText('打开所在文件夹'),
        ),
        PopupMenuItem<String>(
          value: 'previewSql',
          height: 36,
          child: LText('预览 SQL'),
        ),
        PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'deletePdm',
          height: 36,
          child: LText('删除 PDM'),
        ),
      ],
    );
    if (!context.mounted) {
      return;
    }
    switch (action) {
      case 'openFolder':
        await _openPdmFolder(context, file);
      case 'previewSql':
        await _previewPdmSql(context, project, file);
      case 'deletePdm':
        await _confirmDeletePdm(context, project, file);
    }
  }
}

class _ProjectTreeBody extends StatefulWidget {
  const _ProjectTreeBody({
    required this.controller,
    required this.suppressHover,
    required this.onCreateProject,
    required this.onEditProject,
    required this.onDeleteProject,
    required this.onImportPdm,
    required this.onPreviewProject,
    required this.onProjectSecondaryTapDown,
    required this.onDeletePdm,
    required this.onPreviewPdm,
    required this.onPdmSecondaryTapDown,
    required this.onOpenPdmFolder,
  });

  final AppController controller;
  final bool suppressHover;
  final VoidCallback onCreateProject;
  final ValueChanged<ProjectRecord> onEditProject;
  final ValueChanged<ProjectRecord> onDeleteProject;
  final ValueChanged<ProjectRecord> onImportPdm;
  final ValueChanged<ProjectRecord> onPreviewProject;
  final void Function(ProjectRecord project, Offset globalPosition)
  onProjectSecondaryTapDown;
  final void Function(ProjectRecord project, ProjectPdmFileRecord file)
  onDeletePdm;
  final void Function(ProjectRecord project, ProjectPdmFileRecord file)
  onPreviewPdm;
  final void Function(
    ProjectRecord project,
    ProjectPdmFileRecord file,
    Offset globalPosition,
  )
  onPdmSecondaryTapDown;
  final ValueChanged<ProjectPdmFileRecord> onOpenPdmFolder;

  @override
  State<_ProjectTreeBody> createState() => _ProjectTreeBodyState();
}

class _ProjectTreeBodyState extends State<_ProjectTreeBody> {
  final ScrollController _scrollController = ScrollController();
  String? _lastGuideStep;
  final Map<String, GlobalKey> _pdmNodeKeys = <String, GlobalKey>{};
  int _lastLocationVersion = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleLocationIfNeeded() {
    final version = widget.controller.treeLocationVersion;
    if (version == _lastLocationVersion) {
      return;
    }
    _lastLocationVersion = version;
    final fileId = widget.controller.selectedPdmFileId;
    if (fileId == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final targetContext = _pdmNodeKeys[fileId]?.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleLocationIfNeeded();
    final guide = UserGuideScope.maybeOf(context);
    final guideStep = guide?.active == true
        ? '${guide!.session}:${guide.step}'
        : null;
    if (guideStep != _lastGuideStep) {
      _lastGuideStep = guideStep;
      if (guide?.active == true && guide!.target == UserGuideTarget.importPdm) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
        });
      }
    }
    final controller = widget.controller;
    if (controller.projects.isEmpty) {
      return _SidebarEmptyState(onCreate: widget.onCreateProject);
    }

    final selectedProjectId = controller.selectedProject?.id;
    return ListView.separated(
      controller: _scrollController,
      itemCount: controller.projects.length,
      separatorBuilder: (_, _) => const SizedBox.shrink(),
      itemBuilder: (context, index) {
        final project = controller.projects[index];
        final projectSelected =
            selectedProjectId == project.id &&
            controller.selectedPdmFileId == null;
        final expanded = controller.isProjectExpanded(project.id);
        final files = controller.projectFilesFor(project.id);
        final importButton = _TreeActionButton(
          icon: Icons.add,
          tooltip: context.tr('新增 PDM'),
          onPressed: () => widget.onImportPdm(project),
        );

        return Column(
          children: [
            _ProjectTreeNodeRow(
              indentLevel: 1,
              forceActions:
                  index == 0 &&
                  guide?.active == true &&
                  guide!.target == UserGuideTarget.importPdm,
              suppressHover: widget.suppressHover,
              leadingIcon: expanded ? Icons.folder_open : Icons.folder_outlined,
              title: project.name,
              selected: projectSelected,
              onTap: () async {
                controller.toggleProjectExpansion(project.id);
                await controller.selectProject(project);
              },
              onSecondaryTapDown: (globalPosition) =>
                  widget.onProjectSecondaryTapDown(project, globalPosition),
              actions: [
                if (index == 0)
                  UserGuideAnchor(
                    target: UserGuideTarget.importPdm,
                    child: importButton,
                  )
                else
                  importButton,
                _TreeActionButton(
                  icon: Icons.code_outlined,
                  tooltip: context.tr('预览 SQL'),
                  onPressed: () => widget.onPreviewProject(project),
                ),
                _TreeActionButton(
                  icon: Icons.edit_outlined,
                  tooltip: context.tr('修改项目名称'),
                  onPressed: () => widget.onEditProject(project),
                ),
                _TreeActionButton(
                  icon: Icons.close,
                  tooltip: context.tr('删除项目'),
                  onPressed: () => widget.onDeleteProject(project),
                ),
              ],
              isExpandable: true,
              isExpanded: expanded,
              onToggleExpanded: () =>
                  controller.toggleProjectExpansion(project.id),
            ),
            if (expanded)
              for (final file in files) ...[
                _ProjectTreeNodeRow(
                  key: _pdmNodeKeys.putIfAbsent(file.id, GlobalKey.new),
                  indentLevel: 2,
                  suppressHover: widget.suppressHover,
                  leadingIcon: file.hasError
                      ? Icons.error_outline
                      : Icons.description_outlined,
                  title: file.displayName,
                  selected: controller.selectedPdmFileId == file.id,
                  titleColor: file.hasError
                      ? AppTheme.warningForeground(context)
                      : null,
                  onTap: () => controller.selectProjectFile(project, file.id),
                  onSecondaryTapDown: (globalPosition) => widget
                      .onPdmSecondaryTapDown(project, file, globalPosition),
                  actions: [
                    _TreeActionButton(
                      icon: Icons.code_outlined,
                      tooltip: context.tr('预览 SQL'),
                      onPressed: () => widget.onPreviewPdm(project, file),
                    ),
                    _TreeActionButton(
                      icon: Icons.folder_open_outlined,
                      tooltip: context.tr('打开所在文件夹'),
                      onPressed: () => widget.onOpenPdmFolder(file),
                    ),
                    _TreeActionButton(
                      icon: Icons.close,
                      tooltip: context.tr('删除 PDM'),
                      onPressed: () => widget.onDeletePdm(project, file),
                    ),
                  ],
                ),
              ],
          ],
        );
      },
    );
  }
}

class _ProjectTreeRootNode extends StatelessWidget {
  const _ProjectTreeRootNode({
    required this.expanded,
    required this.suppressHover,
    required this.onToggleExpanded,
    required this.onExpandAll,
    required this.onCollapseAll,
    required this.onLocateActivePdm,
    required this.onCreateProject,
  });

  final bool expanded;
  final bool suppressHover;
  final VoidCallback onToggleExpanded;
  final VoidCallback onExpandAll;
  final VoidCallback onCollapseAll;
  final VoidCallback onLocateActivePdm;
  final VoidCallback onCreateProject;

  @override
  Widget build(BuildContext context) {
    final guide = UserGuideScope.maybeOf(context);
    return _ProjectTreeNodeRow(
      indentLevel: 0,
      forceActions:
          guide?.active == true &&
          guide!.target == UserGuideTarget.createProject,
      suppressHover: suppressHover,
      leadingIcon: expanded ? Icons.folder_open : Icons.folder_outlined,
      title: context.tr('项目'),
      selected: false,
      onTap: onToggleExpanded,
      actions: [
        UserGuideAnchor(
          target: UserGuideTarget.createProject,
          child: _TreeActionButton(
            icon: Icons.add,
            tooltip: context.tr('新增'),
            onPressed: onCreateProject,
          ),
        ),
        _TreeActionButton(
          icon: Icons.my_location_outlined,
          tooltip: context.tr('定位当前表所在 PDM'),
          onPressed: onLocateActivePdm,
        ),
        _TreeActionButton(
          icon: Icons.unfold_more,
          tooltip: context.tr('展开全部'),
          onPressed: onExpandAll,
        ),
        _TreeActionButton(
          icon: Icons.unfold_less,
          tooltip: context.tr('收缩全部'),
          onPressed: onCollapseAll,
        ),
      ],
      isExpandable: true,
      isExpanded: expanded,
      onToggleExpanded: onToggleExpanded,
    );
  }
}

class _ProjectTreeNodeRow extends StatefulWidget {
  const _ProjectTreeNodeRow({
    super.key,
    required this.indentLevel,
    required this.suppressHover,
    required this.leadingIcon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.onSecondaryTapDown,
    this.titleColor,
    this.actions = const [],
    this.isExpandable = false,
    this.isExpanded = false,
    this.onToggleExpanded,
    this.forceActions = false,
  });

  final int indentLevel;
  final bool suppressHover;
  final IconData leadingIcon;
  final String title;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onSecondaryTapDown;
  final Color? titleColor;
  final List<Widget> actions;
  final bool isExpandable;
  final bool isExpanded;
  final VoidCallback? onToggleExpanded;
  final bool forceActions;

  @override
  State<_ProjectTreeNodeRow> createState() => _ProjectTreeNodeRowState();
}

class _ProjectTreeNodeRowState extends State<_ProjectTreeNodeRow> {
  bool _hovered = false;

  @override
  void didUpdateWidget(covariant _ProjectTreeNodeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.suppressHover && _hovered) {
      _hovered = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final horizontalInset = 8.0 + (widget.indentLevel * 14);
    final isHovered = _hovered && !widget.suppressHover;
    final fillColor = widget.selected
        ? AppTheme.treeSelectionFill(context)
        : (isHovered
              ? AppTheme.treeNodeHoverFill(context)
              : AppTheme.treeNodeFill(context));
    final iconColor = widget.selected
        ? AppTheme.treeSelectionForeground(context)
        : AppTheme.treeNodeIcon(context);
    final titleColor = widget.selected
        ? AppTheme.treeSelectionForeground(context)
        : widget.titleColor;

    final showActions = isHovered || widget.forceActions;

    return MouseRegion(
      onEnter: widget.suppressHover
          ? null
          : (_) => setState(() => _hovered = true),
      onExit: widget.suppressHover
          ? null
          : (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(
          onTap: widget.onTap,
          onSecondaryTapDown: widget.onSecondaryTapDown == null
              ? null
              : (details) => widget.onSecondaryTapDown!(details.globalPosition),
          borderRadius: AppTheme.controlRadiusOf(context),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: AppTheme.controlRadiusOf(context),
              color: fillColor,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(horizontalInset, 5, 4, 5),
              child: Row(
                children: [
                  Icon(widget.leadingIcon, size: 16, color: iconColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: widget.selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: titleColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IgnorePointer(
                    ignoring: !showActions,
                    child: Opacity(
                      opacity: showActions ? 1 : 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...widget.actions,
                          if (widget.isExpandable)
                            _TreeActionButton(
                              icon: widget.isExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              tooltip: context.tr(
                                widget.isExpanded ? '收起' : '展开',
                              ),
                              onPressed: widget.onToggleExpanded,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TreeActionButton extends StatelessWidget {
  const _TreeActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      padding: const EdgeInsets.all(1),
      splashRadius: 16,
      onPressed: onPressed,
      tooltip: context.tr(tooltip),
      icon: Icon(icon, size: 16),
    );
  }
}

class _SidebarEmptyState extends StatelessWidget {
  const _SidebarEmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_rounded,
              size: 44,
              color: AppTheme.primaryOf(context),
            ),
            const SizedBox(height: 12),
            LText('还没有项目', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            LText(
              '点击上方根节点右侧的新增按钮，先创建项目，再为项目添加多个 PDM 文件。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const LText('创建第一个项目'),
            ),
          ],
        ),
      ),
    );
  }
}
