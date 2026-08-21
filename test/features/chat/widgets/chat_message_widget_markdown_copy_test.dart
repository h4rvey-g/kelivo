import '../../../support/business_test_harness.dart';

import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/core/services/macos_selected_text_accessibility.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _buildHarness(Widget child) {
  SharedPreferences.setMockInitialValues(const {});
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(createBusinessTestPreferences()),
      ),
      ChangeNotifierProvider(
        create: (_) =>
            TtsProvider(preferences: createBusinessTestPreferences()),
      ),
      ChangeNotifierProvider(
        create: (_) =>
            UserProvider(preferences: createBusinessTestPreferences()),
      ),
      ChangeNotifierProvider(create: (_) => ToolApprovalService()),
      ChangeNotifierProvider(create: (_) => AskUserInteractionService()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

Offset _textOffsetToPosition(RenderParagraph paragraph, int offset) {
  const caret = Rect.fromLTWH(0, 0, 2, 20);
  final localOffset =
      paragraph.getOffsetForCaret(TextPosition(offset: offset), caret) +
      Offset(0, paragraph.preferredLineHeight - 2);
  return paragraph.localToGlobal(localOffset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'assistant selection copies exact rendered text through Copy intent',
    (tester) async {
      MethodCall? clipboardCall;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboardCall = call;
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      const markdown = '- **Alpha**\n* Beta';
      await tester.pumpWidget(
        _buildHarness(
          ChatMessageWidget(
            message: ChatMessage(
              id: 'markdown-copy',
              role: 'assistant',
              content: markdown,
              conversationId: 'conversation-1',
            ),
            showModelIcon: false,
          ),
        ),
      );
      await tester.pump();

      final areaFinder = find.byType(SelectionArea);
      expect(areaFinder, findsOneWidget);
      final areaState = tester.state<SelectionAreaState>(areaFinder);
      areaState.selectableRegion.selectAll(SelectionChangedCause.keyboard);
      await tester.pump();

      final selectableChild = find.descendant(
        of: areaFinder,
        matching: find.byType(RichText),
      );
      expect(selectableChild, findsWidgets);
      Actions.invoke(
        tester.element(selectableChild.first),
        CopySelectionTextIntent.copy,
      );
      await tester.pump();

      expect(clipboardCall?.method, 'Clipboard.setData');
      expect(clipboardCall?.arguments, <String, dynamic>{
        'text': '•Alpha\n•Beta',
      });
    },
  );

  testWidgets('assistant table cell drag selection copies with keyboard', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    MethodCall? clipboardCall;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboardCall = call;
      return null;
    });

    try {
      const markdown = '''
| Name | Value |
| --- | --- |
| Alpha | 42 |
''';
      await tester.pumpWidget(
        _buildHarness(
          ChatMessageWidget(
            message: ChatMessage(
              id: 'markdown-table-cell-copy',
              role: 'assistant',
              content: markdown,
              conversationId: 'conversation-1',
            ),
            showModelIcon: false,
          ),
        ),
      );
      await tester.pump();

      final alphaCell = find.byWidgetPredicate(
        (widget) =>
            (widget is SelectableText &&
                (widget.data == 'Alpha' ||
                    widget.textSpan?.toPlainText() == 'Alpha')) ||
            (widget is Text && widget.textSpan?.toPlainText() == 'Alpha'),
      );
      expect(alphaCell, findsOneWidget);
      final cellRect = tester.getRect(alphaCell);
      final gesture = await tester.startGesture(
        cellRect.centerLeft + const Offset(1, 0),
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      addTearDown(gesture.removePointer);
      await gesture.moveTo(cellRect.centerRight - const Offset(1, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(clipboardCall?.method, 'Clipboard.setData');
      expect((clipboardCall?.arguments as Map?)?['text'], 'Alpha');
    } finally {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('user selection copies exact rendered text through Copy intent', (
    tester,
  ) async {
    MethodCall? clipboardCall;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboardCall = call;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    const markdown = '- **Alpha**\n* Beta';
    await tester.pumpWidget(
      _buildHarness(
        ChatMessageWidget(
          message: ChatMessage(
            id: 'user-markdown-copy',
            role: 'user',
            content: markdown,
            conversationId: 'conversation-1',
          ),
          showUserAvatar: false,
        ),
      ),
    );
    await tester.pump();

    final areaFinder = find.byType(SelectionArea);
    expect(areaFinder, findsOneWidget);
    final areaState = tester.state<SelectionAreaState>(areaFinder);
    areaState.selectableRegion.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();

    final selectableChild = find.descendant(
      of: areaFinder,
      matching: find.byType(RichText),
    );
    expect(selectableChild, findsWidgets);
    Actions.invoke(
      tester.element(selectableChild.first),
      CopySelectionTextIntent.copy,
    );
    await tester.pump();

    expect(clipboardCall?.method, 'Clipboard.setData');
    expect(clipboardCall?.arguments, <String, dynamic>{
      'text': '•Alpha\n•Beta',
    });
  });

  testWidgets('right click follows native macOS selection behavior', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    MethodCall? clipboardCall;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboardCall = call;
      return null;
    });

    try {
      const content = 'Alpha **Beta** Gamma';
      await tester.pumpWidget(
        _buildHarness(
          SingleChildScrollView(
            child: ChatMessageWidget(
              message: ChatMessage(
                id: 'desktop-right-click-selection',
                role: 'assistant',
                content: content,
                conversationId: 'conversation-1',
              ),
              showModelIcon: false,
            ),
          ),
        ),
      );
      await tester.pump();

      final areaFinder = find.byType(SelectionArea);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: areaFinder, matching: find.byType(RichText)).first,
      );
      final selectionGesture = await tester.startGesture(
        _textOffsetToPosition(paragraph, 0),
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(selectionGesture.removePointer);
      await tester.pump();
      final selectionEnd = _textOffsetToPosition(paragraph, 8);
      await selectionGesture.moveTo(selectionEnd);
      await tester.pump();
      await selectionGesture.up();
      await tester.pumpAndSettle();

      final selectionBeforeRightClick = List<TextSelection>.of(
        paragraph.selections,
      );
      expect(selectionBeforeRightClick, isNotEmpty);

      final insideRightClick = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      addTearDown(insideRightClick.removePointer);
      await insideRightClick.down(_textOffsetToPosition(paragraph, 6));
      await insideRightClick.up();
      await tester.pump();

      expect(paragraph.selections, selectionBeforeRightClick);

      final selectableChild = find.descendant(
        of: areaFinder,
        matching: find.byType(RichText),
      );
      Actions.invoke(
        tester.element(selectableChild.first),
        CopySelectionTextIntent.copy,
      );
      await tester.pump();
      final selectedBeforeRightClick = Map<String, dynamic>.from(
        clipboardCall!.arguments as Map,
      );
      expect(selectedBeforeRightClick['text'], isNot('Beta'));
      clipboardCall = null;

      final outsideRightClick = await tester.startGesture(
        _textOffsetToPosition(paragraph, 12),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      addTearDown(outsideRightClick.removePointer);
      await tester.pump();
      await outsideRightClick.up();
      await tester.pump();

      Actions.invoke(
        tester.element(selectableChild.first),
        CopySelectionTextIntent.copy,
      );
      await tester.pump();

      expect(clipboardCall?.method, 'Clipboard.setData');
      expect(clipboardCall?.arguments, <String, dynamic>{'text': 'Gamma'});
    } finally {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('user long press selects text on mobile', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    MethodCall? clipboardCall;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboardCall = call;
      return null;
    });

    try {
      const content = 'Selectable user text';
      await tester.pumpWidget(
        _buildHarness(
          ChatMessageWidget(
            message: ChatMessage(
              id: 'user-touch-selection',
              role: 'user',
              content: content,
              conversationId: 'conversation-1',
            ),
            showUserAvatar: false,
          ),
        ),
      );
      await tester.pump();

      final areaFinder = find.byType(SelectionArea);
      expect(areaFinder, findsOneWidget);
      await tester.longPress(find.text(content));
      await tester.pump();

      final selectableChild = find.descendant(
        of: areaFinder,
        matching: find.byType(RichText),
      );
      Actions.invoke(
        tester.element(selectableChild.first),
        CopySelectionTextIntent.copy,
      );
      await tester.pump();

      expect(clipboardCall?.method, 'Clipboard.setData');
      final copiedText = (clipboardCall?.arguments as Map?)?['text'] as String?;
      expect(copiedText, isNotNull);
      expect(copiedText, isNotEmpty);
      expect(content, contains(copiedText!));
    } finally {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'assistant selection is published and cleared for macOS accessibility',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final accessibilityCalls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const accessibilityChannel = MethodChannel(
        MacOSSelectedTextAccessibilityBridge.channelName,
      );
      messenger.setMockMethodCallHandler(accessibilityChannel, (call) async {
        accessibilityCalls.add(call);
        return null;
      });
      try {
        const markdown = '- **Alpha**\n* Beta';
        await tester.pumpWidget(
          _buildHarness(
            ChatMessageWidget(
              message: ChatMessage(
                id: 'macos-accessible-selection',
                role: 'assistant',
                content: markdown,
                conversationId: 'conversation-1',
              ),
              showModelIcon: false,
            ),
          ),
        );
        await tester.pump();

        final areaState = tester.state<SelectionAreaState>(
          find.byType(SelectionArea),
        );
        areaState.selectableRegion.selectAll(SelectionChangedCause.keyboard);
        await tester.pump();

        expect(accessibilityCalls, isNotEmpty);
        expect(
          accessibilityCalls.last.method,
          MacOSSelectedTextAccessibilityBridge.methodName,
        );
        final selectionArguments = Map<String, Object?>.from(
          accessibilityCalls.last.arguments as Map,
        );
        expect(selectionArguments['source'], isA<String>());
        expect(selectionArguments['source'], isNotEmpty);
        expect(selectionArguments['text'], '•Alpha\n•Beta');
        final bounds = Map<String, Object?>.from(
          selectionArguments['bounds']! as Map,
        );
        expect((bounds['width']! as num).toDouble(), greaterThan(0));
        expect((bounds['height']! as num).toDouble(), greaterThan(0));
        expect((bounds['x']! as num).toDouble().isFinite, isTrue);
        expect((bounds['y']! as num).toDouble().isFinite, isTrue);

        await tester.pumpWidget(
          _buildHarness(
            ChatMessageWidget(
              message: ChatMessage(
                id: 'macos-accessible-selection-replacement',
                role: 'assistant',
                content: markdown,
                conversationId: 'conversation-1',
              ),
              showModelIcon: false,
            ),
          ),
        );
        await tester.pump();
        expect(accessibilityCalls.last.arguments, <String, Object?>{
          'source': selectionArguments['source'],
          'text': '',
        });

        final replacementAreaState = tester.state<SelectionAreaState>(
          find.byType(SelectionArea),
        );
        replacementAreaState.selectableRegion.selectAll(
          SelectionChangedCause.keyboard,
        );
        await tester.pump();
        final replacementArguments = Map<String, Object?>.from(
          accessibilityCalls.last.arguments as Map,
        );
        expect(replacementArguments['text'], '•Alpha\n•Beta');
        expect(
          replacementArguments['source'],
          isNot(selectionArguments['source']),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(accessibilityCalls.last.arguments, <String, Object?>{
          'source': replacementArguments['source'],
          'text': '',
        });
      } finally {
        messenger.setMockMethodCallHandler(accessibilityChannel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
