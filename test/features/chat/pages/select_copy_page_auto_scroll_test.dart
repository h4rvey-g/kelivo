import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/desktop/select_copy_dialog.dart';
import 'package:Kelivo/features/chat/pages/select_copy_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/auto_scroll_selection_area.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final longContent = List<String>.generate(
    60,
    (index) =>
        'Line ${index.toString().padLeft(3, '0')}: '
        'Selectable content used to exercise edge scrolling.',
  ).join('\n');
  final message = ChatMessage(
    id: 'message-1',
    role: 'assistant',
    content: longContent,
    conversationId: 'conversation-1',
  );

  testWidgets('dragging a selection below the viewport scrolls down', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final position = await _pumpPage(tester, message);

      final scrollable = find.byType(Scrollable).first;
      final viewport = tester.getRect(scrollable);
      final text = tester.getRect(find.text(longContent));
      final start = Offset(text.left + 24, viewport.top + 48);

      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await gesture.moveBy(const Offset(0, 24));
      await tester.pump();
      await gesture.moveTo(Offset(start.dx, viewport.bottom + 60));
      await _pumpAutoScroll(tester);

      expect(position.pixels, greaterThan(0));
      await gesture.up();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('dragging a selection above the viewport scrolls up', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final position = await _pumpPage(tester, message);

      final scrollable = find.byType(Scrollable).first;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();

      final viewport = tester.getRect(scrollable);
      final text = tester.getRect(find.text(longContent));
      final start = Offset(text.left + 24, viewport.bottom - 48);
      final initialOffset = position.pixels;

      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await gesture.moveBy(const Offset(0, -24));
      await tester.pump();
      await gesture.moveTo(Offset(start.dx, viewport.top - 60));
      await _pumpAutoScroll(tester);

      expect(position.pixels, lessThan(initialOffset));
      await gesture.up();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('auto-scroll keeps extending the selection', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final controller = ScrollController();
    SelectedContent? selection;
    addTearDown(controller.dispose);

    try {
      tester.view.physicalSize = const Size(480, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: controller,
              child: AutoScrollSelectionArea(
                onSelectionChanged: (value) => selection = value,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    longContent,
                    style: const TextStyle(fontSize: 15, height: 1.5),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final viewport = tester.getRect(scrollable);
      final text = tester.getRect(find.text(longContent));
      final start = Offset(text.left + 24, viewport.top + 48);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await gesture.moveBy(const Offset(0, 24));
      await tester.pump();
      await gesture.moveTo(Offset(start.dx, viewport.bottom + 60));
      await tester.pump(const Duration(milliseconds: 40));
      final selectionLengthBeforeScroll = selection?.plainText.length ?? 0;

      await _pumpAutoScroll(tester);
      await gesture.up();
      await tester.pump();

      expect(controller.offset, greaterThan(0));
      expect(selectionLengthBeforeScroll, greaterThan(0));
      expect(
        selection?.plainText.length ?? 0,
        greaterThan(selectionLengthBeforeScroll),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop select-copy dialog auto-scrolls its own viewport', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      tester.view.physicalSize = const Size(720, 680);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showSelectCopyDesktopDialog(context, message: message),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final dialog = find.byType(Dialog);
      final scrollable = find.descendant(
        of: dialog,
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      final viewport = tester.getRect(scrollable);
      final text = tester.getRect(find.text(longContent));
      final start = Offset(text.left + 24, viewport.top + 48);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await gesture.moveBy(const Offset(0, 24));
      await tester.pump();
      await gesture.moveTo(Offset(start.dx, viewport.bottom + 60));
      await _pumpAutoScroll(tester);

      expect(position.pixels, greaterThan(0));
      await gesture.up();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<ScrollPosition> _pumpPage(
  WidgetTester tester,
  ChatMessage message,
) async {
  tester.view.physicalSize = const Size(480, 420);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SelectCopyPage(message: message),
    ),
  );
  await tester.pumpAndSettle();
  return tester.state<ScrollableState>(find.byType(Scrollable).first).position;
}

Future<void> _pumpAutoScroll(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}
