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
                ChatModelShortcutData(
                  slot: 1,
                  icon: Icon(Icons.filter_1, key: ValueKey('model-icon-1')),
                ),
                ChatModelShortcutData(
                  slot: 2,
                  icon: Icon(Icons.filter_2, key: ValueKey('model-icon-2')),
                ),
              ],
              onSelectModel: taps.add,
              onLongPressModel: longPresses.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Model 1'), findsNothing);
    expect(find.text('Model 2'), findsNothing);
    expect(find.byKey(const ValueKey('model-icon-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('model-icon-2')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('chat-model-shortcut-group'))),
      const Size(64, 32),
    );

    await tester.tap(find.byKey(const ValueKey('chat-model-shortcut-1')));
    await tester.pump();
    await tester.longPress(find.byKey(const ValueKey('chat-model-shortcut-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-model-shortcut-2')));
    await tester.pump();
    await tester.longPress(find.byKey(const ValueKey('chat-model-shortcut-2')));
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
                ChatModelShortcutData(
                  slot: 1,
                  icon: Icon(Icons.filter_1, key: ValueKey('model-icon-1')),
                ),
                ChatModelShortcutData(
                  slot: 2,
                  icon: Icon(Icons.filter_2, key: ValueKey('model-icon-2')),
                ),
                ChatModelShortcutData(
                  slot: 3,
                  icon: Icon(Icons.filter_3, key: ValueKey('model-icon-3')),
                ),
                ChatModelShortcutData(
                  slot: 4,
                  icon: Icon(Icons.filter_4, key: ValueKey('model-icon-4')),
                ),
                ChatModelShortcutData(
                  slot: 5,
                  icon: Icon(Icons.filter_5, key: ValueKey('model-icon-5')),
                ),
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
      expect(find.text('Model $slot'), findsNothing);
      expect(find.byKey(ValueKey('chat-model-shortcut-$slot')), findsOneWidget);
      expect(find.byKey(ValueKey('model-icon-$slot')), findsOneWidget);
    }
    expect(
      tester.getSize(find.byKey(const ValueKey('chat-model-shortcut-group'))),
      const Size(160, 32),
    );

    await tester.tap(find.byKey(const ValueKey('chat-model-shortcut-5')));
    await tester.pump();
    await tester.longPress(find.byKey(const ValueKey('chat-model-shortcut-5')));
    await tester.pump();

    expect(taps, [5]);
    expect(longPresses, [5]);

    taps.clear();
    longPresses.clear();
    tester.view.physicalSize = const Size(240, 600);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-model-shortcut-5')), findsNothing);
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
