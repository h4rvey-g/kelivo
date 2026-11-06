import 'package:irondash_message_channel/irondash_message_channel.dart';
import 'package:super_clipboard/super_clipboard.dart';
// ignore: implementation_imports
import 'package:super_native_extensions/src/native/context.dart';

class NativeClipboardMock implements PlatformDataProvider {
  NativeClipboardMock() {
    final context = MockMessageChannelContext()
      ..registerMockMethodCallHandler('DataProviderManager', (call) {
        switch (call.method) {
          case 'registerDataProvider':
            final id = ++_nextId;
            final representations =
                (call.arguments as Map)['representations'] as Iterable;
            _providers[id] = {
              for (final representation in representations)
                representation['format'] as String: representation['data'],
            };
            return id;
          case 'unregisterDataProvider':
            _providers.remove(call.arguments);
            return null;
          default:
            throw StateError('Unexpected clipboard method: ${call.method}');
        }
      })
      ..registerMockMethodCallHandler('ClipboardWriter', (call) {
        if (call.method != 'writeToClipboard') {
          throw StateError('Unexpected clipboard method: ${call.method}');
        }
        items = [for (final id in call.arguments as Iterable) _providers[id]!];
        writeCount++;
        return null;
      });
    setContextOverride(context);
  }

  int _nextId = 0;
  final _providers = <int, Map<String, Object?>>{};
  List<Map<String, Object?>> items = [];
  int writeCount = 0;

  void clear() {
    items.clear();
    writeCount = 0;
  }

  Future<String?> get plainText => _read(Formats.plainText);
  Future<String?> get htmlText => _read(Formats.htmlText);

  Future<String?> _read(ValueFormat<String> format) async {
    for (final name in format.codec.decodingFormats) {
      if (getAllFormats().contains(name)) {
        return format.codec.decode(this, name);
      }
    }
    return null;
  }

  @override
  Future<Object?> getData(String format) async => items.firstOrNull?[format];

  @override
  List<String> getAllFormats() => items.firstOrNull?.keys.toList() ?? [];
}
