import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/desktop/hotkeys/sidebar_tab_bus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('switches to topics when assistants are selected', () async {
    final bus = DesktopSidebarTabBus.instance;
    bus.setCurrentIndex(0);
    final event = bus.stream.first;

    bus.switchToTopicsIfAssistantSelected();

    expect(await event, 1);
  });

  test('does not switch when topics are already selected', () async {
    final bus = DesktopSidebarTabBus.instance;
    bus.setCurrentIndex(1);
    var eventCount = 0;
    final subscription = bus.stream.listen((_) => eventCount++);

    bus.switchToTopicsIfAssistantSelected();
    await Future<void>.delayed(Duration.zero);

    expect(eventCount, 0);
    await subscription.cancel();
  });
}
