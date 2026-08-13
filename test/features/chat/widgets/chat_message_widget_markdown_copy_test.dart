import '../../../support/business_test_harness.dart';

import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'dart:ui' as ui;
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

  testWidgets(
    'assistant selection is exposed to macOS accessibility services',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final semantics = tester.ensureSemantics();
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

        final semanticsFinder = find.byWidgetPredicate(
          (widget) =>
              widget.key?.toString().contains(
                'assistant-selection-semantics',
              ) ??
              false,
        );
        final data = tester.getSemantics(semanticsFinder).getSemanticsData();
        expect(data.value, '•Alpha\n•Beta');
        expect(
          data.textSelection,
          const TextSelection(baseOffset: 0, extentOffset: 12),
        );
        expect(data.flagsCollection.isTextField, isTrue);
        expect(data.flagsCollection.isReadOnly, isTrue);
        expect(data.flagsCollection.isFocused, ui.Tristate.isTrue);
      } finally {
        semantics.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
