import 'package:Kelivo/core/database/business_settings_router.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsProvider input translation', () {
    test('defaults the shortcut to enabled', () async {
      final harness = await createBusinessTestHarness(initial: {});
      final settings = SettingsProvider(harness.preferences);

      await settings.loaded;

      expect(settings.inputTranslationEnabled, isTrue);
    });

    test('loads and persists the shortcut and target language', () async {
      final harness = await createBusinessTestHarness(
        initial: {
          'input_translation_enabled_v1': true,
          'translate_target_lang_v1': 'ja',
        },
      );
      final settings = SettingsProvider(harness.preferences);

      await settings.loaded;
      expect(settings.inputTranslationEnabled, isTrue);
      expect(settings.translateTargetLang, 'ja');

      await settings.setInputTranslationEnabled(false);
      await settings.setTranslateTargetLang('fr');

      expect(
        harness.preferences.getBool('input_translation_enabled_v1'),
        isFalse,
      );
      expect(harness.preferences.getString('translate_target_lang_v1'), 'fr');
    });

    test('includes the shortcut in synced business preferences', () {
      expect(
        BusinessKeyRegistry.classify('input_translation_enabled_v1'),
        BusinessKeyDisposition.preference,
      );
    });
  });
}
