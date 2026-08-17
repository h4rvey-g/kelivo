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
import 'package:flutter/material.dart';
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
