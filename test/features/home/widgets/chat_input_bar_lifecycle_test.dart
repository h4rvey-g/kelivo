import '../../../support/business_test_harness.dart';
import 'package:Kelivo/core/models/chat_input_data.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/home/widgets/chat_input_bar.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildHarness({
    required TextEditingController controller,
    required FocusNode focusNode,
    GlobalKey<NavigatorState>? navigatorKey,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              AssistantProvider(preferences: createBusinessTestPreferences()),
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            onSend: (_) async => ChatInputSubmissionResult.rejected,
          ),
        ),
      ),
    );
  }

  testWidgets('桌面应用失活期间保留对话输入焦点以支持外部听写', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();

    await tester.pumpWidget(
      buildHarness(controller: controller, focusNode: focusNode),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('对话页被其他路由覆盖时恢复前台不抢焦点', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      buildHarness(
        controller: controller,
        focusNode: focusNode,
        navigatorKey: navigatorKey,
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other page')),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(focusNode.hasFocus, isFalse);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    focusNode.dispose();
  });
}
