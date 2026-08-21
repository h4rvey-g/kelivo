import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';

import 'support/business_test_harness.dart';

typedef _PreferenceGetter = bool Function(SettingsProvider settings);
typedef _PreferenceSetter =
    Future<void> Function(SettingsProvider settings, bool value);

final class _BooleanPreferenceCase {
  const _BooleanPreferenceCase({
    required this.name,
    required this.key,
    required this.defaultValue,
    required this.get,
    required this.set,
  });

  final String name;
  final String key;
  final bool defaultValue;
  final _PreferenceGetter get;
  final _PreferenceSetter set;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cases = <_BooleanPreferenceCase>[
    _BooleanPreferenceCase(
      name: 'tool result summary',
      key: 'display_show_tool_result_summary_v1',
      defaultValue: false,
      get: (settings) => settings.showToolResultSummary,
      set: (settings, value) => settings.setShowToolResultSummary(value),
    ),
    _BooleanPreferenceCase(
      name: 'collapsed thinking steps',
      key: 'display_collapse_thinking_steps_v1',
      defaultValue: false,
      get: (settings) => settings.collapseThinkingSteps,
      set: (settings, value) => settings.setCollapseThinkingSteps(value),
    ),
    _BooleanPreferenceCase(
      name: 'new assistant avatar UX',
      key: 'display_use_new_assistant_avatar_ux_v1',
      defaultValue: false,
      get: (settings) => settings.useNewAssistantAvatarUx,
      set: (settings, value) => settings.setUseNewAssistantAvatarUx(value),
    ),
    _BooleanPreferenceCase(
      name: 'mobile assistant detail outline',
      key: 'mobile_assistant_detail_outline_enabled_v1',
      defaultValue: false,
      get: (settings) => settings.mobileAssistantDetailOutlineEnabled,
      set: (settings, value) =>
          settings.setMobileAssistantDetailOutlineEnabled(value),
    ),
    _BooleanPreferenceCase(
      name: 'image cropper',
      key: 'image_cropper_enabled_v1',
      defaultValue: false,
      get: (settings) => settings.imageCropperEnabled,
      set: (settings, value) => settings.setImageCropperEnabled(value),
    ),
    _BooleanPreferenceCase(
      name: 'delete trailing messages on regeneration',
      key: 'display_regenerate_delete_trailing_messages_v1',
      defaultValue: false,
      get: (settings) => settings.regenerateDeleteTrailingMessages,
      set: (settings, value) =>
          settings.setRegenerateDeleteTrailingMessages(value),
    ),
    _BooleanPreferenceCase(
      name: 'regeneration confirmation dialog',
      key: 'display_show_regenerate_confirm_dialog_v1',
      defaultValue: true,
      get: (settings) => settings.showRegenerateConfirmDialog,
      set: (settings, value) => settings.setShowRegenerateConfirmDialog(value),
    ),
  ];

  group('SettingsProvider boolean preferences', () {
    for (final preference in cases) {
      test('${preference.name} defaults, loads, and persists', () async {
        final harness = await createBusinessTestHarness(initial: {});
        final settings = SettingsProvider(harness.preferences);
        await settings.loaded;

        expect(preference.get(settings), preference.defaultValue);

        final changedValue = !preference.defaultValue;
        await preference.set(settings, changedValue);

        expect(preference.get(settings), changedValue);
        expect(harness.preferences.getBool(preference.key), changedValue);

        final persistedHarness = await createBusinessTestHarness(
          initial: {preference.key: changedValue},
        );
        final persistedSettings = SettingsProvider(
          persistedHarness.preferences,
        );
        await persistedSettings.loaded;

        expect(preference.get(persistedSettings), changedValue);
      });
    }
  });
}
