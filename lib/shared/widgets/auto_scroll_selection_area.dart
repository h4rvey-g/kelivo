import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// A [SelectionArea] that can auto-scroll the nearest enclosing vertical
/// [Scrollable] while a selection edge is dragged beyond its viewport.
///
/// Flutter normally installs this coordination when the selection area wraps
/// the scroll view. Chat messages use the inverse hierarchy, so this selection
/// container forwards the pending edge update while the ancestor scrolls.
class AutoScrollSelectionArea extends StatelessWidget {
  const AutoScrollSelectionArea({
    super.key,
    this.selectionAreaKey,
    this.focusNode,
    this.selectionControls,
    this.contextMenuBuilder = _defaultContextMenuBuilder,
    this.magnifierConfiguration,
    this.onSelectionChanged,
    required this.child,
  });

  /// Forwarded to the underlying [SelectionArea].
  final Key? selectionAreaKey;
  final FocusNode? focusNode;
  final TextSelectionControls? selectionControls;
  final SelectableRegionContextMenuBuilder contextMenuBuilder;
  final TextMagnifierConfiguration? magnifierConfiguration;
  final ValueChanged<SelectedContent?>? onSelectionChanged;
  final Widget child;

  static Widget _defaultContextMenuBuilder(
    BuildContext context,
    SelectableRegionState selectableRegionState,
  ) {
    return AdaptiveTextSelectionToolbar.selectableRegion(
      selectableRegionState: selectableRegionState,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      key: selectionAreaKey,
      focusNode: focusNode,
      selectionControls: selectionControls,
      contextMenuBuilder: contextMenuBuilder,
      magnifierConfiguration: magnifierConfiguration,
      onSelectionChanged: onSelectionChanged,
      child: _AutoScrollSelectionContainer(child: child),
    );
  }
}

class _AutoScrollSelectionContainer extends StatefulWidget {
  const _AutoScrollSelectionContainer({required this.child});

  final Widget child;

  @override
  State<_AutoScrollSelectionContainer> createState() =>
      _AutoScrollSelectionContainerState();
}

class _AutoScrollSelectionContainerState
    extends State<_AutoScrollSelectionContainer> {
  late final _AutoScrollSelectionDelegate _delegate =
      _AutoScrollSelectionDelegate();
  ScrollableState? _scrollable;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
    _delegate.scrollable = _scrollable;
  }

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_scrollable == null) return widget.child;
    return SelectionContainer(delegate: _delegate, child: widget.child);
  }
}

class _AutoScrollSelectionDelegate extends StaticSelectionContainerDelegate {
  static const double _velocityScalar = 30;

  ScrollableState? _scrollable;
  ScrollPosition? _position;
  EdgeDraggingAutoScroller? _autoScroller;
  bool _layoutChangeScheduled = false;
  bool _disposed = false;

  set scrollable(ScrollableState? value) {
    final nextPosition = value?.position;
    if (identical(_scrollable, value) && identical(_position, nextPosition)) {
      return;
    }

    _autoScroller?.stopAutoScroll();
    _position?.removeListener(_scheduleLayoutChange);
    _scrollable = value;
    _position = nextPosition;
    _position?.addListener(_scheduleLayoutChange);
    _autoScroller = value == null
        ? null
        : EdgeDraggingAutoScroller(
            value,
            velocityScalar: _velocityScalar,
            onScrollViewScrolled: _scheduleLayoutChange,
          );
  }

  @override
  SelectionResult handleSelectionEdgeUpdate(SelectionEdgeUpdateEvent event) {
    final result = super.handleSelectionEdgeUpdate(event);
    final autoScroller = _autoScroller;
    if (result == SelectionResult.pending || autoScroller == null) {
      autoScroller?.stopAutoScroll();
      return result;
    }

    autoScroller.startAutoScrollIfNecessary(
      Rect.fromCenter(center: event.globalPosition, width: 0, height: 0),
    );
    return autoScroller.scrolling ? SelectionResult.pending : result;
  }

  @override
  SelectionResult handleClearSelection(ClearSelectionEvent event) {
    _autoScroller?.stopAutoScroll();
    return super.handleClearSelection(event);
  }

  void _scheduleLayoutChange() {
    if (_layoutChangeScheduled || _disposed) return;
    _layoutChangeScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      _layoutChangeScheduled = false;
      layoutDidChange();
    }, debugLabel: 'AutoScrollSelectionArea.layoutDidChange');
  }

  @override
  void dispose() {
    _disposed = true;
    _layoutChangeScheduled = false;
    _position?.removeListener(_scheduleLayoutChange);
    _autoScroller?.stopAutoScroll();
    _autoScroller = null;
    _position = null;
    _scrollable = null;
    super.dispose();
  }
}
