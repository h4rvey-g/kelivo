import 'package:Kelivo/features/home/utils/input_translation_trigger.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stripInputTranslationTrigger', () {
    test('removes three spaces after the third space is typed', () {
      const previous = TextEditingValue(
        text: 'hello  ',
        selection: TextSelection.collapsed(offset: 7),
      );
      const current = TextEditingValue(
        text: 'hello   ',
        selection: TextSelection.collapsed(offset: 8),
      );

      final result = stripInputTranslationTrigger(
        previous: previous,
        current: current,
      );

      expect(result?.text, 'hello');
      expect(result?.selection, const TextSelection.collapsed(offset: 5));
    });

    test('ignores three spaces inserted together by paste', () {
      const previous = TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
      );
      const current = TextEditingValue(
        text: 'hello   ',
        selection: TextSelection.collapsed(offset: 8),
      );

      expect(
        stripInputTranslationTrigger(previous: previous, current: current),
        isNull,
      );
    });

    test('ignores edits while an IME composition is active', () {
      const previous = TextEditingValue(
        text: 'ni  ',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 0, end: 2),
      );
      const current = TextEditingValue(
        text: 'ni   ',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 2),
      );

      expect(
        stripInputTranslationTrigger(previous: previous, current: current),
        isNull,
      );
    });

    test('does not trigger when the input contains only whitespace', () {
      const previous = TextEditingValue(
        text: '  ',
        selection: TextSelection.collapsed(offset: 2),
      );
      const current = TextEditingValue(
        text: '   ',
        selection: TextSelection.collapsed(offset: 3),
      );

      expect(
        stripInputTranslationTrigger(previous: previous, current: current),
        isNull,
      );
    });

    test('supports a trigger inserted before existing text', () {
      const previous = TextEditingValue(
        text: 'hello  world',
        selection: TextSelection.collapsed(offset: 7),
      );
      const current = TextEditingValue(
        text: 'hello   world',
        selection: TextSelection.collapsed(offset: 8),
      );

      final result = stripInputTranslationTrigger(
        previous: previous,
        current: current,
      );

      expect(result?.text, 'helloworld');
      expect(result?.selection, const TextSelection.collapsed(offset: 5));
    });
  });
}
