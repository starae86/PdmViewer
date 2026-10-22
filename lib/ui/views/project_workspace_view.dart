import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../app/l10n/app_strings.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../../app/state/app_controller.dart';
import '../../app/theme/app_theme.dart';
import '../../domain/models/pdm_models.dart';
import '../../domain/models/search_models.dart';
import 'project_workspace_copy.dart';
import 'project_workspace_ddl.dart';
import '../widgets/search_text_field.dart';
import '../widgets/user_guide.dart';

class ProjectWorkspaceView extends StatefulWidget {
  const ProjectWorkspaceView({super.key, required this.controller});

  final AppController controller;

  @override
  State<ProjectWorkspaceView> createState() => _ProjectWorkspaceViewState();
}

class _ProjectWorkspaceViewState extends State<ProjectWorkspaceView> {
  static const String _homeTabId = '__home__';
  late String _activeWorkspaceTabId;
  String? _lastObservedDetailTabId;
  int _lastObservedTableActivationVersion = 0;
  int _lastUserGuideSession = 0;

  @override
  void initState() {
    super.initState();
    _activeWorkspaceTabId = widget.controller.activeTableTabId ?? _homeTabId;
    _lastObservedDetailTabId = widget.controller.activeTableTabId;
    _lastObservedTableActivationVersion =
        widget.controller.tableActivationVersion;
  }

  @override
  void didUpdateWidget(covariant ProjectWorkspaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncWorkspaceTabSelection();
  }

  void _syncWorkspaceTabSelection() {
    final currentDetailTabId = widget.controller.activeTableTabId;
    final currentActivationVersion = widget.controller.tableActivationVersion;
    final openTabIds = widget.controller.openTableTabs
        .map((tab) => tab.id)
        .toSet();

    if (currentDetailTabId != null &&
        currentDetailTabId != _lastObservedDetailTabId) {
      _activeWorkspaceTabId = currentDetailTabId;
    } else if (currentDetailTabId != null &&
        currentActivationVersion != _lastObservedTableActivationVersion) {
      _activeWorkspaceTabId = currentDetailTabId;
    } else if (_activeWorkspaceTabId != _homeTabId &&
        !openTabIds.contains(_activeWorkspaceTabId)) {
      _activeWorkspaceTabId = currentDetailTabId ?? _homeTabId;
    }

    _lastObservedDetailTabId = currentDetailTabId;
    _lastObservedTableActivationVersion = currentActivationVersion;
  }

  void _selectWorkspaceTab(String tabId) {
    if (tabId == _homeTabId) {
      setState(() {
        _activeWorkspaceTabId = _homeTabId;
      });
      return;
    }

    unawaited(widget.controller.selectTableTab(tabId));
    setState(() {
      _activeWorkspaceTabId = tabId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final guide = UserGuideScope.maybeOf(context);
    if (guide?.active == true && guide!.session != _lastUserGuideSession) {
      _lastUserGuideSession = guide.session;
      _activeWorkspaceTabId = _homeTabId;
      _lastObservedDetailTabId = controller.activeTableTabId;
      _lastObservedTableActivationVersion = controller.tableActivationVersion;
    }
    if (controller.selectedProject == null) {
      return const _WorkspaceEmptyState();
    }

    _syncWorkspaceTabSelection();

    return Stack(
      children: [
        Column(
          children: [
            _WorkspaceTabsBar(
              activeTabId: _activeWorkspaceTabId,
              detailTabs: controller.openTableTabs,
              onSelect: _selectWorkspaceTab,
              onClose: controller.closeTableTab,
              onCloseOthers: controller.closeOtherTableTabs,
              onCloseLeft: controller.closeLeftTableTabs,
              onCloseRight: controller.closeRightTableTabs,
              onCloseAll: controller.closeAllTableTabs,
            ),
            Expanded(
              child: _activeWorkspaceTabId == _homeTabId
                  ? _TableListPanel(controller: controller)
                  : _TableFieldsPanel(
                      key: ValueKey(controller.activeTableTabId),
                      controller: controller,
                    ),
            ),
          ],
        ),
        if (controller.isBusy)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.14),
              ),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                        const SizedBox(width: 10),
                        LText(controller.busyLabel ?? '正在处理，请稍候...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TableListPanel extends StatefulWidget {
  const _TableListPanel({required this.controller});

  final AppController controller;

  @override
  State<_TableListPanel> createState() => _TableListPanelState();
}

class _TableListPanelState extends State<_TableListPanel> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'table-list-copy');
  final ScrollController _scrollController = ScrollController();
  String? _lastTopResultId;
  int _lastResultCount = 0;
  Set<String> _selectedResultIds = <String>{};
  String? _selectionAnchorResultId;
  FieldTableSelection? _homeSelection;
  bool _isHomeDragging = false;

  @override
  void didUpdateWidget(covariant _TableListPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncScrollToTopIfNeeded();
    _syncSelectedRows();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _syncScrollToTopIfNeeded() {
    final results = widget.controller.results;
    final topResultId = results.isEmpty ? null : results.first.id;
    final shouldScrollToTop =
        results.isNotEmpty &&
        (topResultId != _lastTopResultId || results.length != _lastResultCount);

    _lastTopResultId = topResultId;
    _lastResultCount = results.length;

    if (!shouldScrollToTop) {
      return;
    }
    _homeSelection = null;
    _isHomeDragging = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(0);
    });
  }

  Future<void> _handleCopy() async {
    final results = widget.controller.results;
    final selection = _homeSelection;
    if (selection != null &&
        selection.startRow >= 0 &&
        selection.endRow < results.length) {
      final text = buildTableResultsSelectionCopyText(
        items: results,
        selection: selection,
        projectLabelFor: (item) =>
            widget.controller.searchTarget == SearchTarget.allProjects
            ? item.projectName
            : (widget.controller.selectedProject?.name ?? ''),
      );
      if (text.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: text));
      }
      return;
    }
    final selectedItems = results
        .where((item) => _selectedResultIds.contains(item.id))
        .toList(growable: false);
    if (selectedItems.isNotEmpty) {
      final includeProject =
          widget.controller.searchTarget == SearchTarget.allProjects;
      final text = selectedItems
          .map(
            (item) => buildTableResultCopyText(
              item: item,
              projectLabel: includeProject
                  ? item.projectName
                  : (widget.controller.selectedProject?.name ?? ''),
              includeProject: includeProject,
            ),
          )
          .join('\n');
      await Clipboard.setData(ClipboardData(text: text));
      return;
    }

    final item = widget.controller.selectedResult;
    if (item == null) {
      return;
    }

    final includeProject =
        widget.controller.searchTarget == SearchTarget.allProjects;
    final projectLabel = includeProject
        ? item.projectName
        : (widget.controller.selectedProject?.name ?? '');
    final text = buildTableResultCopyText(
      item: item,
      projectLabel: projectLabel,
      includeProject: includeProject,
    );
    await Clipboard.setData(ClipboardData(text: text));
  }

  void _selectAllResults() {
    final results = widget.controller.results;
    if (results.isEmpty) {
      return;
    }
    setState(() {
      _selectedResultIds = results.map((item) => item.id).toSet();
      _selectionAnchorResultId = results.first.id;
      _homeSelection = FieldTableSelection(
        anchor: const FieldTableCellPosition(rowIndex: 0, columnIndex: 0),
        focus: FieldTableCellPosition(
          rowIndex: results.length - 1,
          columnIndex: 3,
        ),
      );
    });
  }

  void _syncSelectedRows() {
    final validIds = widget.controller.results.map((item) => item.id).toSet();
    final selectionIsValid =
        _homeSelection == null ||
        _homeSelection!.endRow < widget.controller.results.length;
    if (_selectedResultIds.every(validIds.contains) &&
        (_selectionAnchorResultId == null ||
            validIds.contains(_selectionAnchorResultId)) &&
        selectionIsValid) {
      return;
    }
    setState(() {
      _selectedResultIds = _selectedResultIds.intersection(validIds);
      if (_selectionAnchorResultId != null &&
          !validIds.contains(_selectionAnchorResultId)) {
        _selectionAnchorResultId = null;
      }
      if (!selectionIsValid) {
        _homeSelection = null;
        _isHomeDragging = false;
      }
    });
  }

  bool _isAdditiveSelectionPressed() {
    return defaultTargetPlatform == TargetPlatform.macOS
        ? HardwareKeyboard.instance.isMetaPressed
        : HardwareKeyboard.instance.isControlPressed;
  }

  bool _isRangeSelectionPressed() => HardwareKeyboard.instance.isShiftPressed;

  void _selectSingleResult(SearchResultItem item) {
    setState(() {
      _selectedResultIds = {item.id};
      _selectionAnchorResultId = item.id;
    });
  }

  void _toggleSelectedResult(SearchResultItem item) {
    final next = Set<String>.from(_selectedResultIds);
    if (next.contains(item.id)) {
      next.remove(item.id);
    } else {
      next.add(item.id);
    }
    setState(() {
      _selectedResultIds = next;
      _selectionAnchorResultId = item.id;
    });
  }

  void _selectResultRange(SearchResultItem item) {
    final anchorId = _selectionAnchorResultId;
    final results = widget.controller.results;
    if (anchorId == null) {
      _selectSingleResult(item);
      return;
    }
    final anchorIndex = results.indexWhere((result) => result.id == anchorId);
    final currentIndex = results.indexWhere((result) => result.id == item.id);
    if (anchorIndex < 0 || currentIndex < 0) {
      _selectSingleResult(item);
      return;
    }
    final start = anchorIndex < currentIndex ? anchorIndex : currentIndex;
    final end = anchorIndex > currentIndex ? anchorIndex : currentIndex;
    setState(() {
      _selectedResultIds = results
          .sublist(start, end + 1)
          .map((result) => result.id)
          .toSet();
    });
  }

  void _handleRowTap(SearchResultItem item) {
    if (_isRangeSelectionPressed()) {
      _selectResultRange(item);
      return;
    }
    if (_isAdditiveSelectionPressed()) {
      _toggleSelectedResult(item);
      return;
    }
    _selectSingleResult(item);
  }

  void _handleHomeCellTap(
    SearchResultItem item,
    int rowIndex,
    int columnIndex,
  ) {
    _handleRowTap(item);
    setState(() {
      final position = FieldTableCellPosition(
        rowIndex: rowIndex,
        columnIndex: columnIndex,
      );
      _homeSelection = FieldTableSelection(anchor: position, focus: position);
    });
  }

  void _startHomeCellDrag(
    SearchResultItem item,
    int rowIndex,
    int columnIndex,
  ) {
    _focusNode.requestFocus();
    final position = FieldTableCellPosition(
      rowIndex: rowIndex,
      columnIndex: columnIndex,
    );
    setState(() {
      _selectedResultIds = {item.id};
      _selectionAnchorResultId = item.id;
      _homeSelection = FieldTableSelection(anchor: position, focus: position);
      _isHomeDragging = true;
    });
  }

  void _updateHomeCellDrag(FieldTableCellPosition position) {
    final selection = _homeSelection;
    if (!_isHomeDragging || selection == null) {
      return;
    }
    setState(() {
      _homeSelection = selection.copyWith(focus: position);
    });
  }

  void _endHomeCellDrag() {
    if (!_isHomeDragging) {
      return;
    }
    setState(() {
      _isHomeDragging = false;
    });
  }

  List<SearchResultItem> _resolvedPreviewTargets(SearchResultItem item) {
    final results = widget.controller.results;
    if (_selectedResultIds.contains(item.id)) {
      return results
          .where((result) => _selectedResultIds.contains(result.id))
          .toList(growable: false);
    }
    _selectSingleResult(item);
    return [item];
  }

  Future<void> _showRowContextMenu(
    BuildContext rowContext,
    SearchResultItem item,
    int rowIndex,
    int columnIndex,
    Offset globalPosition,
  ) async {
    _focusNode.requestFocus();
    if (!_selectedResultIds.contains(item.id)) {
      _selectSingleResult(item);
    }
    final position = FieldTableCellPosition(
      rowIndex: rowIndex,
      columnIndex: columnIndex,
    );
    if (!(_homeSelection?.contains(position) ?? false)) {
      setState(() {
        _homeSelection = FieldTableSelection(anchor: position, focus: position);
      });
    }
    final isTableNameCell = columnIndex == 0;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: rowContext,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'copy',
          height: 36,
          child: LText('复制'),
        ),
        if (isTableNameCell)
          const PopupMenuItem<String>(
            value: 'copyCamelCase',
            height: 36,
            child: LText('驼峰复制'),
          ),
        const PopupMenuItem<String>(
          value: 'previewSql',
          height: 36,
          child: LText('预览 SQL'),
        ),
      ],
    );
    if (!mounted || action == null) {
      return;
    }
    if (action == 'copy') {
      await _handleCopy();
      return;
    }
    if (action == 'copyCamelCase') {
      final tableName = (item.tableCode?.trim().isNotEmpty == true
          ? item.tableCode!
          : item.title);
      await Clipboard.setData(ClipboardData(text: toLowerCamelCase(tableName)));
      return;
    }
    if (action != 'previewSql') {
      return;
    }
    final targets = _resolvedPreviewTargets(item);
    await showSqlPreviewDialog(
      context: context,
      targets: targets,
      loadDetail: widget.controller.loadTableDetailForResult,
      loadDetails: widget.controller.loadTableDetailsForResults,
      suggestedFileName: buildPreviewSuggestedFileNameForResults(targets),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final results = controller.results;
    final isProjectBrowse =
        controller.selectedPdmFileId == null &&
        controller.activeQuery.trim().isEmpty &&
        controller.searchTarget == SearchTarget.currentProject;
    final displayCount = isProjectBrowse
        ? controller.stats.tableCount
        : results.length;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyC, control: true):
            _handleCopy,
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): _handleCopy,
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            _selectAllResults,
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
            _selectAllResults,
      },
      child: Focus(
        focusNode: _focusNode,
        child: _WorkspaceContentSurface(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SearchToolbar(
                  controller: controller,
                  resultCount: results.length,
                  displayCount: displayCount,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Listener(
                    onPointerDown: (_) => _focusNode.requestFocus(),
                    child: _WindowsSemanticsWorkaround(
                      child: results.isEmpty
                          ? const _EmptyBody(
                              icon: Icons.table_rows_outlined,
                              title: '没有可显示的表',
                              description: '调整项目范围、树节点或搜索关键字后再试。',
                            )
                          : RepaintBoundary(
                              child: Scrollbar(
                                controller: _scrollController,
                                thumbVisibility: true,
                                interactive: true,
                                child: _TableResultsList(
                                  controller: controller,
                                  results: results,
                                  scrollController: _scrollController,
                                  onFocusRequested: () =>
                                      _focusNode.requestFocus(),
                                  selectedResultIds: _selectedResultIds,
                                  selection: _homeSelection,
                                  onCellTap: _handleHomeCellTap,
                                  onCellDragStart: _startHomeCellDrag,
                                  onCellDragEnter: _updateHomeCellDrag,
                                  onCellDragEnd: _endHomeCellDrag,
                                  onLinkTap: controller.selectResult,
                                  onRowSecondaryTapDown: _showRowContextMenu,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchToolbar extends StatefulWidget {
  const _SearchToolbar({
    required this.controller,
    required this.resultCount,
    required this.displayCount,
  });

  final AppController controller;
  final int resultCount;
  final int displayCount;

  @override
  State<_SearchToolbar> createState() => _SearchToolbarState();
}

class _SearchToolbarState extends State<_SearchToolbar> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.controller.draftQuery);
  }

  @override
  void didUpdateWidget(covariant _SearchToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final draftQuery = widget.controller.draftQuery;
    if (_textController.text != draftQuery) {
      _textController.value = TextEditingValue(
        text: draftQuery,
        selection: TextSelection.collapsed(offset: draftQuery.length),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    final toolbarTextStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w500,
      color: theme.colorScheme.onSurface,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          UserGuideAnchor(
            target: UserGuideTarget.search,
            child: SizedBox(
              width: 320,
              child: SearchTextField(
                controller: _textController,
                onChanged: controller.scheduleQueryUpdate,
                onSubmitted: (_) => controller.flushQueryNow(),
                style: toolbarTextStyle,
                decoration: InputDecoration(
                  prefixIcon: SearchActivityIndicator(
                    searching: controller.isSearching,
                  ),
                  filled: true,
                  fillColor: AppTheme.componentsOf(context).isMaterial
                      ? theme.colorScheme.surfaceContainerHigh
                      : theme.colorScheme.surfaceContainerLowest,
                  border: OutlineInputBorder(
                    borderRadius: AppTheme.searchRadiusOf(context),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppTheme.searchRadiusOf(context),
                    borderSide: AppTheme.componentsOf(context).isMaterial
                        ? BorderSide.none
                        : BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: AppTheme.searchRadiusOf(context),
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary.withValues(
                        alpha: AppTheme.componentsOf(context).isMacos ? 0.5 : 1,
                      ),
                      width: AppTheme.componentsOf(context).focusWidth,
                    ),
                  ),
                  hintText: context.tr(
                    controller.selectedPdmFileId == null
                        ? '搜索表编码、表注释或字段编码'
                        : '仅在当前选中的 PDM 文件内搜索',
                  ),
                  hintStyle: toolbarTextStyle?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w400,
                  ),
                  isDense: true,
                  contentPadding: AppTheme.componentsOf(context).inputPadding,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<SearchTarget>(
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              textStyle: WidgetStatePropertyAll(toolbarTextStyle),
            ),
            segments: [
              ButtonSegment(
                value: SearchTarget.currentProject,
                label: Tooltip(
                  message: context.tr(
                    '仅在左侧当前选中范围内搜索。选中项目时搜索该项目全部 PDM，选中 PDM 时仅搜索当前 PDM。',
                  ),
                  child: LText('当前范围', style: toolbarTextStyle),
                ),
              ),
              ButtonSegment(
                value: SearchTarget.allProjects,
                label: Tooltip(
                  message: context.tr('忽略左侧当前选择，直接在全部项目的全部 PDM 中搜索。'),
                  child: LText('全部项目', style: toolbarTextStyle),
                ),
              ),
            ],
            selected: {controller.searchTarget},
            onSelectionChanged: (selection) {
              controller.setSearchTarget(selection.first);
            },
          ),
          const SizedBox(width: 8),
          SegmentedButton<SearchScope>(
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              textStyle: WidgetStatePropertyAll(toolbarTextStyle),
            ),
            segments: [
              ButtonSegment(
                value: SearchScope.all,
                label: LText('全部', style: toolbarTextStyle),
              ),
              ButtonSegment(
                value: SearchScope.table,
                label: LText('表', style: toolbarTextStyle),
              ),
              ButtonSegment(
                value: SearchScope.column,
                label: LText('字段', style: toolbarTextStyle),
              ),
            ],
            selected: {controller.scope},
            onSelectionChanged: (selection) {
              controller.setScope(selection.first);
            },
          ),
          const SizedBox(width: 8),
          _Pill(text: '表数量 ${widget.displayCount}'),
        ],
      ),
    );
  }
}

class _TableResultsList extends StatelessWidget {
  const _TableResultsList({
    required this.controller,
    required this.results,
    required this.scrollController,
    required this.onFocusRequested,
    required this.selectedResultIds,
    required this.selection,
    required this.onCellTap,
    required this.onCellDragStart,
    required this.onCellDragEnter,
    required this.onCellDragEnd,
    required this.onLinkTap,
    required this.onRowSecondaryTapDown,
  });

  final AppController controller;
  final List<SearchResultItem> results;
  final ScrollController scrollController;
  final VoidCallback onFocusRequested;
  final Set<String> selectedResultIds;
  final FieldTableSelection? selection;
  final void Function(SearchResultItem item, int rowIndex, int columnIndex)
  onCellTap;
  final void Function(SearchResultItem item, int rowIndex, int columnIndex)
  onCellDragStart;
  final ValueChanged<FieldTableCellPosition> onCellDragEnter;
  final VoidCallback onCellDragEnd;
  final ValueChanged<SearchResultItem> onLinkTap;
  final void Function(BuildContext, SearchResultItem, int, int, Offset)
  onRowSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      itemExtent: 42,
      itemCount: results.length,
      itemBuilder: (context, index) {
        final item = results[index];
        final selected = selectedResultIds.contains(item.id);
        return _TableListTile(
          item: item,
          rowIndex: index,
          selected: selected,
          projectLabel: controller.searchTarget == SearchTarget.allProjects
              ? item.projectName
              : (controller.selectedProject?.name ?? '-'),
          selection: selection,
          onCellTap: (columnIndex) {
            onFocusRequested();
            onCellTap(item, index, columnIndex);
          },
          onCellDragStart: (columnIndex) {
            onFocusRequested();
            onCellDragStart(item, index, columnIndex);
          },
          onCellDragEnter: (columnIndex) => onCellDragEnter(
            FieldTableCellPosition(rowIndex: index, columnIndex: columnIndex),
          ),
          onCellDragEnd: onCellDragEnd,
          onLinkTap: () => onLinkTap(item),
          onSecondaryTapDown: (columnIndex, globalPosition) =>
              onRowSecondaryTapDown(
                context,
                item,
                index,
                columnIndex,
                globalPosition,
              ),
        );
      },
    );
  }
}

Future<void> showSqlPreviewDialog({
  required BuildContext context,
  required List<SearchResultItem> targets,
  required Future<TableDetail?> Function(SearchResultItem result) loadDetail,
  required Future<Map<String, TableDetail>> Function(
    List<SearchResultItem> results,
  )
  loadDetails,
  String? suggestedFileName,
}) {
  if (targets.isEmpty) {
    return Future.value();
  }
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _TableDdlPreviewDialog(
      targets: targets,
      loadDetail: loadDetail,
      loadDetails: loadDetails,
      suggestedFileName: suggestedFileName,
    ),
  );
}

class _TableListTile extends StatelessWidget {
  const _TableListTile({
    required this.item,
    required this.rowIndex,
    required this.selected,
    required this.projectLabel,
    required this.selection,
    required this.onCellTap,
    required this.onCellDragStart,
    required this.onCellDragEnter,
    required this.onCellDragEnd,
    required this.onLinkTap,
    required this.onSecondaryTapDown,
  });

  final SearchResultItem item;
  final int rowIndex;
  final bool selected;
  final String projectLabel;
  final FieldTableSelection? selection;
  final ValueChanged<int> onCellTap;
  final ValueChanged<int> onCellDragStart;
  final ValueChanged<int> onCellDragEnter;
  final VoidCallback onCellDragEnd;
  final VoidCallback onLinkTap;
  final void Function(int columnIndex, Offset globalPosition)
  onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primaryOf(context);
    final zebraColor = AppTheme.tableRowFill(context, isEven: rowIndex.isEven);
    final dividerColor = AppTheme.outlineSoft(context).withValues(alpha: 0.95);
    final fullRowSelected =
        selection != null &&
        rowIndex >= selection!.startRow &&
        rowIndex <= selection!.endRow &&
        selection!.startColumn == 0 &&
        selection!.endColumn == 3;
    return Material(
      color: zebraColor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fullRowSelected ? AppTheme.selectionFill(context) : null,
          border: Border(
            left: BorderSide(
              color: selected ? accent : Colors.transparent,
              width: 3,
            ),
            bottom: BorderSide(color: dividerColor),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.zero,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCell(
                context,
                columnIndex: 0,
                flex: 3,
                fullRowSelected: fullRowSelected,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    behavior: HitTestBehavior.deferToChild,
                    onTap: () {
                      onCellTap(0);
                      onLinkTap();
                    },
                    child: Text(
                      item.tableCode?.isNotEmpty == true
                          ? item.tableCode!
                          : item.title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: accent,
                        decoration: TextDecoration.underline,
                        decorationColor: accent,
                      ),
                    ),
                  ),
                ),
              ),
              _buildCell(
                context,
                columnIndex: 1,
                flex: 4,
                fullRowSelected: fullRowSelected,
                child: Text(
                  item.displayTableLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              _buildCell(
                context,
                columnIndex: 2,
                flex: 2,
                fullRowSelected: fullRowSelected,
                child: Text(
                  item.sourcePdm,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              _buildCell(
                context,
                columnIndex: 3,
                flex: 2,
                fullRowSelected: fullRowSelected,
                child: Text(
                  projectLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCell(
    BuildContext context, {
    required int columnIndex,
    required int flex,
    required bool fullRowSelected,
    required Widget child,
  }) {
    final position = FieldTableCellPosition(
      rowIndex: rowIndex,
      columnIndex: columnIndex,
    );
    final cellSelected = selection?.contains(position) ?? false;
    return Expanded(
      flex: flex,
      child: MouseRegion(
        onEnter: (_) => onCellDragEnter(columnIndex),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onCellTap(columnIndex),
          onPanStart: (_) => onCellDragStart(columnIndex),
          onPanEnd: (_) => onCellDragEnd(),
          onPanCancel: onCellDragEnd,
          onSecondaryTapDown: (details) =>
              onSecondaryTapDown(columnIndex, details.globalPosition),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cellSelected && !fullRowSelected
                  ? AppTheme.selectionFill(context)
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(alignment: Alignment.centerLeft, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _TableDdlPreviewItem {
  const _TableDdlPreviewItem({required this.result, required this.detail});

  final SearchResultItem result;
  final TableDetail detail;
}

class _TableDdlPreviewDialog extends StatefulWidget {
  const _TableDdlPreviewDialog({
    required this.targets,
    required this.loadDetail,
    required this.loadDetails,
    this.suggestedFileName,
  });

  final List<SearchResultItem> targets;
  final Future<TableDetail?> Function(SearchResultItem result) loadDetail;
  final Future<Map<String, TableDetail>> Function(
    List<SearchResultItem> results,
  )
  loadDetails;
  final String? suggestedFileName;

  @override
  State<_TableDdlPreviewDialog> createState() => _TableDdlPreviewDialogState();
}

class _TableDdlPreviewDialogState extends State<_TableDdlPreviewDialog> {
  static const double _previewLineExtent = 22;
  static const Duration _searchDebounceDuration = Duration(milliseconds: 240);
  static const Duration _minimumLoadingDuration = Duration(milliseconds: 320);
  static const int _visiblePreviewLimit = 200;

  DdlDialect _dialect = DdlDialect.oracle;
  bool _includeDdl = true;
  bool _includeComments = true;
  final FocusNode _focusNode = FocusNode(debugLabel: 'preview-sql-focus');
  final FocusNode _searchFocusNode = FocusNode(
    debugLabel: 'preview-sql-search',
  );
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _selectedText = '';
  bool _isLoading = true;
  bool _isMaterializingFullSql = false;
  bool _searchBarExpanded = false;
  bool _searchCaseSensitive = false;
  bool _searchWholeMatch = false;
  String _loadingLabel = '正在准备表结构...';
  int _loadedItemCount = 0;
  List<_TextSearchMatch> _searchMatches = const [];
  int _activeSearchMatchIndex = -1;
  String _previewText = '';
  List<_TableDdlPreviewItem> _items = const [];
  Timer? _searchDebounceTimer;

  bool get _isLargePreview => widget.targets.length > _visiblePreviewLimit;

  List<_TableDdlPreviewItem> get _visiblePreviewItems {
    return _items;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_loadPreviewItems());
    });
  }

  String _composeItemPreviewText(_TableDdlPreviewItem item) {
    final code = (item.result.tableCode ?? '').trim().isNotEmpty
        ? item.result.tableCode!.trim()
        : item.result.title.trim();
    final comment = item.result.displayTableLabel.trim();
    final headerParts = <String>[
      code,
      if (comment.isNotEmpty && comment != code) comment,
      item.result.sourcePdm,
      item.result.projectName,
    ];
    final header = '-- ${headerParts.join(' | ')}';
    if (!_includeDdl) {
      if (!_includeComments) {
        return header;
      }
      final comments = buildTableCommentSql(item.detail, _dialect);
      return comments.trim().isEmpty ? header : '$header\n$comments';
    }
    final ddl = buildTableDdl(
      item.detail,
      _dialect,
      includeComments: _includeComments,
    );
    return '$header\n$ddl';
  }

  Future<String> _composePreviewTextAsync({
    List<_TableDdlPreviewItem>? items,
    String progressPrefix = '正在生成 SQL 文本',
  }) async {
    final sourceItems = items ?? _visiblePreviewItems;
    final buffer = StringBuffer();
    const chunkSize = 120;
    for (var index = 0; index < sourceItems.length; index++) {
      if (index > 0) {
        buffer.write('\n\n');
      }
      buffer.write(_composeItemPreviewText(sourceItems[index]));
      if (index > 0 && index % chunkSize == 0) {
        if (!mounted) {
          return buffer.toString();
        }
        setState(() {
          _loadingLabel =
              '$progressPrefix... ${index + 1}/${sourceItems.length}';
        });
        await Future<void>.delayed(Duration.zero);
      }
    }
    return buffer.toString();
  }

  Future<void> _loadPreviewItems() async {
    final startedAt = DateTime.now();
    setState(() {
      _isLoading = true;
      _loadingLabel = '正在加载表结构...';
      _loadedItemCount = 0;
    });
    // Let the dialog paint before starting synchronous SQLite work.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }
    final previewTargets = widget.targets
        .take(_visiblePreviewLimit)
        .toList(growable: false);
    final detailMap = await widget.loadDetails(previewTargets);
    if (!mounted) {
      return;
    }

    final previewItems = <_TableDdlPreviewItem>[];
    for (var index = 0; index < previewTargets.length; index++) {
      final result = previewTargets[index];
      final detail = detailMap[_buildPreviewItemKey(result)];
      if (detail != null) {
        previewItems.add(_TableDdlPreviewItem(result: result, detail: detail));
      }
    }

    setState(() {
      _items = previewItems;
      _loadedItemCount = previewItems.length;
      _loadingLabel = '正在生成 SQL 文本...';
    });
    final previewText = await _composePreviewTextAsync();
    if (!mounted) {
      return;
    }

    final elapsed = DateTime.now().difference(startedAt);
    final waitDuration = _minimumLoadingDuration - elapsed;
    if (waitDuration > Duration.zero) {
      await Future<void>.delayed(waitDuration);
      if (!mounted) {
        return;
      }
    }

    setState(() {
      _previewText = previewText;
      _isLoading = false;
      _selectedText = '';
    });
    if (_searchController.text.trim().isNotEmpty) {
      _rebuildSearchMatches();
    }
  }

  Future<void> _savePreviewToFile() async {
    if (_isLoading || _isMaterializingFullSql || _items.isEmpty) {
      return;
    }
    final filePath = await FilePicker.platform.saveFile(
      dialogTitle: context.tr('保存 SQL 预览'),
      fileName: widget.suggestedFileName ?? 'pdm_preview.sql',
      type: FileType.custom,
      allowedExtensions: const ['sql'],
    );
    if (filePath == null || filePath.trim().isEmpty) {
      return;
    }
    final normalizedPath = filePath.toLowerCase().endsWith('.sql')
        ? filePath
        : '$filePath.sql';
    final fullText = await _materializeFullPreviewText();
    if (fullText.trim().isEmpty) {
      return;
    }
    await File(normalizedPath).writeAsString(fullText);
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _focusNode.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _refreshPreviewContent() {
    if (_items.isEmpty) {
      _previewText = '';
      return;
    }
    unawaited(_refreshPreviewContentAsync());
  }

  Future<void> _refreshPreviewContentAsync() async {
    setState(() {
      _isLoading = true;
      _loadingLabel = '正在重新生成 SQL 文本...';
    });
    final previewText = await _composePreviewTextAsync();
    if (!mounted) {
      return;
    }
    setState(() {
      _previewText = previewText;
      _isLoading = false;
      _selectedText = '';
    });
  }

  void _openSearchBar() {
    if (_searchBarExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _searchFocusNode.requestFocus();
        _searchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _searchController.text.length,
        );
      });
      return;
    }
    setState(() {
      _searchBarExpanded = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _searchFocusNode.requestFocus();
      _searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _searchController.text.length,
      );
    });
  }

  void _closeSearchBar() {
    if (!_searchBarExpanded) {
      return;
    }
    _searchDebounceTimer?.cancel();
    setState(() {
      _searchBarExpanded = false;
      _searchMatches = const [];
      _activeSearchMatchIndex = -1;
      _searchController.clear();
    });
  }

  void _toggleSearchBar() {
    if (_searchBarExpanded) {
      _closeSearchBar();
    } else {
      _openSearchBar();
    }
  }

  void _scheduleSearchRebuild() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(_searchDebounceDuration, () {
      if (!mounted) {
        return;
      }
      _rebuildSearchMatches();
    });
  }

  void _rebuildSearchMatches() {
    if (_isLoading) {
      return;
    }
    final rawQuery = _searchController.text.trim();
    if (rawQuery.isEmpty) {
      setState(() {
        _searchMatches = const [];
        _activeSearchMatchIndex = -1;
      });
      return;
    }
    final matches = _findTextSearchMatches(
      text: _previewText,
      query: rawQuery,
      caseSensitive: _searchCaseSensitive,
      wholeMatch: _searchWholeMatch,
    );
    final nextActiveIndex = matches.isEmpty
        ? -1
        : _findNearestPreviewMatchIndex(matches);
    setState(() {
      _searchMatches = matches;
      _activeSearchMatchIndex = nextActiveIndex;
    });
    _ensureActiveSearchMatchVisible();
  }

  int _findNearestPreviewMatchIndex(List<_TextSearchMatch> matches) {
    if (matches.isEmpty || !_scrollController.hasClients) {
      return 0;
    }
    final lineCount = '\n'.allMatches(_previewText).length + 1;
    final currentLine = (_scrollController.offset / _previewLineExtent)
        .round()
        .clamp(0, lineCount <= 0 ? 0 : lineCount - 1);
    var bestIndex = 0;
    var bestDistance = (matches.first.lineIndex - currentLine).abs();
    for (var index = 1; index < matches.length; index++) {
      final distance = (matches[index].lineIndex - currentLine).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = index;
      }
    }
    return bestIndex;
  }

  void _jumpSearchMatch(int delta) {
    if (_searchMatches.isEmpty) {
      return;
    }
    setState(() {
      final nextIndex =
          (_activeSearchMatchIndex + delta) % _searchMatches.length;
      _activeSearchMatchIndex = nextIndex < 0
          ? _searchMatches.length - 1
          : nextIndex;
    });
    _ensureActiveSearchMatchVisible(requestFocus: true);
  }

  void _ensureActiveSearchMatchVisible({bool requestFocus = false}) {
    if (_activeSearchMatchIndex < 0 ||
        _activeSearchMatchIndex >= _searchMatches.length) {
      return;
    }
    final match = _searchMatches[_activeSearchMatchIndex];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final targetOffset = (match.lineIndex * _previewLineExtent).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _copyPreviewText() async {
    if (_isLoading || _isMaterializingFullSql || _items.isEmpty) {
      return;
    }
    final previewText = await _materializeFullPreviewText();
    if (previewText.trim().isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: previewText));
  }

  void _selectAllPreviewText() {
    if (_previewText.trim().isEmpty) {
      return;
    }
    setState(() {
      _selectedText = _previewText;
    });
  }

  Future<String> _materializeFullPreviewText() async {
    if (!_isLargePreview) {
      return _previewText;
    }
    if (_isMaterializingFullSql) {
      return '';
    }
    setState(() {
      _isMaterializingFullSql = true;
      _loadingLabel = '正在读取完整表结构...';
    });
    final buffer = StringBuffer();
    var writtenItemCount = 0;
    const batchSize = 200;
    for (var start = 0; start < widget.targets.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, widget.targets.length);
      final targets = widget.targets.sublist(start, end);
      final detailMap = await widget.loadDetails(targets);
      if (!mounted) {
        return '';
      }
      for (final result in targets) {
        final detail = detailMap[_buildPreviewItemKey(result)];
        if (detail == null) {
          continue;
        }
        if (writtenItemCount > 0) {
          buffer.write('\n\n');
        }
        buffer.write(
          _composeItemPreviewText(
            _TableDdlPreviewItem(result: result, detail: detail),
          ),
        );
        writtenItemCount++;
      }
      setState(() {
        _loadingLabel = '正在生成完整 SQL... $end/${widget.targets.length}';
      });
      await Future<void>.delayed(Duration.zero);
      if (!mounted) {
        return '';
      }
    }
    final text = buffer.toString();
    if (mounted) {
      setState(() {
        _isMaterializingFullSql = false;
        _loadingLabel = '正在生成 SQL 文本...';
      });
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 96, vertical: 24),
      backgroundColor: AppTheme.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          AppTheme.componentsOf(context).dialogRadius,
        ),
        side: BorderSide(color: AppTheme.outlineSoft(context)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 760,
          maxWidth: 980,
          minHeight: 520,
          maxHeight: 760,
        ),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                _toggleSearchBar,
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                _toggleSearchBar,
            const SingleActivator(LogicalKeyboardKey.keyC, control: true):
                _copyPreviewText,
            const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
                _copyPreviewText,
            const SingleActivator(LogicalKeyboardKey.keyA, control: true):
                _selectAllPreviewText,
            const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
                _selectAllPreviewText,
          },
          child: Focus(
            autofocus: true,
            focusNode: _focusNode,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        LText(
                          '预览 SQL',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(width: 12),
                        LText(
                          _isLoading
                              ? '正在生成...'
                              : _isMaterializingFullSql
                              ? '正在生成完整 SQL...'
                              : '共 ${widget.targets.length} 张表',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SegmentedButton<DdlDialect>(
                        segments: const [
                          ButtonSegment<DdlDialect>(
                            value: DdlDialect.oracle,
                            label: Text('Oracle'),
                          ),
                          ButtonSegment<DdlDialect>(
                            value: DdlDialect.mysql,
                            label: Text('MySQL'),
                          ),
                          ButtonSegment<DdlDialect>(
                            value: DdlDialect.postgresql,
                            label: Text('PostgreSQL'),
                          ),
                        ],
                        selected: {_dialect},
                        showSelectedIcon: false,
                        onSelectionChanged: _isLoading
                            ? null
                            : (selection) {
                                setState(() {
                                  _dialect = selection.first;
                                  _selectedText = '';
                                });
                                _refreshPreviewContent();
                                _rebuildSearchMatches();
                              },
                      ),
                      FilterChip(
                        label: const LText('生成 DDL'),
                        selected: _includeDdl,
                        showCheckmark: false,
                        onSelected: _isLoading || _isMaterializingFullSql
                            ? null
                            : (value) {
                                setState(() {
                                  _includeDdl = value;
                                  _selectedText = '';
                                });
                                _refreshPreviewContent();
                                _rebuildSearchMatches();
                              },
                      ),
                      FilterChip(
                        label: const LText('生成注释'),
                        selected: _includeComments,
                        showCheckmark: false,
                        onSelected: _isLoading || _isMaterializingFullSql
                            ? null
                            : (value) {
                                setState(() {
                                  _includeComments = value;
                                  _selectedText = '';
                                });
                                _refreshPreviewContent();
                                _rebuildSearchMatches();
                              },
                      ),
                      if (!_isLoading && _isLargePreview)
                        _Pill(
                          text: '当前仅预览前 $_visiblePreviewLimit 张，复制/保存仍包含全部表',
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceOf(context),
                        border: Border.all(
                          color: AppTheme.outlineSoft(context),
                        ),
                      ),
                      child: _isLoading
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  LText(
                                    _loadingLabel,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 6),
                                  LText(
                                    '已选择 ${widget.targets.length} 张表，已处理 $_loadedItemCount 张',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            )
                          : Stack(
                              children: [
                                Positioned.fill(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    child: ScrollConfiguration(
                                      behavior: ScrollConfiguration.of(
                                        context,
                                      ).copyWith(scrollbars: false),
                                      child: SelectionArea(
                                        onSelectionChanged: (content) {
                                          final normalized =
                                              content?.plainText ?? '';
                                          if (normalized == _selectedText) {
                                            return;
                                          }
                                          setState(() {
                                            _selectedText = normalized;
                                          });
                                        },
                                        child: Scrollbar(
                                          controller: _scrollController,
                                          thumbVisibility: true,
                                          child: SingleChildScrollView(
                                            controller: _scrollController,
                                            padding: const EdgeInsets.all(12),
                                            child: _HighlightedSqlTextBlock(
                                              text: _previewText,
                                              matches: _searchMatches,
                                              activeMatchIndex:
                                                  _activeSearchMatchIndex,
                                              baseStyle: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(height: 1.35),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 8,
                                  bottom: 8,
                                  child: _DetailSearchOverlay(
                                    expanded: _searchBarExpanded,
                                    controller: _searchController,
                                    focusNode: _searchFocusNode,
                                    hintText: context.tr('搜索预览 SQL'),
                                    caseSensitive: _searchCaseSensitive,
                                    wholeMatch: _searchWholeMatch,
                                    matchCount: _searchMatches.length,
                                    onToggleExpanded: _toggleSearchBar,
                                    onCaseSensitiveChanged: (value) {
                                      _searchDebounceTimer?.cancel();
                                      setState(() {
                                        _searchCaseSensitive = value;
                                      });
                                      _rebuildSearchMatches();
                                    },
                                    onWholeMatchChanged: (value) {
                                      _searchDebounceTimer?.cancel();
                                      setState(() {
                                        _searchWholeMatch = value;
                                      });
                                      _rebuildSearchMatches();
                                    },
                                    onChanged: (_) => _scheduleSearchRebuild(),
                                    onSubmitted: (_) {
                                      _searchDebounceTimer?.cancel();
                                      if (_searchMatches.isEmpty) {
                                        _rebuildSearchMatches();
                                      } else {
                                        _jumpSearchMatch(1);
                                      }
                                    },
                                    onPrevious: () => _jumpSearchMatch(-1),
                                    onNext: () => _jumpSearchMatch(1),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _isLoading || _isMaterializingFullSql
                            ? null
                            : _savePreviewToFile,
                        child: LText(
                          _isMaterializingFullSql ? '生成中...' : '保存到文件',
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const LText('关闭'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _isLoading || _isMaterializingFullSql
                            ? null
                            : _copyPreviewText,
                        child: LText(_isMaterializingFullSql ? '生成中...' : '复制'),
                      ),
                    ],
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

String _buildPreviewItemKey(SearchResultItem result) {
  return '${result.projectId}\u0000${result.pdmFileId}\u0000${result.sourceTableId}';
}

String buildPreviewSuggestedFileNameForResults(List<SearchResultItem> targets) {
  if (targets.isEmpty) {
    return 'pdm_preview.sql';
  }
  final first = targets.first;
  final stem = first.displayTableLabel.trim().isNotEmpty
      ? first.displayTableLabel.trim()
      : first.title.trim();
  return '${_normalizeSqlFileNameStem(stem)}.sql';
}

String buildPreviewSuggestedFileNameForProject(String projectName) {
  return '${_normalizeSqlFileNameStem(projectName)}.sql';
}

String buildPreviewSuggestedFileNameForPdm(String displayName) {
  final normalized = displayName.trim();
  final lower = normalized.toLowerCase();
  final stem = lower.endsWith('.pdm')
      ? normalized.substring(0, normalized.length - 4)
      : normalized;
  return '${_normalizeSqlFileNameStem(stem)}.sql';
}

String _normalizeSqlFileNameStem(String value) {
  final sanitized = value
      .trim()
      .replaceAll(RegExp(r'[<>:"/\\|?*]+'), '_')
      .replaceAll(RegExp(r'\s+'), ' ');
  if (sanitized.isEmpty) {
    return 'pdm_preview';
  }
  return sanitized;
}

class _TableFieldsPanel extends StatefulWidget {
  const _TableFieldsPanel({super.key, required this.controller});

  final AppController controller;

  @override
  State<_TableFieldsPanel> createState() => _TableFieldsPanelState();
}

enum _DetailViewMode { fields, ddl, dml }

class _TableFieldsPanelState extends State<_TableFieldsPanel> {
  Timer? _searchDebounceTimer;
  final FocusNode _focusNode = FocusNode(debugLabel: 'field-table-copy');
  final FocusNode _sqlTextFocusNode = FocusNode(debugLabel: 'detail-sql-text');
  final FocusNode _summaryFocusNode = FocusNode(
    debugLabel: 'detail-summary-copy',
  );
  final FocusNode _searchFocusNode = FocusNode(
    debugLabel: 'field-table-search',
  );
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _sqlTextController = TextEditingController();
  final ScrollController _fieldTableScrollController = ScrollController();
  final ScrollController _sqlTextScrollController = ScrollController();
  FieldTableSelection? _selection;
  bool _isDragging = false;
  FieldTableCellPosition? _lastCellTapPosition;
  DateTime? _lastCellTapAt;
  int _cellTapCount = 0;
  bool _searchBarExpanded = false;
  bool _searchCaseSensitive = false;
  bool _searchWholeMatch = false;
  _DetailViewMode _viewMode = _DetailViewMode.fields;
  DdlDialect _ddlDialect = DdlDialect.oracle;
  String _selectedSummaryText = '';
  String _selectedDdlText = '';
  String _selectedDmlText = '';
  List<FieldTableCellPosition> _fieldSearchMatches = const [];
  int _activeFieldSearchMatchIndex = -1;
  List<GlobalKey> _searchRowKeys = const [];
  List<_TextSearchMatch> _sqlSearchMatches = const [];
  int _activeSqlSearchMatchIndex = -1;

  @override
  void initState() {
    super.initState();
    _sqlTextController.addListener(_syncSelectedSqlText);
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _sqlTextController.removeListener(_syncSelectedSqlText);
    _sqlTextFocusNode.dispose();
    _sqlTextController.dispose();
    _searchController.dispose();
    _fieldTableScrollController.dispose();
    _sqlTextScrollController.dispose();
    _searchFocusNode.dispose();
    _summaryFocusNode.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _searchCellId(FieldTableCellPosition position) =>
      '${position.rowIndex}:${position.columnIndex}';

  void _syncSearchRowKeys(int rowCount) {
    if (_searchRowKeys.length == rowCount) {
      return;
    }
    _searchRowKeys = List<GlobalKey>.generate(
      rowCount,
      (_) => GlobalKey(),
      growable: false,
    );
  }

  String _searchOverlayHintText() {
    return _viewMode == _DetailViewMode.fields ? '搜索当前页单元格' : '搜索当前页 SQL';
  }

  int _currentSearchMatchCount() {
    return _viewMode == _DetailViewMode.fields
        ? _fieldSearchMatches.length
        : _sqlSearchMatches.length;
  }

  String? _currentSqlText(TableDetail? detail) {
    if (detail == null) {
      return null;
    }
    return switch (_viewMode) {
      _DetailViewMode.ddl => buildTableDdl(detail, _ddlDialect),
      _DetailViewMode.dml => buildTableDml(detail, _ddlDialect),
      _DetailViewMode.fields => null,
    };
  }

  void _syncSqlTextController(String sql) {
    if (_sqlTextController.text == sql) {
      return;
    }
    _sqlTextController.value = TextEditingValue(
      text: sql,
      selection: const TextSelection.collapsed(offset: -1),
    );
  }

  void _syncSelectedSqlText() {
    final selection = _sqlTextController.selection;
    final selectedText = selection.isValid && !selection.isCollapsed
        ? selection.textInside(_sqlTextController.text)
        : '';
    if (_viewMode == _DetailViewMode.ddl) {
      if (selectedText == _selectedDdlText && _selectedDmlText.isEmpty) {
        return;
      }
      setState(() {
        _selectedDdlText = selectedText;
        _selectedDmlText = '';
      });
      return;
    }
    if (_viewMode == _DetailViewMode.dml) {
      if (selectedText == _selectedDmlText && _selectedDdlText.isEmpty) {
        return;
      }
      setState(() {
        _selectedDmlText = selectedText;
        _selectedDdlText = '';
      });
    }
  }

  String _tableValueForSearch(
    TableDetail detail,
    int rowIndex,
    int columnIndex,
  ) {
    if (rowIndex == 0) {
      return _ResponsiveFieldTable.headerLabels[columnIndex];
    }
    final column = detail.columns[rowIndex - 1];
    if (columnIndex == 0) {
      return column.isPrimaryKey ? 'PK' : '';
    }
    return _displayFieldCellValue(column, columnIndex);
  }

  void _openSearchBar() {
    if (_searchBarExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchFocusNode.requestFocus();
          _searchController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _searchController.text.length,
          );
        }
      });
      return;
    }

    setState(() {
      _searchBarExpanded = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
        _searchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _searchController.text.length,
        );
      }
    });
  }

  void _closeSearchBar() {
    if (!_searchBarExpanded) {
      return;
    }
    _searchDebounceTimer?.cancel();
    setState(() {
      _searchBarExpanded = false;
      _fieldSearchMatches = const [];
      _activeFieldSearchMatchIndex = -1;
      _sqlSearchMatches = const [];
      _activeSqlSearchMatchIndex = -1;
      _searchController.clear();
    });
  }

  void _toggleSearchBar() {
    if (_searchBarExpanded) {
      _closeSearchBar();
    } else {
      _openSearchBar();
    }
  }

  void _scheduleDetailSearch() {
    _searchDebounceTimer?.cancel();
    if (_searchController.text.trim().isEmpty) {
      _rebuildSearchMatches();
      return;
    }
    _searchDebounceTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted) _rebuildSearchMatches();
    });
  }

  void _rebuildSearchMatches() {
    _searchDebounceTimer?.cancel();
    if (_viewMode != _DetailViewMode.fields) {
      _rebuildSqlSearchMatches();
      return;
    }
    final detail = widget.controller.selectedTableDetail;
    final rawQuery = _searchController.text.trim();
    if (detail == null || rawQuery.isEmpty) {
      setState(() {
        _fieldSearchMatches = const [];
        _activeFieldSearchMatchIndex = -1;
      });
      return;
    }

    final query = _searchCaseSensitive ? rawQuery : rawQuery.toLowerCase();
    final matches = <FieldTableCellPosition>[];
    for (var rowIndex = 0; rowIndex <= detail.columns.length; rowIndex++) {
      for (
        var columnIndex = 0;
        columnIndex < _ResponsiveFieldTable.headerLabels.length;
        columnIndex++
      ) {
        final value = _tableValueForSearch(detail, rowIndex, columnIndex);
        if (value.isEmpty) {
          continue;
        }
        final normalizedValue = value.trim();
        final candidate = _searchCaseSensitive
            ? normalizedValue
            : normalizedValue.toLowerCase();
        final matched = _searchWholeMatch
            ? candidate == query
            : candidate.contains(query);
        if (matched) {
          matches.add(
            FieldTableCellPosition(
              rowIndex: rowIndex,
              columnIndex: columnIndex,
            ),
          );
        }
      }
    }

    setState(() {
      _fieldSearchMatches = matches;
      _activeFieldSearchMatchIndex = matches.isEmpty ? -1 : 0;
    });
    _ensureActiveSearchMatchVisible();
  }

  void _rebuildSqlSearchMatches() {
    final sql = _currentSqlText(widget.controller.selectedTableDetail);
    final rawQuery = _searchController.text.trim();
    if (sql == null || rawQuery.isEmpty) {
      setState(() {
        _sqlSearchMatches = const [];
        _activeSqlSearchMatchIndex = -1;
      });
      return;
    }

    final matches = _findTextSearchMatches(
      text: sql,
      query: rawQuery,
      caseSensitive: _searchCaseSensitive,
      wholeMatch: _searchWholeMatch,
    );
    setState(() {
      _sqlSearchMatches = matches;
      _activeSqlSearchMatchIndex = matches.isEmpty ? -1 : 0;
    });
    _ensureActiveSearchMatchVisible();
  }

  void _jumpSearchMatch(int delta) {
    if (_searchDebounceTimer?.isActive ?? false) {
      _rebuildSearchMatches();
      return;
    }
    if (_viewMode == _DetailViewMode.fields) {
      if (_fieldSearchMatches.isEmpty) {
        return;
      }
      setState(() {
        final nextIndex =
            (_activeFieldSearchMatchIndex + delta) % _fieldSearchMatches.length;
        _activeFieldSearchMatchIndex = nextIndex < 0
            ? _fieldSearchMatches.length - 1
            : nextIndex;
      });
    } else {
      if (_sqlSearchMatches.isEmpty) {
        return;
      }
      setState(() {
        final nextIndex =
            (_activeSqlSearchMatchIndex + delta) % _sqlSearchMatches.length;
        _activeSqlSearchMatchIndex = nextIndex < 0
            ? _sqlSearchMatches.length - 1
            : nextIndex;
      });
    }
    _ensureActiveSearchMatchVisible(requestTableFocus: true);
  }

  void _ensureActiveSearchMatchVisible({bool requestTableFocus = false}) {
    if (requestTableFocus) {
      _focusNode.requestFocus();
    }

    if (_viewMode == _DetailViewMode.fields) {
      if (_activeFieldSearchMatchIndex < 0 ||
          _activeFieldSearchMatchIndex >= _fieldSearchMatches.length) {
        return;
      }
      final position = _fieldSearchMatches[_activeFieldSearchMatchIndex];
      if (position.rowIndex == 0 || !_fieldTableScrollController.hasClients) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_fieldTableScrollController.hasClients ||
            position.rowIndex - 1 < 0 ||
            position.rowIndex - 1 >= _searchRowKeys.length) {
          return;
        }
        final targetContext =
            _searchRowKeys[position.rowIndex - 1].currentContext;
        if (targetContext == null) {
          return;
        }
        Scrollable.ensureVisible(
          targetContext,
          alignment: 0.2,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      });
      return;
    }

    if (_activeSqlSearchMatchIndex < 0 ||
        _activeSqlSearchMatchIndex >= _sqlSearchMatches.length) {
      return;
    }
    final match = _sqlSearchMatches[_activeSqlSearchMatchIndex];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (requestTableFocus) _sqlTextFocusNode.requestFocus();
      _sqlTextController.selection = TextSelection(
        baseOffset: match.start.clamp(0, _sqlTextController.text.length),
        extentOffset: match.end.clamp(0, _sqlTextController.text.length),
      );
    });
  }

  void _selectSingleCell(FieldTableCellPosition position) {
    _focusNode.requestFocus();
    setState(() {
      _selection = FieldTableSelection(anchor: position, focus: position);
      _isDragging = false;
    });
  }

  void _handleFieldCellTap(FieldTableCellPosition position) {
    final now = DateTime.now();
    final lastPosition = _lastCellTapPosition;
    final repeated =
        lastPosition != null &&
        lastPosition.rowIndex == position.rowIndex &&
        lastPosition.columnIndex == position.columnIndex &&
        _lastCellTapAt != null &&
        now.difference(_lastCellTapAt!) <= const Duration(milliseconds: 420);
    _cellTapCount = repeated ? _cellTapCount + 1 : 1;
    _lastCellTapPosition = position;
    _lastCellTapAt = now;

    if (_cellTapCount >= 3) {
      _cellTapCount = 0;
      _selectAll(includeHeader: true);
      return;
    }
    if (_cellTapCount == 2) {
      _selectRow(position);
      return;
    }
    _selectSingleCell(position);
  }

  void _startDrag(FieldTableCellPosition position) {
    _focusNode.requestFocus();
    setState(() {
      _selection = FieldTableSelection(anchor: position, focus: position);
      _isDragging = true;
    });
  }

  void _updateDrag(FieldTableCellPosition position) {
    if (!_isDragging || _selection == null) {
      return;
    }
    if (_selection!.focus.rowIndex == position.rowIndex &&
        _selection!.focus.columnIndex == position.columnIndex) {
      return;
    }
    setState(() {
      _selection = _selection!.copyWith(focus: position);
    });
  }

  void _endDrag() {
    if (!_isDragging) {
      return;
    }
    setState(() {
      _isDragging = false;
    });
  }

  void _clearSelection() {
    if (_selection == null) {
      return;
    }
    setState(() {
      _selection = null;
      _isDragging = false;
    });
  }

  void _selectAll({bool includeHeader = false}) {
    final detail = widget.controller.selectedTableDetail;
    if (detail == null) {
      return;
    }
    _focusNode.requestFocus();
    setState(() {
      _selection = FieldTableSelection(
        anchor: FieldTableCellPosition(
          rowIndex: includeHeader ? 0 : 1,
          columnIndex: 0,
        ),
        focus: FieldTableCellPosition(
          rowIndex: detail.columns.length,
          columnIndex: _ResponsiveFieldTable.headerLabels.length - 1,
        ),
      );
      _isDragging = false;
    });
  }

  FieldTableSelection? _buildSelectAllSelection({bool includeHeader = false}) {
    final detail = widget.controller.selectedTableDetail;
    if (detail == null) {
      return null;
    }
    return FieldTableSelection(
      anchor: FieldTableCellPosition(
        rowIndex: includeHeader ? 0 : 1,
        columnIndex: 0,
      ),
      focus: FieldTableCellPosition(
        rowIndex: detail.columns.length,
        columnIndex: _ResponsiveFieldTable.headerLabels.length - 1,
      ),
    );
  }

  void _selectRow(FieldTableCellPosition position) {
    _focusNode.requestFocus();
    setState(() {
      _selection = FieldTableSelection(
        anchor: FieldTableCellPosition(
          rowIndex: position.rowIndex,
          columnIndex: 0,
        ),
        focus: FieldTableCellPosition(
          rowIndex: position.rowIndex,
          columnIndex: _ResponsiveFieldTable.headerLabels.length - 1,
        ),
      );
      _isDragging = false;
    });
  }

  void _selectColumn(
    FieldTableCellPosition position, {
    bool includeHeader = false,
  }) {
    final detail = widget.controller.selectedTableDetail;
    if (detail == null) {
      return;
    }
    _focusNode.requestFocus();
    setState(() {
      _selection = FieldTableSelection(
        anchor: FieldTableCellPosition(
          rowIndex: includeHeader ? 0 : 1,
          columnIndex: position.columnIndex,
        ),
        focus: FieldTableCellPosition(
          rowIndex: detail.columns.length,
          columnIndex: position.columnIndex,
        ),
      );
      _isDragging = false;
    });
  }

  Future<void> _copySelection(
    FieldTableSelection selection, {
    bool camelCaseFieldNames = false,
    bool includeHeader = false,
  }) async {
    final detail = widget.controller.selectedTableDetail;
    if (detail == null) {
      return;
    }
    final effectiveSelection = !includeHeader && selection.startRow == 0
        ? (selection.endRow == 0
              ? null
              : FieldTableSelection(
                  anchor: FieldTableCellPosition(
                    rowIndex: 1,
                    columnIndex: selection.startColumn,
                  ),
                  focus: FieldTableCellPosition(
                    rowIndex: selection.endRow,
                    columnIndex: selection.endColumn,
                  ),
                ))
        : selection;
    if (effectiveSelection == null) {
      return;
    }
    final text = buildFieldSelectionCopyText(
      headers: _ResponsiveFieldTable.headerLabels.map(context.tr).toList(),
      columns: detail.columns,
      selection: effectiveSelection,
      camelCaseFieldNames: camelCaseFieldNames,
    );
    if (text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _copyCurrentSelection({
    bool camelCaseFieldNames = false,
    bool includeHeader = false,
  }) async {
    final selection = _selection;
    if (selection == null) {
      return;
    }
    await _copySelection(
      selection,
      camelCaseFieldNames: camelCaseFieldNames,
      includeHeader: includeHeader,
    );
  }

  Future<void> _handleCopy() async {
    final ddlText = _selectedDdlText.trim();
    if (ddlText.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: _selectedDdlText));
      return;
    }
    final dmlText = _selectedDmlText.trim();
    if (dmlText.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: _selectedDmlText));
      return;
    }
    final summaryText = _selectedSummaryText.trim();
    if (summaryText.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: _selectedSummaryText));
      return;
    }
    final currentSqlText = _currentSqlText(
      widget.controller.selectedTableDetail,
    );
    if (currentSqlText != null && currentSqlText.trim().isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: currentSqlText));
      return;
    }
    await _copyCurrentSelection();
  }

  void _selectAllActiveContent() {
    if (_viewMode == _DetailViewMode.fields) {
      _selectAll();
      return;
    }
    final currentSqlText = _currentSqlText(
      widget.controller.selectedTableDetail,
    );
    if (currentSqlText == null || currentSqlText.trim().isEmpty) {
      return;
    }
    _sqlTextFocusNode.requestFocus();
    _sqlTextController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _sqlTextController.text.length,
    );
  }

  Future<void> _showTableContextMenu(
    Offset globalPosition, {
    FieldTableCellPosition? position,
  }) async {
    final isFieldNameCell = position != null && position.columnIndex == 1;
    final includeHeader = position?.rowIndex == 0;
    final headerSuffix = includeHeader ? '(含表头)' : '';
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'copy',
          height: 36,
          child: LText('复制$headerSuffix'),
        ),
        if (isFieldNameCell)
          PopupMenuItem<String>(
            value: 'copyCamelCase',
            height: 36,
            child: LText('驼峰复制$headerSuffix'),
          ),
        PopupMenuItem<String>(
          value: 'selectAll',
          height: 36,
          child: LText('复制全部$headerSuffix'),
        ),
        PopupMenuItem<String>(
          value: 'copyRow',
          height: 36,
          child: LText('复制整行$headerSuffix'),
        ),
        PopupMenuItem<String>(
          value: 'copyColumn',
          height: 36,
          child: LText('复制整列$headerSuffix'),
        ),
        if (isFieldNameCell)
          PopupMenuItem<String>(
            value: 'copyCamelCaseColumn',
            height: 36,
            child: LText('驼峰复制整列$headerSuffix'),
          ),
      ],
    );

    if (!mounted || result == null) {
      return;
    }
    if (result == 'copy' && position != null) {
      final currentSelection = _selection;
      final selection =
          currentSelection != null && currentSelection.contains(position)
          ? currentSelection
          : FieldTableSelection(anchor: position, focus: position);
      if (selection != currentSelection) {
        _selectSingleCell(position);
      }
      await _copySelection(selection, includeHeader: includeHeader);
      return;
    }
    if (result == 'copyCamelCase' && position != null) {
      final currentSelection = _selection;
      final selection =
          currentSelection != null &&
              currentSelection.contains(position) &&
              currentSelection.startColumn == 1 &&
              currentSelection.endColumn == 1
          ? currentSelection
          : FieldTableSelection(anchor: position, focus: position);
      if (selection != currentSelection) {
        _selectSingleCell(position);
      }
      await _copySelection(
        selection,
        camelCaseFieldNames: true,
        includeHeader: includeHeader,
      );
      return;
    }
    if (result == 'copyCamelCaseColumn' && position != null) {
      final detail = widget.controller.selectedTableDetail;
      if (detail == null) {
        return;
      }
      final selection = FieldTableSelection(
        anchor: FieldTableCellPosition(
          rowIndex: includeHeader ? 0 : 1,
          columnIndex: position.columnIndex,
        ),
        focus: FieldTableCellPosition(
          rowIndex: detail.columns.length,
          columnIndex: position.columnIndex,
        ),
      );
      _selectColumn(position, includeHeader: includeHeader);
      await _copySelection(
        selection,
        camelCaseFieldNames: true,
        includeHeader: includeHeader,
      );
      return;
    }
    if (result == 'selectAll') {
      final selection = _buildSelectAllSelection(includeHeader: includeHeader);
      if (selection == null) {
        return;
      }
      _selectAll(includeHeader: includeHeader);
      await _copySelection(selection, includeHeader: includeHeader);
      return;
    }
    if (result == 'copyRow' && position != null) {
      _selectRow(position);
      await _copySelection(
        FieldTableSelection(
          anchor: FieldTableCellPosition(
            rowIndex: position.rowIndex,
            columnIndex: 0,
          ),
          focus: FieldTableCellPosition(
            rowIndex: position.rowIndex,
            columnIndex: _ResponsiveFieldTable.headerLabels.length - 1,
          ),
        ),
        includeHeader: includeHeader,
      );
      return;
    }
    if (result == 'copyColumn' && position != null) {
      final detail = widget.controller.selectedTableDetail;
      if (detail == null) {
        return;
      }
      _selectColumn(position, includeHeader: includeHeader);
      await _copySelection(
        FieldTableSelection(
          anchor: FieldTableCellPosition(
            rowIndex: includeHeader ? 0 : 1,
            columnIndex: position.columnIndex,
          ),
          focus: FieldTableCellPosition(
            rowIndex: detail.columns.length,
            columnIndex: position.columnIndex,
          ),
        ),
        includeHeader: includeHeader,
      );
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final detail = controller.selectedTableDetail;
    final activeTab = controller.activeTableTab;
    _syncSearchRowKeys(detail?.columns.length ?? 0);
    final matchedCellIds = _fieldSearchMatches.map(_searchCellId).toSet();
    final activeMatchedCellId =
        _activeFieldSearchMatchIndex >= 0 &&
            _activeFieldSearchMatchIndex < _fieldSearchMatches.length
        ? _searchCellId(_fieldSearchMatches[_activeFieldSearchMatchIndex])
        : null;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyC, control: true):
            _handleCopy,
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): _handleCopy,
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            _selectAllActiveContent,
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
            _selectAllActiveContent,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _toggleSearchBar,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            _toggleSearchBar,
      },
      child: Focus(
        autofocus: true,
        focusNode: _focusNode,
        child: _WorkspaceContentSurface(
          backgroundColor: AppTheme.surfaceOf(context),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: detail == null || activeTab == null
                    ? const _EmptyBody(
                        icon: Icons.table_chart_outlined,
                        title: '表字段详情',
                        description: '从上方表列表选择一张表后，这里会显示字段详情。',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _WindowsSemanticsWorkaround(
                                  child: SelectableText(
                                    _buildDetailSummary(
                                      tab: activeTab,
                                      isGlobal:
                                          controller.searchTarget ==
                                          SearchTarget.allProjects,
                                    ),
                                    focusNode: _summaryFocusNode,
                                    onSelectionChanged: (selection, cause) {
                                      final text = _buildDetailSummary(
                                        tab: activeTab,
                                        isGlobal:
                                            controller.searchTarget ==
                                            SearchTarget.allProjects,
                                      );
                                      final normalized = selection.isCollapsed
                                          ? ''
                                          : selection.textInside(text);
                                      setState(() {
                                        _selectedSummaryText = normalized;
                                      });
                                    },
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _Pill(text: '${detail.columns.length} 个字段'),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _buildViewToolbar(context),
                          const SizedBox(height: 10),
                          Expanded(
                            child: _viewMode == _DetailViewMode.fields
                                ? GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _clearSelection,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: AppTheme.surfaceOf(context),
                                      ),
                                      child: Listener(
                                        onPointerDown: (_) {
                                          _focusNode.requestFocus();
                                          if (_selectedSummaryText.isNotEmpty) {
                                            setState(() {
                                              _selectedSummaryText = '';
                                            });
                                          }
                                        },
                                        child: _ResponsiveFieldTable(
                                          columns: detail.columns,
                                          rowKeys: _searchRowKeys,
                                          highlightedColumnIds: controller
                                              .highlightedColumnIds
                                              .toSet(),
                                          selection: _selection,
                                          matchedCellIds: matchedCellIds,
                                          activeMatchedCellId:
                                              activeMatchedCellId,
                                          scrollController:
                                              _fieldTableScrollController,
                                          onCellTap: _handleFieldCellTap,
                                          onCellDragStart: _startDrag,
                                          onCellDragEnter: _updateDrag,
                                          onCellDragEnd: _endDrag,
                                          onCellSecondaryTapDown:
                                              (position, globalPosition) {
                                                _focusNode.requestFocus();
                                                _showTableContextMenu(
                                                  globalPosition,
                                                  position: position,
                                                );
                                              },
                                        ),
                                      ),
                                    ),
                                  )
                                : _viewMode == _DetailViewMode.ddl
                                ? _buildDdlView(context, detail)
                                : _buildDmlView(context, detail),
                          ),
                        ],
                      ),
              ),
              if (detail != null &&
                  activeTab != null &&
                  _viewMode == _DetailViewMode.fields)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _DetailSearchOverlay(
                    expanded: _searchBarExpanded,
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    hintText: context.tr(_searchOverlayHintText()),
                    caseSensitive: _searchCaseSensitive,
                    wholeMatch: _searchWholeMatch,
                    matchCount: _currentSearchMatchCount(),
                    onToggleExpanded: _toggleSearchBar,
                    onCaseSensitiveChanged: (value) {
                      setState(() {
                        _searchCaseSensitive = value;
                      });
                      _rebuildSearchMatches();
                    },
                    onWholeMatchChanged: (value) {
                      setState(() {
                        _searchWholeMatch = value;
                      });
                      _rebuildSearchMatches();
                    },
                    onChanged: (_) => _scheduleDetailSearch(),
                    onSubmitted: (_) {
                      if ((_searchDebounceTimer?.isActive ?? false) ||
                          _currentSearchMatchCount() == 0) {
                        _rebuildSearchMatches();
                      } else {
                        _jumpSearchMatch(1);
                      }
                    },
                    onPrevious: () => _jumpSearchMatch(-1),
                    onNext: () => _jumpSearchMatch(1),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewToolbar(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SegmentedButton<_DetailViewMode>(
            segments: const [
              ButtonSegment<_DetailViewMode>(
                value: _DetailViewMode.fields,
                label: LText('字段视图'),
                icon: Icon(Icons.table_rows_outlined, size: 16),
              ),
              ButtonSegment<_DetailViewMode>(
                value: _DetailViewMode.ddl,
                label: LText('DDL 视图'),
                icon: Icon(Icons.code_outlined, size: 16),
              ),
              ButtonSegment<_DetailViewMode>(
                value: _DetailViewMode.dml,
                label: LText('DML 视图'),
                icon: Icon(Icons.dataset_linked_outlined, size: 16),
              ),
            ],
            selected: {_viewMode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              final next = selection.first;
              if (next == _viewMode) {
                return;
              }
              setState(() {
                _viewMode = next;
                _selectedSummaryText = '';
                _selectedDdlText = '';
                _selectedDmlText = '';
                if (_viewMode != _DetailViewMode.fields) {
                  _selection = null;
                  _isDragging = false;
                }
              });
              _rebuildSearchMatches();
            },
          ),
          if (_viewMode != _DetailViewMode.fields) ...[
            const SizedBox(width: 12),
            SegmentedButton<DdlDialect>(
              segments: const [
                ButtonSegment<DdlDialect>(
                  value: DdlDialect.oracle,
                  label: Text('Oracle'),
                ),
                ButtonSegment<DdlDialect>(
                  value: DdlDialect.mysql,
                  label: Text('MySQL'),
                ),
                ButtonSegment<DdlDialect>(
                  value: DdlDialect.postgresql,
                  label: Text('PostgreSQL'),
                ),
              ],
              selected: {_ddlDialect},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                setState(() {
                  _ddlDialect = selection.first;
                });
                _rebuildSearchMatches();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDdlView(BuildContext context, TableDetail detail) {
    final ddl = buildTableDdl(detail, _ddlDialect);
    return _buildSqlTextView(
      context,
      sql: ddl,
      scrollController: _sqlTextScrollController,
      onCopyPressed: () async {
        await Clipboard.setData(
          ClipboardData(
            text: _selectedDdlText.trim().isNotEmpty ? _selectedDdlText : ddl,
          ),
        );
      },
    );
  }

  Widget _buildDmlView(BuildContext context, TableDetail detail) {
    final dml = buildTableDml(detail, _ddlDialect);
    return _buildSqlTextView(
      context,
      sql: dml,
      scrollController: _sqlTextScrollController,
      onCopyPressed: () async {
        await Clipboard.setData(
          ClipboardData(
            text: _selectedDmlText.trim().isNotEmpty ? _selectedDmlText : dml,
          ),
        );
      },
    );
  }

  Widget _buildSqlTextView(
    BuildContext context, {
    required String sql,
    required ScrollController scrollController,
    required Future<void> Function() onCopyPressed,
  }) {
    _syncSqlTextController(sql);
    return DecoratedBox(
      decoration: BoxDecoration(color: AppTheme.surfaceOf(context)),
      child: Listener(
        onPointerDown: (_) {
          _sqlTextFocusNode.requestFocus();
          if (_selectedSummaryText.isNotEmpty) {
            setState(() {
              _selectedSummaryText = '';
            });
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              Positioned.fill(
                child: _buildPlainSqlTextField(
                  context,
                  controller: _sqlTextController,
                  focusNode: _sqlTextFocusNode,
                  scrollController: scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  tooltip: context.tr('复制'),
                  visualDensity: const VisualDensity(
                    horizontal: -2,
                    vertical: -2,
                  ),
                  onPressed: onCopyPressed,
                  icon: const Icon(Icons.content_copy_outlined, size: 18),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: _DetailSearchOverlay(
                  expanded: _searchBarExpanded,
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  caseSensitive: _searchCaseSensitive,
                  wholeMatch: _searchWholeMatch,
                  matchCount: _currentSearchMatchCount(),
                  hintText: context.tr(_searchOverlayHintText()),
                  onToggleExpanded: _toggleSearchBar,
                  onCaseSensitiveChanged: (value) {
                    setState(() {
                      _searchCaseSensitive = value;
                    });
                    _rebuildSearchMatches();
                  },
                  onWholeMatchChanged: (value) {
                    setState(() {
                      _searchWholeMatch = value;
                    });
                    _rebuildSearchMatches();
                  },
                  onChanged: (_) => _scheduleDetailSearch(),
                  onSubmitted: (_) {
                    if ((_searchDebounceTimer?.isActive ?? false) ||
                        _currentSearchMatchCount() == 0) {
                      _rebuildSearchMatches();
                    } else {
                      _jumpSearchMatch(1);
                    }
                  },
                  onPrevious: () => _jumpSearchMatch(-1),
                  onNext: () => _jumpSearchMatch(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResponsiveFieldTable extends StatefulWidget {
  const _ResponsiveFieldTable({
    required this.columns,
    required this.rowKeys,
    required this.highlightedColumnIds,
    required this.selection,
    required this.matchedCellIds,
    required this.activeMatchedCellId,
    required this.scrollController,
    required this.onCellTap,
    required this.onCellDragStart,
    required this.onCellDragEnter,
    required this.onCellDragEnd,
    required this.onCellSecondaryTapDown,
  });

  static const List<_FieldColumnDefinition> _columnDefs = [
    _FieldColumnDefinition(label: '主键', flex: 3, align: TextAlign.center),
    _FieldColumnDefinition(label: '字段名', flex: 10),
    _FieldColumnDefinition(label: '字段描述', flex: 10),
    _FieldColumnDefinition(label: '类型', flex: 8),
    _FieldColumnDefinition(label: '长度', flex: 6, align: TextAlign.center),
    _FieldColumnDefinition(label: '精度', flex: 6, align: TextAlign.center),
    _FieldColumnDefinition(label: '可空', flex: 6, align: TextAlign.center),
    _FieldColumnDefinition(label: '默认值', flex: 6, align: TextAlign.center),
    _FieldColumnDefinition(label: '备注', flex: 10),
  ];

  static const List<String> headerLabels = [
    '主键',
    '字段名',
    '字段描述',
    '类型',
    '长度',
    '精度',
    '可空',
    '默认值',
    '备注',
  ];

  final List<TableDetailColumn> columns;
  final List<GlobalKey> rowKeys;
  final Set<String> highlightedColumnIds;
  final FieldTableSelection? selection;
  final Set<String> matchedCellIds;
  final String? activeMatchedCellId;
  final ScrollController scrollController;
  final ValueChanged<FieldTableCellPosition> onCellTap;
  final ValueChanged<FieldTableCellPosition> onCellDragStart;
  final ValueChanged<FieldTableCellPosition> onCellDragEnter;
  final VoidCallback onCellDragEnd;
  final void Function(FieldTableCellPosition position, Offset globalPosition)
  onCellSecondaryTapDown;

  @override
  State<_ResponsiveFieldTable> createState() => _ResponsiveFieldTableState();
}

class _ResponsiveFieldTableState extends State<_ResponsiveFieldTable> {
  static const List<double> _minColumnWidths = [
    40,
    40,
    40,
    40,
    48,
    40,
    40,
    40,
    40,
  ];

  late List<double> _columnFractions;
  final ScrollController _horizontalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _columnFractions = _buildDefaultFractions();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  List<double> _buildDefaultFractions() {
    final totalFlex = _ResponsiveFieldTable._columnDefs.fold<int>(
      0,
      (sum, definition) => sum + definition.flex,
    );
    return _ResponsiveFieldTable._columnDefs
        .map((definition) => definition.flex / totalFlex)
        .toList(growable: false);
  }

  List<double> _resolveColumnWidths(double availableWidth) {
    final normalizedWidth = availableWidth <= 0 ? 1.0 : availableWidth;
    final widths = <double>[];
    var consumed = 0.0;
    for (var index = 0; index < _columnFractions.length; index++) {
      if (index == _columnFractions.length - 1) {
        widths.add(
          (normalizedWidth - consumed).clamp(
            _minColumnWidths[index],
            normalizedWidth,
          ),
        );
      } else {
        final width = _columnFractions[index] * normalizedWidth;
        widths.add(width);
        consumed += width;
      }
    }
    return widths;
  }

  void _resizeColumn(int columnIndex, double delta, double availableWidth) {
    if (columnIndex < 0 || columnIndex >= _columnFractions.length - 1) {
      return;
    }
    final widths = _resolveColumnWidths(availableWidth);
    final currentWidth = widths[columnIndex];
    final nextWidth = widths[columnIndex + 1];
    final minCurrent = _minColumnWidths[columnIndex];
    final minNext = _minColumnWidths[columnIndex + 1];
    final maxCurrent = currentWidth + nextWidth - minNext;
    final targetCurrent = (currentWidth + delta).clamp(minCurrent, maxCurrent);
    final appliedDelta = targetCurrent - currentWidth;
    if (appliedDelta.abs() < 0.1) {
      return;
    }

    setState(() {
      final updated = List<double>.from(_columnFractions);
      updated[columnIndex] = targetCurrent / availableWidth;
      updated[columnIndex + 1] = (nextWidth - appliedDelta) / availableWidth;
      _columnFractions = updated;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minTableWidth = _minColumnWidths.fold<double>(
          16,
          (sum, width) => sum + width,
        );
        final tableWidth = constraints.maxWidth
            .clamp(minTableWidth, double.infinity)
            .toDouble();
        final contentWidth = tableWidth - 16;
        final columnWidths = _resolveColumnWidths(contentWidth);

        return Scrollbar(
          controller: _horizontalScrollController,
          thumbVisibility: constraints.maxWidth < tableWidth,
          interactive: true,
          child: SingleChildScrollView(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                children: [
                  _buildHeaderRow(columnWidths, contentWidth),
                  const Divider(height: 1, thickness: 1),
                  Expanded(
                    child: Scrollbar(
                      controller: widget.scrollController,
                      thumbVisibility: true,
                      interactive: true,
                      child: SingleChildScrollView(
                        controller: widget.scrollController,
                        child: _buildBodyRows(columnWidths),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderRow(List<double> columnWidths, double contentWidth) {
    final headerFullySelected = _isFullRowSelected(0);
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: headerFullySelected
          ? AppTheme.selectionFill(context)
          : AppTheme.tableHeaderFill(context),
      child: Row(
        children: [
          for (
            var columnIndex = 0;
            columnIndex < _ResponsiveFieldTable._columnDefs.length;
            columnIndex++
          )
            _SelectableHeaderCell(
              width: columnWidths[columnIndex],
              definition: _ResponsiveFieldTable._columnDefs[columnIndex],
              position: FieldTableCellPosition(
                rowIndex: 0,
                columnIndex: columnIndex,
              ),
              selection: widget.selection,
              matchedCellIds: widget.matchedCellIds,
              activeMatchedCellId: widget.activeMatchedCellId,
              fullRowSelected: headerFullySelected,
              onTap: widget.onCellTap,
              onDragStart: widget.onCellDragStart,
              onDragEnter: widget.onCellDragEnter,
              onDragEnd: widget.onCellDragEnd,
              onSecondaryTapDown: widget.onCellSecondaryTapDown,
              showResizeHandle:
                  columnIndex < _ResponsiveFieldTable._columnDefs.length - 1,
              onResizeDelta: (delta) =>
                  _resizeColumn(columnIndex, delta, contentWidth),
            ),
        ],
      ),
    );
  }

  Widget _buildBodyRows(List<double> columnWidths) {
    return Column(
      children: [
        for (
          var rowIndex = 0;
          rowIndex < widget.columns.length;
          rowIndex++
        ) ...[
          if (rowIndex > 0) const Divider(height: 1, thickness: 1),
          Builder(
            builder: (context) {
              final column = widget.columns[rowIndex];
              final rowHighlighted = widget.highlightedColumnIds.contains(
                column.id,
              );
              final fullRowSelected = _isFullRowSelected(rowIndex + 1);
              return Container(
                key: rowIndex < widget.rowKeys.length
                    ? widget.rowKeys[rowIndex]
                    : null,
                color: fullRowSelected
                    ? AppTheme.selectionFill(context)
                    : rowHighlighted
                    ? AppTheme.searchHighlight(context)
                    : null,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (
                        var columnIndex = 0;
                        columnIndex < _ResponsiveFieldTable._columnDefs.length;
                        columnIndex++
                      )
                        _SelectableDataCell(
                          width: columnWidths[columnIndex],
                          definition:
                              _ResponsiveFieldTable._columnDefs[columnIndex],
                          position: FieldTableCellPosition(
                            rowIndex: rowIndex + 1,
                            columnIndex: columnIndex,
                          ),
                          selection: widget.selection,
                          matchedCellIds: widget.matchedCellIds,
                          activeMatchedCellId: widget.activeMatchedCellId,
                          displayText: _displayFieldCellValue(
                            column,
                            columnIndex,
                          ),
                          isPrimaryKeyCell:
                              columnIndex == 0 && column.isPrimaryKey,
                          rowHighlighted: rowHighlighted,
                          fullRowSelected: fullRowSelected,
                          onTap: widget.onCellTap,
                          onDragStart: widget.onCellDragStart,
                          onDragEnter: widget.onCellDragEnter,
                          onDragEnd: widget.onCellDragEnd,
                          onSecondaryTapDown: widget.onCellSecondaryTapDown,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  bool _isFullRowSelected(int rowIndex) {
    final selection = widget.selection;
    return selection != null &&
        rowIndex >= selection.startRow &&
        rowIndex <= selection.endRow &&
        selection.startColumn == 0 &&
        selection.endColumn == _ResponsiveFieldTable._columnDefs.length - 1;
  }
}

class _FieldColumnDefinition {
  const _FieldColumnDefinition({
    required this.label,
    required this.flex,
    this.align = TextAlign.start,
  });

  final String label;
  final int flex;
  final TextAlign align;
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.label, required this.align});

  final String label;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final alignment = switch (align) {
      TextAlign.center => Alignment.center,
      TextAlign.right || TextAlign.end => Alignment.centerRight,
      _ => Alignment.centerLeft,
    };
    return Align(
      alignment: alignment,
      child: LText(
        label,
        textAlign: align,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          height: 1.0,
        ),
      ),
    );
  }
}

Widget _buildPlainSqlTextField(
  BuildContext context, {
  required TextEditingController controller,
  required FocusNode focusNode,
  required ScrollController scrollController,
  required EdgeInsetsGeometry padding,
}) {
  final theme = Theme.of(context);
  return Theme(
    data: theme.copyWith(
      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: AppTheme.surfaceOf(context),
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        contentPadding: padding,
        isDense: true,
      ),
    ),
    child: TextField(
      controller: controller,
      focusNode: focusNode,
      scrollController: scrollController,
      readOnly: true,
      showCursor: false,
      enableInteractiveSelection: true,
      expands: true,
      minLines: null,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      style:
          theme.textTheme.bodySmall?.copyWith(height: 1.35) ??
          const TextStyle(fontSize: 12, height: 1.35),
      decoration: const InputDecoration(),
    ),
  );
}

class _HighlightedSqlTextBlock extends StatelessWidget {
  const _HighlightedSqlTextBlock({
    required this.text,
    required this.matches,
    required this.activeMatchIndex,
    required this.baseStyle,
  });

  final String text;
  final List<_TextSearchMatch> matches;
  final int activeMatchIndex;
  final TextStyle? baseStyle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SelectableText.rich(
        TextSpan(style: baseStyle, children: _buildTextSpans(context)),
      ),
    );
  }

  List<InlineSpan> _buildTextSpans(BuildContext context) {
    if (matches.isEmpty) {
      return [TextSpan(text: text.isEmpty ? ' ' : text)];
    }
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      final start = match.start.clamp(0, text.length);
      final end = match.end.clamp(0, text.length);
      if (cursor < start) {
        spans.add(TextSpan(text: text.substring(cursor, start)));
      }
      if (start < end) {
        spans.add(
          TextSpan(
            text: text.substring(start, end),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              backgroundColor: AppTheme.searchHighlight(
                context,
                active: index == activeMatchIndex,
              ),
            ),
          ),
        );
      }
      cursor = end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return spans;
  }
}

class _TextSearchMatch {
  const _TextSearchMatch({
    required this.start,
    required this.end,
    required this.lineIndex,
  });

  final int start;
  final int end;
  final int lineIndex;
}

List<_TextSearchMatch> _findTextSearchMatches({
  required String text,
  required String query,
  required bool caseSensitive,
  required bool wholeMatch,
}) {
  final trimmedQuery = query.trim();
  if (text.isEmpty || trimmedQuery.isEmpty) {
    return const [];
  }

  final source = caseSensitive ? text : text.toLowerCase();
  final pattern = caseSensitive ? trimmedQuery : trimmedQuery.toLowerCase();
  final matches = <_TextSearchMatch>[];
  final lineStartOffsets = _computeLineStartOffsets(text);
  var searchStart = 0;

  while (searchStart <= source.length - pattern.length) {
    final index = source.indexOf(pattern, searchStart);
    if (index < 0) {
      break;
    }
    final end = index + pattern.length;
    final boundaryMatched =
        !wholeMatch ||
        (_isWordBoundary(source, index - 1) && _isWordBoundary(source, end));
    if (boundaryMatched) {
      matches.add(
        _TextSearchMatch(
          start: index,
          end: end,
          lineIndex: _resolveLineIndex(lineStartOffsets, index),
        ),
      );
    }
    searchStart = index + pattern.length;
  }

  return matches;
}

List<int> _computeLineStartOffsets(String text) {
  final offsets = <int>[0];
  for (var index = 0; index < text.length; index++) {
    if (text.codeUnitAt(index) == 10 && index + 1 < text.length) {
      offsets.add(index + 1);
    }
  }
  return offsets;
}

int _resolveLineIndex(List<int> lineStartOffsets, int offset) {
  var low = 0;
  var high = lineStartOffsets.length - 1;
  while (low <= high) {
    final mid = low + ((high - low) >> 1);
    final start = lineStartOffsets[mid];
    final nextStart = mid + 1 < lineStartOffsets.length
        ? lineStartOffsets[mid + 1]
        : 0x7fffffff;
    if (offset < start) {
      high = mid - 1;
    } else if (offset >= nextStart) {
      low = mid + 1;
    } else {
      return mid;
    }
  }
  return 0;
}

bool _isWordBoundary(String text, int index) {
  if (index < 0 || index >= text.length) {
    return true;
  }
  final char = text[index];
  return !RegExp(r'[A-Za-z0-9_\u4E00-\u9FFF]').hasMatch(char);
}

class _SelectableHeaderCell extends StatelessWidget {
  const _SelectableHeaderCell({
    required this.width,
    required this.definition,
    required this.position,
    required this.selection,
    required this.matchedCellIds,
    required this.activeMatchedCellId,
    required this.fullRowSelected,
    required this.onTap,
    required this.onDragStart,
    required this.onDragEnter,
    required this.onDragEnd,
    required this.onSecondaryTapDown,
    required this.showResizeHandle,
    required this.onResizeDelta,
  });

  final double width;
  final _FieldColumnDefinition definition;
  final FieldTableCellPosition position;
  final FieldTableSelection? selection;
  final Set<String> matchedCellIds;
  final String? activeMatchedCellId;
  final bool fullRowSelected;
  final ValueChanged<FieldTableCellPosition> onTap;
  final ValueChanged<FieldTableCellPosition> onDragStart;
  final ValueChanged<FieldTableCellPosition> onDragEnter;
  final VoidCallback onDragEnd;
  final void Function(FieldTableCellPosition position, Offset globalPosition)
  onSecondaryTapDown;
  final bool showResizeHandle;
  final ValueChanged<double> onResizeDelta;

  @override
  Widget build(BuildContext context) {
    final isSelected = selection?.contains(position) ?? false;
    final cellId = '${position.rowIndex}:${position.columnIndex}';
    final isMatch = matchedCellIds.contains(cellId);
    final isActiveMatch = activeMatchedCellId == cellId;
    final borderColor = !fullRowSelected && !isSelected && isActiveMatch
        ? AppTheme.primaryOf(context)
        : Colors.transparent;
    return SizedBox(
      width: width,
      child: MouseRegion(
        onEnter: (_) => onDragEnter(position),
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(position),
              onPanStart: (_) => onDragStart(position),
              onPanEnd: (_) => onDragEnd(),
              onPanCancel: onDragEnd,
              onSecondaryTapDown: (details) =>
                  onSecondaryTapDown(position, details.globalPosition),
              child: Container(
                decoration: BoxDecoration(
                  color: fullRowSelected
                      ? null
                      : isSelected
                      ? AppTheme.selectionFill(context)
                      : isActiveMatch
                      ? AppTheme.searchHighlight(context, active: true)
                      : isMatch
                      ? AppTheme.searchHighlight(context)
                      : null,
                  border: Border.all(color: borderColor, width: 1.5),
                ),
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
                child: _HeaderCell(
                  label: definition.label,
                  align: definition.align,
                ),
              ),
            ),
            if (showResizeHandle)
              Positioned(
                top: 0,
                right: -4,
                bottom: 0,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: (details) =>
                        onResizeDelta(details.delta.dx),
                    child: const SizedBox(width: 8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SelectableDataCell extends StatelessWidget {
  const _SelectableDataCell({
    required this.width,
    required this.definition,
    required this.position,
    required this.selection,
    required this.matchedCellIds,
    required this.activeMatchedCellId,
    required this.displayText,
    required this.isPrimaryKeyCell,
    required this.rowHighlighted,
    required this.fullRowSelected,
    required this.onTap,
    required this.onDragStart,
    required this.onDragEnter,
    required this.onDragEnd,
    required this.onSecondaryTapDown,
  });

  final double width;
  final _FieldColumnDefinition definition;
  final FieldTableCellPosition position;
  final FieldTableSelection? selection;
  final Set<String> matchedCellIds;
  final String? activeMatchedCellId;
  final String displayText;
  final bool isPrimaryKeyCell;
  final bool rowHighlighted;
  final bool fullRowSelected;
  final ValueChanged<FieldTableCellPosition> onTap;
  final ValueChanged<FieldTableCellPosition> onDragStart;
  final ValueChanged<FieldTableCellPosition> onDragEnter;
  final VoidCallback onDragEnd;
  final void Function(FieldTableCellPosition position, Offset globalPosition)
  onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final isSelected = selection?.contains(position) ?? false;
    final cellId = '${position.rowIndex}:${position.columnIndex}';
    final isMatch = matchedCellIds.contains(cellId);
    final isActiveMatch = activeMatchedCellId == cellId;
    final backgroundColor = fullRowSelected
        ? null
        : isSelected
        ? AppTheme.selectionFill(context)
        : isActiveMatch
        ? AppTheme.searchHighlight(context, active: true)
        : isMatch
        ? AppTheme.searchHighlight(context)
        : rowHighlighted
        ? const Color(0x00FFFFFF)
        : null;
    final borderColor = !fullRowSelected && !isSelected && isActiveMatch
        ? AppTheme.primaryOf(context)
        : Colors.transparent;

    Widget child;
    if (isPrimaryKeyCell) {
      child = Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            borderRadius: AppTheme.controlRadiusOf(context),
            color: Theme.of(context).colorScheme.primary,
          ),
          child: Text(
            'PK',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ),
      );
    } else {
      child = Text(
        position.columnIndex == 0 || position.columnIndex == 6
            ? context.tr(displayText)
            : displayText,
        softWrap: true,
        textAlign: definition.align,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.1),
      );
    }

    return SizedBox(
      width: width,
      child: MouseRegion(
        onEnter: (_) => onDragEnter(position),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(position),
          onPanStart: (_) => onDragStart(position),
          onPanEnd: (_) => onDragEnd(),
          onPanCancel: onDragEnd,
          onSecondaryTapDown: (details) =>
              onSecondaryTapDown(position, details.globalPosition),
          child: Container(
            decoration: BoxDecoration(
              color: backgroundColor,
              border: Border.all(color: borderColor, width: 1.5),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _DetailSearchOverlay extends StatelessWidget {
  const _DetailSearchOverlay({
    required this.expanded,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.caseSensitive,
    required this.wholeMatch,
    required this.matchCount,
    required this.onToggleExpanded,
    required this.onCaseSensitiveChanged,
    required this.onWholeMatchChanged,
    required this.onChanged,
    required this.onSubmitted,
    required this.onPrevious,
    required this.onNext,
  });

  final bool expanded;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final bool caseSensitive;
  final bool wholeMatch;
  final int matchCount;
  final VoidCallback onToggleExpanded;
  final ValueChanged<bool> onCaseSensitiveChanged;
  final ValueChanged<bool> onWholeMatchChanged;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  Widget _optionButton(
    BuildContext context, {
    required String label,
    required String tooltip,
    required bool selected,
    required VoidCallback onPressed,
    bool underline = false,
  }) {
    final theme = Theme.of(context);
    return IconButton(
      tooltip: context.tr(tooltip),
      isSelected: selected,
      onPressed: onPressed,
      constraints: const BoxConstraints.tightFor(width: 28, height: 30),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: selected
            ? AppTheme.selectionFill(context)
            : Colors.transparent,
        side: selected
            ? BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              )
            : BorderSide.none,
      ),
      icon: Text(
        label,
        textScaler: TextScaler.noScaling,
        style: theme.textTheme.labelLarge?.copyWith(
          fontSize: 14,
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
          decoration: underline ? TextDecoration.underline : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = AppTheme.outlineSoft(context);

    return Align(
      alignment: Alignment.bottomRight,
      child: Material(
        color: Colors.transparent,
        child: expanded
            ? Container(
                key: const ValueKey('detail-search-bar'),
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.shadow.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                  borderRadius: AppTheme.controlRadiusOf(context),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SearchTextField(
                        controller: controller,
                        focusNode: focusNode,
                        onChanged: onChanged,
                        onSubmitted: onSubmitted,
                        decoration: InputDecoration(
                          hintText: context.tr(hintText),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _optionButton(
                      context,
                      label: 'Aa',
                      tooltip: context.tr('区分大小写'),
                      selected: caseSensitive,
                      onPressed: () => onCaseSensitiveChanged(!caseSensitive),
                    ),
                    _optionButton(
                      context,
                      label: 'ab',
                      tooltip: context.tr('全字匹配'),
                      selected: wholeMatch,
                      underline: true,
                      onPressed: () => onWholeMatchChanged(!wholeMatch),
                    ),
                    IconButton(
                      tooltip: context.tr('上一个'),
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 30,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: matchCount == 0 ? null : onPrevious,
                      icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                    ),
                    IconButton(
                      tooltip: context.tr('下一个'),
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 30,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: matchCount == 0 ? null : onNext,
                      icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                    ),
                    IconButton(
                      tooltip: context.tr('关闭搜索'),
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 30,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: onToggleExpanded,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              )
            : FloatingActionButton.small(
                elevation: 0,
                hoverElevation: 1,
                focusElevation: 0,
                highlightElevation: 0,
                onPressed: onToggleExpanded,
                tooltip: context.tr(hintText),
                child: const Icon(Icons.search),
              ),
      ),
    );
  }
}

class _WorkspaceTabsBar extends StatefulWidget {
  const _WorkspaceTabsBar({
    required this.activeTabId,
    required this.detailTabs,
    required this.onSelect,
    required this.onClose,
    required this.onCloseOthers,
    required this.onCloseLeft,
    required this.onCloseRight,
    required this.onCloseAll,
  });

  final String activeTabId;
  final List<TableDetailTab> detailTabs;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final ValueChanged<String> onCloseOthers;
  final ValueChanged<String> onCloseLeft;
  final ValueChanged<String> onCloseRight;
  final VoidCallback onCloseAll;

  @override
  State<_WorkspaceTabsBar> createState() => _WorkspaceTabsBarState();
}

class _WorkspaceTabsBarState extends State<_WorkspaceTabsBar> {
  static const double _scrollStep = 220;
  static const String _homeTabId = _ProjectWorkspaceViewState._homeTabId;
  final ScrollController _scrollController = ScrollController();
  bool _showScrollButtons = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncOverflowState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflowState());
  }

  @override
  void didUpdateWidget(covariant _WorkspaceTabsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detailTabs.length != widget.detailTabs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflowState());
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_syncOverflowState);
    _scrollController.dispose();
    super.dispose();
  }

  void _syncOverflowState() {
    if (!_scrollController.hasClients) {
      return;
    }
    final nextValue = _scrollController.position.maxScrollExtent > 0;
    if (nextValue != _showScrollButtons && mounted) {
      setState(() {
        _showScrollButtons = nextValue;
      });
    }
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) {
      return;
    }
    final delta = event.scrollDelta.dy == 0
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) {
      return;
    }
    final position = _scrollController.position;
    final target = (_scrollController.offset + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = AppTheme.outlineSoft(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.tabStripFill(context),
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: (notification) {
                  _syncOverflowState();
                  return false;
                },
                child: Listener(
                  onPointerSignal: _handlePointerSignal,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _WorkspaceHomeTabChip(
                          selected: widget.activeTabId == _homeTabId,
                          onTap: () => widget.onSelect(_homeTabId),
                        ),
                        const SizedBox(width: 6),
                        for (final tab in widget.detailTabs) ...[
                          _TableTabChip(
                            tab: tab,
                            selected: tab.id == widget.activeTabId,
                            onTap: () => widget.onSelect(tab.id),
                            onClose: () => widget.onClose(tab.id),
                            onCloseOthers: () => widget.onCloseOthers(tab.id),
                            onCloseLeft: () => widget.onCloseLeft(tab.id),
                            onCloseRight: () => widget.onCloseRight(tab.id),
                            onCloseAll: widget.onCloseAll,
                          ),
                          const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_showScrollButtons) ...[
              const SizedBox(width: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TabScrollButton(
                    icon: Icons.chevron_left,
                    tooltip: context.tr('向左滚动页签'),
                    onPressed: () => _scrollBy(-_scrollStep),
                  ),
                  const SizedBox(width: 2),
                  _TabScrollButton(
                    icon: Icons.chevron_right,
                    tooltip: context.tr('向右滚动页签'),
                    onPressed: () => _scrollBy(_scrollStep),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkspaceHomeTabChip extends StatelessWidget {
  const _WorkspaceHomeTabChip({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = selected
        ? AppTheme.tabActiveFill(context)
        : AppTheme.tabInactiveFill(context);
    final foregroundColor = selected
        ? AppTheme.tabActiveForeground(context)
        : AppTheme.tabInactiveForeground(context);

    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.tabRadiusOf(context),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: AppTheme.tabRadiusOf(context),
          color: backgroundColor,
        ),
        child: Container(
          decoration: selected ? AppTheme.tabIndicatorOf(context) : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.home_outlined, size: 14, color: foregroundColor),
              const SizedBox(width: 6),
              LText(
                '主页',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: foregroundColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TableTabsBar extends StatefulWidget {
  const _TableTabsBar({
    required this.tabs,
    required this.activeTabId,
    required this.onSelect,
    required this.onClose,
    required this.onCloseOthers,
    required this.onCloseLeft,
    required this.onCloseRight,
    required this.onCloseAll,
  });

  final List<TableDetailTab> tabs;
  final String? activeTabId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final ValueChanged<String> onCloseOthers;
  final ValueChanged<String> onCloseLeft;
  final ValueChanged<String> onCloseRight;
  final VoidCallback onCloseAll;

  @override
  State<_TableTabsBar> createState() => _TableTabsBarState();
}

class _TableTabsBarState extends State<_TableTabsBar> {
  static const double _scrollStep = 220;
  final ScrollController _scrollController = ScrollController();
  bool _showScrollButtons = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncOverflowState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflowState());
  }

  @override
  void didUpdateWidget(covariant _TableTabsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabs.length != widget.tabs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflowState());
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_syncOverflowState);
    _scrollController.dispose();
    super.dispose();
  }

  void _syncOverflowState() {
    if (!_scrollController.hasClients) {
      return;
    }
    final nextValue = _scrollController.position.maxScrollExtent > 0;
    if (nextValue != _showScrollButtons && mounted) {
      setState(() {
        _showScrollButtons = nextValue;
      });
    }
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) {
      return;
    }
    final delta = event.scrollDelta.dy == 0
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) {
      return;
    }
    final position = _scrollController.position;
    final target = (_scrollController.offset + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (notification) {
              _syncOverflowState();
              return false;
            },
            child: Listener(
              onPointerSignal: _handlePointerSignal,
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final tab in widget.tabs) ...[
                      _TableTabChip(
                        tab: tab,
                        selected: tab.id == widget.activeTabId,
                        onTap: () => widget.onSelect(tab.id),
                        onClose: () => widget.onClose(tab.id),
                        onCloseOthers: () => widget.onCloseOthers(tab.id),
                        onCloseLeft: () => widget.onCloseLeft(tab.id),
                        onCloseRight: () => widget.onCloseRight(tab.id),
                        onCloseAll: widget.onCloseAll,
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_showScrollButtons) ...[
          const SizedBox(width: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TabScrollButton(
                icon: Icons.chevron_left,
                tooltip: context.tr('向左滚动页签'),
                onPressed: () => _scrollBy(-_scrollStep),
              ),
              const SizedBox(width: 2),
              _TabScrollButton(
                icon: Icons.chevron_right,
                tooltip: context.tr('向右滚动页签'),
                onPressed: () => _scrollBy(_scrollStep),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TabScrollButton extends StatelessWidget {
  const _TabScrollButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: context.tr(tooltip),
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      constraints: const BoxConstraints.tightFor(width: 26, height: 26),
      padding: EdgeInsets.zero,
      splashRadius: 16,
      icon: Icon(icon, size: 18),
    );
  }
}

class _TableTabChip extends StatelessWidget {
  const _TableTabChip({
    required this.tab,
    required this.selected,
    required this.onTap,
    required this.onClose,
    required this.onCloseOthers,
    required this.onCloseLeft,
    required this.onCloseRight,
    required this.onCloseAll,
  });

  final TableDetailTab tab;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback onCloseOthers;
  final VoidCallback onCloseLeft;
  final VoidCallback onCloseRight;
  final VoidCallback onCloseAll;

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem<String>(
          value: 'closeCurrent',
          height: 36,
          child: LText('关闭'),
        ),
        PopupMenuItem<String>(
          value: 'closeOthers',
          height: 36,
          child: LText('关闭其它'),
        ),
        PopupMenuItem<String>(
          value: 'closeLeft',
          height: 36,
          child: LText('关闭左侧'),
        ),
        PopupMenuItem<String>(
          value: 'closeRight',
          height: 36,
          child: LText('关闭右侧'),
        ),
        PopupMenuItem<String>(
          value: 'closeAll',
          height: 36,
          child: LText('关闭全部'),
        ),
      ],
    );

    if (result == 'closeCurrent') {
      onClose();
    } else if (result == 'closeOthers') {
      onCloseOthers();
    } else if (result == 'closeLeft') {
      onCloseLeft();
    } else if (result == 'closeRight') {
      onCloseRight();
    } else if (result == 'closeAll') {
      onCloseAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = selected
        ? AppTheme.tabActiveFill(context)
        : AppTheme.tabInactiveFill(context);
    final textColor = selected
        ? AppTheme.tabActiveForeground(context)
        : AppTheme.tabInactiveForeground(context);

    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.tabRadiusOf(context),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: AppTheme.tabRadiusOf(context),
            color: backgroundColor,
          ),
          child: Container(
            decoration: selected ? AppTheme.tabIndicatorOf(context) : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      tab.displayCode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: onClose,
                    borderRadius: AppTheme.controlRadiusOf(context),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.close, size: 14, color: textColor),
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

class _WorkspaceContentSurface extends StatelessWidget {
  const _WorkspaceContentSurface({required this.child, this.backgroundColor});

  final Widget child;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('workspace-content-surface'),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTheme.surfaceOf(context),
      ),
      child: child,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppTheme.badgeRadiusOf(context),
        color: AppTheme.badgeFill(context),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: LText(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppTheme.badgeForeground(context),
          ),
        ),
      ),
    );
  }
}

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

String _buildDetailSummary({
  required TableDetailTab tab,
  required bool isGlobal,
}) {
  final parts = <String>[
    tab.displayCode,
    tab.displayTableLabel,
    tab.sourcePdm,
    if (isGlobal) tab.projectName,
  ];
  return parts.join(' | ');
}

String _displayFieldCellValue(TableDetailColumn column, int columnIndex) {
  switch (columnIndex) {
    case 0:
      return column.isPrimaryKey ? '主键' : '-';
    case 1:
      return column.code.trim().isEmpty ? '-' : column.code.trim();
    case 2:
      return column.name.trim().isEmpty ? '-' : column.name.trim();
    case 3:
      return column.dataType.trim().isEmpty ? '-' : column.dataType.trim();
    case 4:
      return column.length.trim().isEmpty ? '-' : column.length.trim();
    case 5:
      return column.precision.trim().isEmpty ? '-' : column.precision.trim();
    case 6:
      return column.nullable ? '是' : '';
    case 7:
      return column.defaultValue.trim().isEmpty
          ? '-'
          : column.defaultValue.trim();
    case 8:
      return column.comment.trim().isEmpty ? '-' : column.comment.trim();
    default:
      return '-';
  }
}

class _WorkspaceEmptyState extends StatelessWidget {
  const _WorkspaceEmptyState();

  @override
  Widget build(BuildContext context) {
    return _WorkspaceContentSurface(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.dashboard_customize_outlined,
                size: 48,
                color: AppTheme.primaryOf(context),
              ),
              const SizedBox(height: 12),
              LText('请选择一张表', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              LText(
                '从首页选择一张表后，会在新页签中打开该表的字段详情。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AppTheme.primaryOf(context)),
            const SizedBox(height: 10),
            LText(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            LText(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
