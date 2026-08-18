import 'dart:async';

import 'package:flutter/services.dart';

class TransientTextPaste {
  const TransientTextPaste({required this.target, required this.text});

  final String target;
  final String text;
}

class TransientTextPasteBridge {
  static const MethodChannel _channel = MethodChannel(
    'com.psyche.kelivo/transient_text_paste',
  );
  static final StreamController<TransientTextPaste> _controller =
      StreamController<TransientTextPaste>.broadcast();
  static bool _initialized = false;

  static Stream<TransientTextPaste> get events {
    _ensureInitialized();
    return _controller.stream;
  }

  static Future<void> setTarget(String target, {required bool focused}) async {
    _ensureInitialized();
    try {
      await _channel.invokeMethod<void>('setTarget', {
        'target': target,
        'focused': focused,
      });
    } catch (_) {}
  }

  static void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onTextPaste') return;
      final arguments = call.arguments;
      if (arguments is! Map) return;
      final target = arguments['target'];
      final text = arguments['text'];
      if (target is! String ||
          target.isEmpty ||
          text is! String ||
          text.isEmpty) {
        return;
      }
      _controller.add(TransientTextPaste(target: target, text: text));
    });
  }
}
