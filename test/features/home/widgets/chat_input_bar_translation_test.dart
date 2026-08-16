import '../../../support/business_test_harness.dart';
import 'package:Kelivo/core/models/chat_input_data.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/home/widgets/chat_input_bar.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpInput(
    WidgetTester tester, {
    required SettingsProvider settings,
    required TextEditingController controller,
    required FocusNode focusNode,
  }) {
    return tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider(
            create: (_) =>
                AssistantProvider(preferences: createBusinessTestPreferences()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppSnackBarOverlay(
            child: Scaffold(
              body: ChatInputBar(
                controller: controller,
                focusNode: focusNode,
                onSend: (_) async => ChatInputSubmissionResult.rejected,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> typeThreeSpaces(WidgetTester tester, String source) async {
    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.enterText(field, '$source ');
    await tester.enterText(field, '$source  ');
    await tester.enterText(field, '$source   ');
    await tester.pump();
  }

  testWidgets('keeps three spaces when input translation is disabled', (
    tester,
  ) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
    await settings.setInputTranslationEnabled(false);
    final controller = TextEditingController(text: 'Hello');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await pumpInput(
      tester,
      settings: settings,
      controller: controller,
      focusNode: focusNode,
    );
    await typeThreeSpaces(tester, 'Hello');

    expect(controller.text, 'Hello   ');
  });

  testWidgets('removes the trigger and warns when no model is configured', (
    tester,
  ) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
    await settings.setInputTranslationEnabled(true);
    final controller = TextEditingController(text: 'Hello');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await pumpInput(
      tester,
      settings: settings,
      controller: controller,
      focusNode: focusNode,
    );
    await typeThreeSpaces(tester, 'Hello');

    expect(controller.text, 'Hello');
    expect(find.text('Please set a translation model first'), findsOneWidget);

    AppSnackBarManager().dismissAll();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
  });
}
