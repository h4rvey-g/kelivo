import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/custom_widgets/unordered_ordered_list.dart';
import '../utils/test_helpers.dart';

void main() {
  group('Ordered lists', () {
    testWidgets('single item', (tester) async {
      await pumpMarkdown(tester, '1. Item 1');
      final output = getSerializedOutput(tester);
      expect(output, contains('OL_ITEM'));
      expect(output, contains('1'));
    });

    testWidgets('multiple items', (tester) async {
      await pumpMarkdown(tester, '1. First\n2. Second\n3. Third');
      final output = getSerializedOutput(tester);
      // Should have 3 list items
      expect('OL_ITEM'.allMatches(output).length, equals(3));
    });

    testWidgets('item with styled text', (tester) async {
      await pumpMarkdown(tester, '1. **Bold** item');
      final output = getSerializedOutput(tester);
      expect(output, contains('OL_ITEM'));
    });

    testWidgets('item with inline code', (tester) async {
      await pumpMarkdown(tester, '1. Use `code` here');
      final output = getSerializedOutput(tester);
      expect(output, contains('OL_ITEM'));
    });

    testWidgets('item with link', (tester) async {
      await pumpMarkdown(tester, '1. Check [this](https://example.com)');
      final output = getSerializedOutput(tester);
      expect(output, contains('OL_ITEM'));
    });

    testWidgets('non-sequential numbers', (tester) async {
      // Library preserves the original numbers
      await pumpMarkdown(tester, '1. First\n5. Fifth\n10. Tenth');
      final output = getSerializedOutput(tester);
      expect(output, contains('OL_ITEM(1'));
      expect(output, contains('OL_ITEM(5'));
      expect(output, contains('OL_ITEM(10'));
    });

    testWidgets('large numbers', (tester) async {
      await pumpMarkdown(tester, '100. Item 100');
      final output = getSerializedOutput(tester);
      expect(output, contains('OL_ITEM'));
      expect(output, contains('100'));
    });

    testWidgets('nested items keep increasing indentation beyond two levels', (
      tester,
    ) async {
      await pumpMarkdown(tester, '''
1. Level 1
  1. Level 2
    1. Level 3
      1. Level 4
''', style: const TextStyle(fontSize: 16));

      final leftEdges = [
        for (var level = 1; level <= 4; level++)
          tester.getTopLeft(find.text('Level $level', findRichText: true)).dx,
      ];

      for (var index = 1; index < leftEdges.length; index++) {
        expect(leftEdges[index] - leftEdges[index - 1], closeTo(32, 0.5));
      }
      expect(find.byType(UnorderedListView), findsNothing);
    });
  });
}
