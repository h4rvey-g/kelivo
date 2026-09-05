import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/retry_policy.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/home/services/translation_service.dart';
import 'package:Kelivo/features/settings/widgets/language_select_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('one-tap translation bypasses the language selector', (
    tester,
  ) async {
    final preferences = createBusinessTestPreferences();
    final settings = SettingsProvider(preferences);
    final assistants = AssistantProvider(preferences: preferences);
    addTearDown(settings.dispose);
    addTearDown(assistants.dispose);
    await Future.wait([settings.loaded, assistants.loaded]);
    await settings.setTranslateTargetLang('ja');
    await settings.setOneTapMessageTranslationTargetLang('fr');
    await settings.setOneTapMessageTranslationEnabled(true);

    late BuildContext serviceContext;
    await tester.pumpWidget(
      _TestApp(
        settings: settings,
        assistants: assistants,
        onContext: (context) => serviceContext = context,
      ),
    );
    await tester.pumpAndSettle();

    var selectorCalls = 0;
    String? resolvedPreferredCode;
    final service = TranslationService(
      chatService: ChatService(),
      getContext: () => serviceContext,
      languageSelector: (_) async {
        selectorCalls++;
        return supportedLanguages.first;
      },
      languageResolver: (locale, {preferredCode}) {
        resolvedPreferredCode = preferredCode;
        return defaultTranslationLanguage(locale, preferredCode: preferredCode);
      },
    );

    final result = await service.translateMessage(
      message: _message,
      onTranslationStarted: () {},
      onTranslationUpdate: (_) {},
      onTranslationCleared: () {},
    );

    expect(result.type, TranslationResultType.noModelConfigured);
    expect(selectorCalls, 0);
    expect(resolvedPreferredCode, 'fr');
  });

  testWidgets('standard translation still opens the language selector', (
    tester,
  ) async {
    final preferences = createBusinessTestPreferences();
    final settings = SettingsProvider(preferences);
    final assistants = AssistantProvider(preferences: preferences);
    addTearDown(settings.dispose);
    addTearDown(assistants.dispose);
    await Future.wait([settings.loaded, assistants.loaded]);

    late BuildContext serviceContext;
    await tester.pumpWidget(
      _TestApp(
        settings: settings,
        assistants: assistants,
        onContext: (context) => serviceContext = context,
      ),
    );
    await tester.pumpAndSettle();

    var selectorCalls = 0;
    final service = TranslationService(
      chatService: ChatService(),
      getContext: () => serviceContext,
      languageSelector: (_) async {
        selectorCalls++;
        return null;
      },
    );

    final result = await service.translateMessage(
      message: _message,
      onTranslationStarted: () {},
      onTranslationUpdate: (_) {},
      onTranslationCleared: () {},
    );

    expect(result.type, TranslationResultType.cancelled);
    expect(selectorCalls, 1);
  });

  test('replaced translation run does not own side effects', () {
    final oldRun = Object();
    final newRun = Object();
    expect(translationRunIsCurrent(oldRun, newRun), isFalse);
    expect(
      shouldApplyTranslationFailure(
        runToken: oldRun,
        currentToken: newRun,
        error: Exception('HTTP 429: busy'),
      ),
      isFalse,
    );
  });

  test('cancelled translation does not clear the newer result', () {
    final run = Object();
    expect(
      shouldApplyTranslationFailure(
        runToken: run,
        currentToken: run,
        error: http.ClientException('cancelled'),
      ),
      isFalse,
    );
    expect(
      shouldApplyTranslationFailure(
        runToken: run,
        currentToken: run,
        error: Exception('HTTP 500: oops'),
      ),
      isTrue,
    );
    expect(isUserCancelError(http.ClientException('cancelled')), isTrue);
  });

  test('clear supersedes the old run so it cannot write translation back', () {
    final runs = <String, Object>{};
    final oldRun = Object();
    runs['m1'] = oldRun;
    final clearToken = supersedeTranslationRun(runs, 'm1');
    expect(translationRequestId('m1'), 'translate-msg-m1');
    expect(identical(runs['m1'], clearToken), isTrue);
    expect(translationRunIsCurrent(oldRun, runs['m1']), isFalse);
    expect(
      shouldApplyTranslationFailure(
        runToken: oldRun,
        currentToken: runs['m1'],
        error: Exception('HTTP 429: busy'),
      ),
      isFalse,
    );
  });
}

final _message = ChatMessage(
  role: 'assistant',
  content: 'Hello',
  conversationId: 'conversation',
);

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.settings,
    required this.assistants,
    required this.onContext,
  });

  final SettingsProvider settings;
  final AssistantProvider assistants;
  final ValueChanged<BuildContext> onContext;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<AssistantProvider>.value(value: assistants),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            onContext(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
