import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/shared/utils/markdown_html_clipboard.dart';

void main() {
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
      final html = markdownSelectionToHtml('**bold** word');
      expect(html, '<p><strong>bold</strong> word</p>');
    });

    test('converts italic text', () {
      final html = markdownSelectionToHtml('*italic* word');
      expect(html, '<p><em>italic</em> word</p>');
    });

    test('converts inline code', () {
      final html = markdownSelectionToHtml('Use `flutter run`');
      expect(html, '<p>Use <code>flutter run</code></p>');
    });

    test('escapes HTML special characters', () {
      final html = markdownSelectionToHtml('a & b < c > d');
      expect(html, '<p>a &amp; b &lt; c &gt; d</p>');
    });

    test('converts unordered list', () {
      final md = '- Apples\n- Bananas\n- Cherries';
      final html = markdownSelectionToHtml(md);
      expect(html, '<ul><li>Apples</li><li>Bananas</li><li>Cherries</li></ul>');
    });

    test('converts ordered list', () {
      final md = '1. First\n2. Second\n3. Third';
      final html = markdownSelectionToHtml(md);
      expect(html, '<ol><li>First</li><li>Second</li><li>Third</li></ol>');
    });

    test('closes list on blank line', () {
      final md = '- Item\n\nParagraph';
      final html = markdownSelectionToHtml(md);
      expect(html, '<ul><li>Item</li></ul><p>Paragraph</p>');
    });

    test('converts fenced code block', () {
      final md = '```dart\nvoid main() {}\n```';
      final html = markdownSelectionToHtml(md);
      expect(
        html,
        '<pre><code class="language-dart">void main() {}</code></pre>',
      );
    });

    test('converts fenced code block without language', () {
      final md = '```\nsome code\n```';
      final html = markdownSelectionToHtml(md);
      expect(html, '<pre><code>some code</code></pre>');
    });

    test('converts blockquote', () {
      final html = markdownSelectionToHtml('> A quoted line');
      expect(html, '<blockquote><p>A quoted line</p></blockquote>');
    });

    test('converts horizontal rule', () {
      expect(markdownSelectionToHtml('---'), '<hr>');
      expect(markdownSelectionToHtml('***'), '<hr>');
    });

    test('handles mixed bold and italic in heading', () {
      final html = markdownSelectionToHtml('## **Bold** heading');
      expect(html, '<h2><strong>Bold</strong> heading</h2>');
    });

    test('handles multi-line mixed content', () {
      final md = '# Title\n\n- Item 1\n- Item 2\n\nParagraph with **bold**.';
      final html = markdownSelectionToHtml(md);
      expect(
        html,
        '<h1>Title</h1>'
        '<ul><li>Item 1</li><li>Item 2</li></ul>'
        '<p>Paragraph with <strong>bold</strong>.</p>',
      );
    });

    test('does not crash on unterminated fenced block', () {
      final md = '```dart\nvoid main() {}';
      // Should produce a code block from collected lines, not throw.
      final html = markdownSelectionToHtml(md);
      expect(html, contains('void main() {}'));
    });

    test('inline code suppresses bold inside backticks', () {
      // The asterisks inside backticks should NOT become <strong>.
      final html = markdownSelectionToHtml('`**not bold**`');
      expect(html, '<p><code>**not bold**</code></p>');
      expect(html, isNot(contains('<strong>')));
    });
  });
}
