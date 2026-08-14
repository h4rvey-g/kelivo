import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

typedef SelectedTextAccessibilityErrorHandler =
    void Function(Object error, StackTrace stackTrace);

class MacOSSelectedTextAccessibilityBridge {
  MacOSSelectedTextAccessibilityBridge({
    MethodChannel? channel,
    this.targetPlatform,
    String? source,
    this.onError,
  }) : _channel = channel ?? const OptionalMethodChannel(channelName),
       source = source ?? const Uuid().v4();

  static const String channelName =
      'com.psyche.kelivo/selected_text_accessibility';
  static const String methodName = 'updateSelection';

  final MethodChannel _channel;
  final TargetPlatform? targetPlatform;
  final SelectedTextAccessibilityErrorHandler? onError;

  final String source;

  bool _disposed = false;
  String? _publishedText;
  Rect? _publishedBounds;

  bool get _isSupported =>
      !kIsWeb &&
      (targetPlatform ?? defaultTargetPlatform) == TargetPlatform.macOS;

  Future<void> updateSelection(String? text, {Rect? bounds}) async {
    if (_disposed || !_isSupported) return;

    final normalizedText = text == null || text.isEmpty ? null : text;
    final normalizedBounds = normalizedText == null
        ? null
        : _validBounds(bounds);
    if (_publishedText == normalizedText &&
        _publishedBounds == normalizedBounds) {
      return;
    }

    _publishedText = normalizedText;
    _publishedBounds = normalizedBounds;
    await _publish(normalizedText, normalizedBounds);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    if (_publishedText != null) {
      _publishedText = null;
      _publishedBounds = null;
      await _publish(null, null);
    }
  }

  Future<void> _publish(String? text, Rect? bounds) async {
    final arguments = <String, Object>{
      'source': source,
      'text': text ?? '',
      if (bounds != null)
        'bounds': <String, double>{
          'x': bounds.left,
          'y': bounds.top,
          'width': bounds.width,
          'height': bounds.height,
        },
    };

    try {
      await _channel.invokeMethod<void>(methodName, arguments);
    } catch (error, stackTrace) {
      final errorHandler = onError;
      if (errorHandler != null) {
        errorHandler(error, stackTrace);
      } else if (kDebugMode) {
        debugPrint(
          '[SelectedTextAccessibility] Failed to publish selection: $error',
        );
      }
    }
  }

  Rect? _validBounds(Rect? bounds) {
    if (bounds == null ||
        !bounds.left.isFinite ||
        !bounds.top.isFinite ||
        !bounds.width.isFinite ||
        !bounds.height.isFinite ||
        bounds.width <= 0 ||
        bounds.height <= 0) {
      return null;
    }
    return bounds;
  }
}
