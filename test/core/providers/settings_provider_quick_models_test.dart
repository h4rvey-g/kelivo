import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('quick model slots load and persist independently', () async {
    final harness = await createBusinessTestHarness(
      initial: const {
        'chat_model_quick_slot_count_v1': 5,
        'chat_model_quick_slot_1_v1': 'Provider A::model-a',
        'chat_model_quick_slot_2_v1': 'Provider B::model::b',
        'chat_model_quick_slot_5_v1': 'Provider E::model-e',
      },
    );
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;

    expect(settings.quickModelSlotCount, 5);
    expect(settings.quickModelProvider(1), 'Provider A');
    expect(settings.quickModelId(1), 'model-a');
    expect(settings.quickModelProvider(2), 'Provider B');
    expect(settings.quickModelId(2), 'model::b');
    expect(settings.quickModelKey(5), 'Provider E::model-e');

    await settings.setQuickModel(3, 'Provider C', 'model-c');
    await settings.setQuickModelSlotCount(1);

    expect(
      harness.preferences.getString('chat_model_quick_slot_3_v1'),
      'Provider C::model-c',
    );
    expect(harness.preferences.getInt('chat_model_quick_slot_count_v1'), 1);
    expect(settings.quickModelKey(2), 'Provider B::model::b');
    expect(settings.quickModelKey(5), 'Provider E::model-e');
  });

  test('quick model slot count defaults to two and stays within 1-5', () async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;

    expect(
      settings.quickModelSlotCount,
      SettingsProvider.defaultQuickModelSlotCount,
    );

    await settings.setQuickModelSlotCount(9);
    expect(settings.quickModelSlotCount, 5);

    await settings.setQuickModelSlotCount(0);
    expect(settings.quickModelSlotCount, 1);
  });

  test('deleted models and providers are removed from quick slots', () async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;
    await settings.setQuickModel(1, 'Provider A', 'model-a');
    await settings.setQuickModel(5, 'Provider B', 'model-b');

    await settings.clearSelectionsForModel('Provider A', 'model-a');

    expect(settings.quickModelKey(1), isNull);
    expect(settings.quickModelKey(5), 'Provider B::model-b');
    expect(harness.preferences.getString('chat_model_quick_slot_1_v1'), isNull);

    await settings.clearSelectionsForProvider('Provider B');

    expect(settings.quickModelKey(5), isNull);
    expect(harness.preferences.getString('chat_model_quick_slot_5_v1'), isNull);
  });
}
