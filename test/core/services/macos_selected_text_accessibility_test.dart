import 'package:Kelivo/core/services/macos_selected_text_accessibility.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('publishes bounds and clears with the same source', () async {
    const channel = MethodChannel('test.selected_text_accessibility.publish');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final bridge = MacOSSelectedTextAccessibilityBridge(
      channel: channel,
      targetPlatform: TargetPlatform.macOS,
      source: 'source-a',
    );
    await bridge.updateSelection(
      'selected',
      bounds: const Rect.fromLTWH(10, 20, 30, 40),
    );

    expect(calls.single.method, 'updateSelection');
    expect(calls.single.arguments, <String, Object>{
      'source': 'source-a',
      'text': 'selected',
      'bounds': <String, double>{'x': 10, 'y': 20, 'width': 30, 'height': 40},
    });

    await bridge.dispose();
    expect(calls.last.arguments, <String, Object>{
      'source': 'source-a',
      'text': '',
    });
  });

  test('does not invoke the channel outside macOS', () async {
    const channel = MethodChannel('test.selected_text_accessibility.platform');
    var callCount = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      callCount++;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final bridge = MacOSSelectedTextAccessibilityBridge(
      channel: channel,
      targetPlatform: TargetPlatform.windows,
      source: 'source-a',
    );
    await bridge.updateSelection('selected');
    await bridge.dispose();

    expect(callCount, 0);
  });

  test('reports platform errors without failing selection callbacks', () async {
    const channel = MethodChannel('test.selected_text_accessibility.error');
    final errors = <Object>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'native_failure');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final bridge = MacOSSelectedTextAccessibilityBridge(
      channel: channel,
      targetPlatform: TargetPlatform.macOS,
      source: 'source-a',
      onError: (error, stackTrace) => errors.add(error),
    );
    await bridge.updateSelection('selected');

    expect(errors, hasLength(1));
    expect(errors.single, isA<PlatformException>());
  });
}
