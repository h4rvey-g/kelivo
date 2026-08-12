import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/shared/utils/markdown_html_clipboard.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // markdownSelectionToHtml
  // ─────────────────────────────────────────────────────────────────────────
  group('markdownSelectionToHtml', () {
    test('returns empty string for blank input', () {
      expect(markdownSelectionToHtml(''), '');
      expect(markdownSelectionToHtml('   '), '');
    });

    test('wraps a plain paragraph in <p>', () {
      expect(markdownSelectionToHtml('Hello world'), '<p>Hello world</p>');
    });

    test('converts ATX headings', () {
      expect(markdownSelectionToHtml('# Title'), '<h1>Title</h1>');
      expect(markdownSelectionToHtml('## Sub'), '<h2>Sub</h2>');
      expect(markdownSelectionToHtml('### Third'), '<h3>Third</h3>');
    });

    test('converts bold text', () {
      expect(
        markdownSelectionToHtml('**bold** word'),
        '<p><strong>bold</strong> word</p>',
      );
    });

    test('converts italic text', () {
      expect(
        markdownSelectionToHtml('*italic* word'),
        '<p><em>italic</em> word</p>',
      );
    });

    test('converts inline code', () {
      expect(
        markdownSelectionToHtml('Use `flutter run`'),
        '<p>Use <code>flutter run</code></p>',
      );
    });

    test('escapes HTML special characters', () {
      expect(
        markdownSelectionToHtml('a & b < c > d'),
        '<p>a &amp; b &lt; c &gt; d</p>',
      );
    });

    test('converts unordered list', () {
      const md = '- Apples\n- Bananas\n- Cherries';
      expect(
        markdownSelectionToHtml(md),
        '<ul><li>Apples</li><li>Bananas</li><li>Cherries</li></ul>',
      );
    });

    test('converts ordered list', () {
      const md = '1. First\n2. Second\n3. Third';
      expect(
        markdownSelectionToHtml(md),
        '<ol><li>First</li><li>Second</li><li>Third</li></ol>',
      );
    });

    test('closes list on blank line', () {
      const md = '- Item\n\nParagraph';
      expect(
        markdownSelectionToHtml(md),
        '<ul><li>Item</li></ul><p>Paragraph</p>',
      );
    });

    test('converts fenced code block with language', () {
      const md = '```dart\nvoid main() {}\n```';
      expect(
        markdownSelectionToHtml(md),
        '<pre><code class="language-dart">void main() {}</code></pre>',
      );
    });

    test('converts fenced code block without language', () {
      const md = '```\nsome code\n```';
      expect(markdownSelectionToHtml(md), '<pre><code>some code</code></pre>');
    });

    test('converts blockquote', () {
      expect(
        markdownSelectionToHtml('> A quoted line'),
        '<blockquote><p>A quoted line</p></blockquote>',
      );
    });

    test('converts horizontal rule', () {
      expect(markdownSelectionToHtml('---'), '<hr>');
      expect(markdownSelectionToHtml('***'), '<hr>');
    });

    test('handles bold inside heading', () {
      expect(
        markdownSelectionToHtml('## **Bold** heading'),
        '<h2><strong>Bold</strong> heading</h2>',
      );
    });

    test('handles multi-line mixed content', () {
      const md =
          '# Title\n\n- Item 1\n- Item 2\n\nParagraph with **bold**.';
      expect(
        markdownSelectionToHtml(md),
        '<h1>Title</h1>'
        '<ul><li>Item 1</li><li>Item 2</li></ul>'
        '<p>Paragraph with <strong>bold</strong>.</p>',
      );
    });

    test('does not crash on unterminated fenced block', () {
      const md = '```dart\nvoid main() {}';
      final html = markdownSelectionToHtml(md);
      expect(html, contains('void main() {}'));
    });

    test('inline code suppresses bold inside backticks', () {
      final html = markdownSelectionToHtml('`**not bold**`');
      expect(html, '<p><code>**not bold**</code></p>');
      expect(html, isNot(contains('<strong>')));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // findMarkdownLinesForSelection
  //
  // The function maps rendered plain-text selections back to the original
  // Markdown source lines that produced them.
  // ─────────────────────────────────────────────────────────────────────────
  group('findMarkdownLinesForSelection', () {
    test('returns plain paragraph line unchanged when it matches', () {
      const md = 'Hello world';
      expect(findMarkdownLinesForSelection(md, 'Hello world'), 'Hello world');
    });

    test('returns markdown source for bold line', () {
      // The rendered text of "**bold** word" is "bold word".
      const md = '**bold** word';
      final result = findMarkdownLinesForSelection(md, 'bold word');
      expect(result, '**bold** word');
    });

    test('returns markdown source for heading', () {
      const md = '## My heading';
      // gpt_markdown renders "## My heading" → "My heading"
      final result = findMarkdownLinesForSelection(md, 'My heading');
      expect(result, '## My heading');
    });

    test('returns markdown source for unordered list item', () {
      const md = '- First item';
      final result = findMarkdownLinesForSelection(md, 'First item');
      expect(result, '- First item');
    });

    test('returns markdown source for ordered list item', () {
      const md = '1. Step one';
      final result = findMarkdownLinesForSelection(md, 'Step one');
      expect(result, '1. Step one');
    });

    test('returns multiple markdown lines for multi-line selection', () {
      const md = '- Apple\n- Banana\n- Cherry';
      // Rendered: "Apple\nBanana\nCherry"
      final result = findMarkdownLinesForSelection(md, 'Apple\nBanana');
      expect(result, '- Apple\n- Banana');
    });

    test('returns selection unchanged if no match found', () {
      const md = '# Heading\n\nSome paragraph.';
      // Selecting a string not present in rendered output.
      const notInSource = 'xyz not found';
      expect(
        findMarkdownLinesForSelection(md, notInSource),
        notInSource,
      );
    });

    test('skips fenced code block lines (non-selectable)', () {
      const md =
          'Before code\n```dart\nvoid f() {}\n```\nAfter code';
      // "Before code" and "After code" are selectable; code block lines are not.
      expect(
        findMarkdownLinesForSelection(md, 'Before code'),
        'Before code',
      );
      expect(
        findMarkdownLinesForSelection(md, 'After code'),
        'After code',
      );
    });

    test('handles selection spanning heading and paragraph', () {
      const md = '## Section\n\nSome text here.';
      // Rendered: "Section\nSome text here."
      final result = findMarkdownLinesForSelection(
        md,
        'Section\nSome text here.',
      );
      expect(result, '## Section\nSome text here.');
    });

    test('handles blockquote', () {
      const md = '> Quoted text';
      final result = findMarkdownLinesForSelection(md, 'Quoted text');
      expect(result, '> Quoted text');
    });

    test('full message: selects bold list items and returns markdown', () {
      const md =
          '# Results\n\n- **Alpha** wins\n- **Beta** loses\n\nDone.';
      // Rendered list: "Alpha wins\nBeta loses"
      final result = findMarkdownLinesForSelection(
        md,
        'Alpha wins\nBeta loses',
      );
      expect(result, '- **Alpha** wins\n- **Beta** loses');
      // Resulting HTML should contain <strong> and <li>
      final html = markdownSelectionToHtml(result);
      expect(html, contains('<strong>Alpha</strong>'));
      expect(html, contains('<li>'));
    });
  });
}
