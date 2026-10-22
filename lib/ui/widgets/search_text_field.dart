import 'dart:async';

import 'package:flutter/material.dart';
import '../../app/l10n/app_strings.dart';
import 'package:flutter/services.dart';

/// Gives text editing priority over the surrounding table's keyboard shortcuts.
class SearchTextField extends StatefulWidget {
  const SearchTextField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.focusNode,
    this.onSubmitted,
    this.decoration = const InputDecoration(),
    this.style,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final InputDecoration decoration;
  final TextStyle? style;

  @override
  State<SearchTextField> createState() => _SearchTextFieldState();
}

class _SearchTextFieldState extends State<SearchTextField> {
  final FocusNode _internalFocusNode = FocusNode();

  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode;

  @override
  void dispose() {
    _internalFocusNode.dispose();
    super.dispose();
  }

  void _selectAll() {
    widget.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.controller.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            _selectAll,
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): _selectAll,
      },
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) => TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          maxLines: 1,
          style: widget.style,
          decoration: widget.decoration.copyWith(
            suffixIconConstraints: const BoxConstraints.tightFor(
              width: 30,
              height: 30,
            ),
            suffixIcon: value.text.isEmpty
                ? const SizedBox(width: 30)
                : IconButton(
                    tooltip: context.tr('清空搜索'),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      widget.controller.clear();
                      widget.onChanged('');
                      _focusNode.requestFocus();
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

/// Avoids flashing for fast queries, and keeps slow-query feedback visible.
class SearchActivityIndicator extends StatefulWidget {
  const SearchActivityIndicator({super.key, required this.searching});

  final bool searching;

  @override
  State<SearchActivityIndicator> createState() =>
      _SearchActivityIndicatorState();
}

class _SearchActivityIndicatorState extends State<SearchActivityIndicator> {
  Timer? _timer;
  DateTime? _shownAt;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(covariant SearchActivityIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searching != widget.searching) _update();
  }

  void _update() {
    _timer?.cancel();
    if (widget.searching) {
      if (_visible) return;
      _timer = Timer(const Duration(milliseconds: 200), () {
        setState(() {
          _visible = true;
          _shownAt = DateTime.now();
        });
      });
    } else if (_visible) {
      final elapsed = DateTime.now().difference(_shownAt!);
      final remaining = const Duration(milliseconds: 300) - elapsed;
      _timer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
        setState(() => _visible = false);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _visible
      ? Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              semanticsLabel: context.tr('正在搜索'),
            ),
          ),
        )
      : const Icon(Icons.search, size: 18);
}
