import 'package:flutter/services.dart';

/// Returns the input value with a user-typed triple-space trigger removed.
///
/// Multi-character pastes and active IME composition are ignored so the
/// shortcut only fires when the third space is inserted as an individual edit.
TextEditingValue? stripInputTranslationTrigger({
  required TextEditingValue previous,
  required TextEditingValue current,
}) {
  final composing = current.composing;
  if (composing.isValid && !composing.isCollapsed) return null;

  final selection = current.selection;
  if (!selection.isValid || !selection.isCollapsed) return null;
  if (current.text.length != previous.text.length + 1) return null;

  final caret = selection.extentOffset;
  final insertedAt = caret - 1;
  if (insertedAt < 0 || insertedAt >= current.text.length) return null;
  if (current.text.codeUnitAt(insertedAt) != 0x20) return null;

  final beforeInsertion = current.text.replaceRange(
    insertedAt,
    insertedAt + 1,
    '',
  );
  if (beforeInsertion != previous.text) return null;
  if (caret < 3 || current.text.substring(caret - 3, caret) != '   ') {
    return null;
  }

  final sourceText = current.text.replaceRange(caret - 3, caret, '');
  if (sourceText.trim().isEmpty) return null;

  return TextEditingValue(
    text: sourceText,
    selection: TextSelection.collapsed(offset: caret - 3),
    composing: TextRange.empty,
  );
}
