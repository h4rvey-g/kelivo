import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/home/widgets/chat_input_bar.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('model shortcut buttons separate taps from long presses', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final taps = <int>[];
    final longPresses = <int>[];

    await tester.pumpWidget(
      MultiProvider(
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ChatInputBar(
              modelShortcuts: const [
                ChatModelShortcutData(slot: 1),
                ChatModelShortcutData(slot: 2),
              ],
              onSelectModel: taps.add,
              onLongPressModel: longPresses.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Model 1'), findsOneWidget);
    expect(find.text('Model 2'), findsOneWidget);

    await tester.tap(find.text('Model 1'));
    await tester.pump();
    await tester.longPress(find.text('Model 1'));
    await tester.pump();
    await tester.tap(find.text('Model 2'));
    await tester.pump();
    await tester.longPress(find.text('Model 2'));
    await tester.pump();

    expect(taps, [1, 2]);
    expect(longPresses, [1, 2]);
  });

  testWidgets('renders and handles five model shortcut slots', (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final taps = <int>[];
    final longPresses = <int>[];

    await tester.pumpWidget(
      MultiProvider(
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ChatInputBar(
              modelShortcuts: const [
                ChatModelShortcutData(slot: 1),
                ChatModelShortcutData(slot: 2),
                ChatModelShortcutData(slot: 3),
                ChatModelShortcutData(slot: 4),
                ChatModelShortcutData(slot: 5),
              ],
              onSelectModel: taps.add,
              onLongPressModel: longPresses.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var slot = 1; slot <= 5; slot++) {
      expect(find.text('Model $slot'), findsOneWidget);
    }

    await tester.tap(find.text('Model 5'));
    await tester.pump();
    await tester.longPress(find.text('Model 5'));
    await tester.pump();

    expect(taps, [5]);
    expect(longPresses, [5]);

    taps.clear();
    longPresses.clear();
    tester.view.physicalSize = const Size(320, 600);
    await tester.pumpAndSettle();

    expect(find.text('Model 5'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('chat-input-left-actions-overflow')),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Model 5'));
    await tester.pumpAndSettle();

    expect(taps, isEmpty);
    expect(longPresses, [5]);
  });
}
