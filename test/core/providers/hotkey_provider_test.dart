import 'package:Kelivo/core/providers/hotkey_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exposes forward and backward model shortcut cycle hotkeys', () {
    final provider = HotkeyProvider();
    addTearDown(provider.dispose);

    final forward = provider.getById('cycle_model_shortcut_forward');
    final backward = provider.getById('cycle_model_shortcut_backward');

    expect(forward.l10nLabelKey, 'hotkeyCycleModelShortcutForward');
    expect(backward.l10nLabelKey, 'hotkeyCycleModelShortcutBackward');
    expect(forward.defaultWinLinux, isEmpty);
    expect(forward.defaultMac, 'cmd+s');
    expect(backward.defaultWinLinux, isEmpty);
    expect(backward.defaultMac, 'cmd+shift+s');
  });
}
