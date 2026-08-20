import '../../../support/business_test_harness.dart';

import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/features/home/controllers/scroll_controller.dart'
    as scroll_ctrl;
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/widgets/message_list_view.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/auto_scroll_selection_area.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('dragging a message selection beyond the viewport scrolls down', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final scrollController = scroll_ctrl.ChatAutoFollowScrollController();
    final listController = ListController();
    final isProcessingFiles = ValueNotifier<bool>(false);
    final settings = SettingsProvider(createBusinessTestPreferences());
    final assistant = AssistantProvider(
      preferences: createBusinessTestPreferences(),
    );
    final tts = TtsProvider(preferences: createBusinessTestPreferences());
    final user = UserProvider(preferences: createBusinessTestPreferences());
    final askUser = AskUserInteractionService();
    final toolApproval = ToolApprovalService();
    final content = List<String>.generate(
      90,
      (index) => 'Selectable timeline line $index for edge scrolling.',
    ).join('\n');

    addTearDown(scrollController.dispose);
    addTearDown(listController.dispose);
    addTearDown(isProcessingFiles.dispose);
    addTearDown(settings.dispose);
    addTearDown(assistant.dispose);
    addTearDown(tts.dispose);
    addTearDown(user.dispose);
    addTearDown(askUser.dispose);
    addTearDown(toolApproval.dispose);

    try {
      await settings.setEnableAssistantMarkdown(false);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: assistant),
            ChangeNotifierProvider.value(value: tts),
            ChangeNotifierProvider.value(value: user),
            ChangeNotifierProvider.value(value: askUser),
            ChangeNotifierProvider.value(value: toolApproval),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MessageListView(
                scrollController: scrollController,
                listController: listController,
                messages: [
                  ChatMessage(
                    id: 'selection-message',
                    role: 'assistant',
                    content: content,
                    conversationId: 'conversation-1',
                  ),
                ],
                byGroup: const {},
                versionSelections: const {},
                reasoning: const {},
                reasoningSegments: const {},
                contentSplits: const {},
                toolParts: const {},
                translations: const {},
                selecting: false,
                selectedItems: const {},
                dividerPadding: EdgeInsets.zero,
                isProcessingFiles: isProcessingFiles,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final viewport = tester.getRect(find.byType(SuperListView));
      final textFinder = find.text(content);
      final selectionArea = find.ancestor(
        of: textFinder,
        matching: find.byType(AutoScrollSelectionArea),
      );
      expect(scrollController.position.maxScrollExtent, greaterThan(0));
      expect(selectionArea, findsOneWidget);
      expect(
        Scrollable.maybeOf(tester.element(selectionArea), axis: Axis.vertical),
        isNotNull,
      );

      final text = tester.getRect(textFinder);
      final visibleText = text.intersect(viewport);
      expect(visibleText.isEmpty, isFalse);
      final start = Offset(visibleText.left + 24, visibleText.top + 24);
      expect(text.contains(start), isTrue);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await gesture.moveBy(const Offset(0, 24));
      await tester.pump();
      await gesture.moveTo(Offset(start.dx, viewport.bottom + 60));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      expect(scrollController.offset, greaterThan(0));
      await gesture.up();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('right click keeps an assistant markdown selection', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final scrollController = scroll_ctrl.ChatAutoFollowScrollController();
    final listController = ListController();
    final isProcessingFiles = ValueNotifier<bool>(false);
    final settings = SettingsProvider(createBusinessTestPreferences());
    final assistant = AssistantProvider(
      preferences: createBusinessTestPreferences(),
    );
    final tts = TtsProvider(preferences: createBusinessTestPreferences());
    final user = UserProvider(preferences: createBusinessTestPreferences());
    final askUser = AskUserInteractionService();
    final toolApproval = ToolApprovalService();
    const selectedLine =
        'Permanent Neurologic Sequelae (Persistent vegetative state, '
        'spastic quadriparesis, cranial nerve palsies).';
    const content = '''
## Complications

- **Brainstem Death** (Loss of all brainstem reflexes, fixed/dilated pupils, apnea).
- **Duret Hemorrhages** (Fatal secondary midbrain and pontine tegmentum hemorrhage).
- **Secondary Cerebral Infarction** (PCA territory stroke leading to permanent cortical blindness).
- **Permanent Neurologic Sequelae** (Persistent vegetative state, spastic quadriparesis, cranial nerve palsies).
- **Neuroendocrine Dysregulation:**
  - Central Diabetes Insipidus (DI) secondary to pituitary stalk shear.
''';

    addTearDown(scrollController.dispose);
    addTearDown(listController.dispose);
    addTearDown(isProcessingFiles.dispose);
    addTearDown(settings.dispose);
    addTearDown(assistant.dispose);
    addTearDown(tts.dispose);
    addTearDown(user.dispose);
    addTearDown(askUser.dispose);
    addTearDown(toolApproval.dispose);

    try {
      await settings.setEnableAssistantMarkdown(true);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: assistant),
            ChangeNotifierProvider.value(value: tts),
            ChangeNotifierProvider.value(value: user),
            ChangeNotifierProvider.value(value: askUser),
            ChangeNotifierProvider.value(value: toolApproval),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MessageListView(
                scrollController: scrollController,
                listController: listController,
                messages: [
                  ChatMessage(
                    id: 'right-click-selection-message',
                    role: 'assistant',
                    content: content,
                    conversationId: 'conversation-1',
                  ),
                ],
                byGroup: const {},
                versionSelections: const {},
                reasoning: const {},
                reasoningSegments: const {},
                contentSplits: const {},
                toolParts: const {},
                translations: const {},
                selecting: false,
                selectedItems: const {},
                dividerPadding: EdgeInsets.zero,
                isProcessingFiles: isProcessingFiles,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final areaFinder = find.byType(SelectionArea);
      final paragraph = tester
          .renderObjectList<RenderParagraph>(
            find.descendant(of: areaFinder, matching: find.byType(RichText)),
          )
          .singleWhere(
            (value) => value.text.toPlainText().contains(selectedLine),
          );
      final paragraphText = paragraph.text.toPlainText();
      final selectionStart = paragraphText.indexOf('Permanent');
      final selectionEnd = paragraphText.indexOf('vegetative') + 1;
      final rightClickOffset = paragraphText.indexOf('Neurologic') + 3;
      final selectionGesture = await tester.startGesture(
        _textOffsetToPosition(paragraph, selectionStart),
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(selectionGesture.removePointer);
      await tester.pump();
      await selectionGesture.moveTo(
        _textOffsetToPosition(paragraph, selectionEnd),
      );
      await tester.pump();
      await selectionGesture.up();
      await tester.pumpAndSettle();

      final selectionBeforeRightClick = List<TextSelection>.of(
        paragraph.selections,
      );
      expect(selectionBeforeRightClick, isNotEmpty);
      final timelineFocusNode = tester
          .widget<Focus>(
            find.byKey(const ValueKey('timeline-keyboard-scroll-region')),
          )
          .focusNode!;
      expect(timelineFocusNode.hasPrimaryFocus, isFalse);

      final rightClick = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      addTearDown(rightClick.removePointer);
      await rightClick.down(_textOffsetToPosition(paragraph, rightClickOffset));
      await tester.pump();

      expect(paragraph.selections, selectionBeforeRightClick);
      expect(timelineFocusNode.hasPrimaryFocus, isFalse);
      expect(
        tester
            .state<SelectionAreaState>(areaFinder)
            .selectableRegion
            .selectionOverlay,
        isNotNull,
      );
      await rightClick.up();
      await tester.pump();

      final listBounds = tester.getRect(find.byType(SuperListView));
      final primaryClick = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      addTearDown(primaryClick.removePointer);
      await primaryClick.down(listBounds.topLeft + const Offset(4, 4));
      await tester.pump();

      expect(timelineFocusNode.hasPrimaryFocus, isTrue);
      await primaryClick.up();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Offset _textOffsetToPosition(RenderParagraph paragraph, int offset) {
  const caret = Rect.fromLTWH(0, 0, 2, 20);
  final localOffset =
      paragraph.getOffsetForCaret(TextPosition(offset: offset), caret) +
      Offset(0, paragraph.preferredLineHeight - 2);
  return paragraph.localToGlobal(localOffset);
}
