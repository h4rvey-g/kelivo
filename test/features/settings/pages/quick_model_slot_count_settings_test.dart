import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/desktop/setting/default_model_pane.dart';
import 'package:Kelivo/desktop/widgets/desktop_select_dropdown.dart';
import 'package:Kelivo/features/settings/pages/settings_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile settings selects the model shortcut slot count', (
    tester,
  ) async {
    final preferences = createBusinessTestPreferences();
    final settings = SettingsProvider(preferences);
    await settings.loaded;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.text('Model Shortcut Slots');
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.text('1 slot'), findsOneWidget);
    expect(find.text('5 slots'), findsOneWidget);

    await tester.tap(find.text('5 slots'));
    await tester.pumpAndSettle();

    expect(settings.quickModelSlotCount, 5);
    expect(preferences.getInt('chat_model_quick_slot_count_v1'), 5);
  });

  testWidgets('desktop default model pane exposes the same slot count', (
    tester,
  ) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: DesktopDefaultModelPane()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Model Shortcut Slots'), findsOneWidget);
    final dropdown = tester.widget<DesktopSelectDropdown<int>>(
      find.byKey(const ValueKey('quick-model-slot-count-dropdown')),
    );
    expect(dropdown.value, 2);
    expect(dropdown.options.map((option) => option.value), [1, 2, 3, 4, 5]);

    await dropdown.onSelected(4);
    await tester.pump();

    expect(settings.quickModelSlotCount, 4);
  });
}
