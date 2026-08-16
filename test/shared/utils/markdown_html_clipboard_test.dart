import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/shared/utils/markdown_html_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─────────────────────────────────────────────────────────────────────────
  // markdownSelectionToHtml
  // ─────────────────────────────────────────────────────────────────────────
  group('markdownSelectionToHtml', () {
    test('empty / blank returns empty', () {
      expect(markdownSelectionToHtml(''), '');
      expect(markdownSelectionToHtml('   '), '');
    });

    test('plain paragraph', () {
      expect(markdownSelectionToHtml('Hello world'), '<p>Hello world</p>');
    });

    test('ATX headings', () {
      expect(markdownSelectionToHtml('# H1'), '<h1>H1</h1>');
      expect(markdownSelectionToHtml('## H2'), '<h2>H2</h2>');
      expect(markdownSelectionToHtml('### H3'), '<h3>H3</h3>');
    });

    test('bold', () {
      expect(
        markdownSelectionToHtml('**bold** word'),
        '<p><strong>bold</strong> word</p>',
      );
    });

    test('italic', () {
      expect(
        markdownSelectionToHtml('*italic* word'),
        '<p><em>italic</em> word</p>',
      );
    });

    test('inline code', () {
      expect(
        markdownSelectionToHtml('Use `flutter run`'),
        '<p>Use <code>flutter run</code></p>',
      );
    });

    test('HTML character escaping', () {
      expect(
        markdownSelectionToHtml('a & b < c > d'),
        '<p>a &amp; b &lt; c &gt; d</p>',
      );
    });

    test('raw HTML blocks are escaped instead of copied as active HTML', () {
      final html = markdownSelectionToHtml('<script>alert("x")</script>');

      expect(html, isNot(contains('<script>')));
      expect(
        html,
        contains('&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;'),
      );
    });

    test('unordered list', () {
      expect(
        markdownSelectionToHtml('- Apples\n- Bananas\n- Cherries'),
        '<ul><li>Apples</li><li>Bananas</li><li>Cherries</li></ul>',
      );
    });

    test('ordered list', () {
      expect(
        markdownSelectionToHtml('1. First\n2. Second\n3. Third'),
        '<ol><li>First</li><li>Second</li><li>Third</li></ol>',
      );
    });

    test('list closes on blank line', () {
      expect(
        markdownSelectionToHtml('- Item\n\nParagraph'),
        '<ul><li>Item</li></ul><p>Paragraph</p>',
      );
    });

    test('fenced code block with language', () {
      expect(
        markdownSelectionToHtml('```dart\nvoid main() {}\n```'),
        '<pre><code class="language-dart">void main() {}</code></pre>',
      );
    });

    test('fenced code block without language', () {
      expect(
        markdownSelectionToHtml('```\nsome code\n```'),
        '<pre><code>some code</code></pre>',
      );
    });

    test('blockquote', () {
      expect(
        markdownSelectionToHtml('> Quoted'),
        '<blockquote><p>Quoted</p></blockquote>',
      );
    });

    test('horizontal rule', () {
      expect(markdownSelectionToHtml('---'), '<hr>');
      expect(markdownSelectionToHtml('***'), '<hr>');
    });

    test('bold inside heading', () {
      expect(
        markdownSelectionToHtml('## **Bold** heading'),
        '<h2><strong>Bold</strong> heading</h2>',
      );
    });

    test('mixed content', () {
      const md = '# Title\n\n- Item 1\n- Item 2\n\nParagraph with **bold**.';
      expect(
        markdownSelectionToHtml(md),
        '<h1>Title</h1>'
        '<ul><li>Item 1</li><li>Item 2</li></ul>'
        '<p>Paragraph with <strong>bold</strong>.</p>',
      );
    });

    test('unterminated fenced block does not throw', () {
      expect(
        () => markdownSelectionToHtml('```dart\nvoid main() {}'),
        returnsNormally,
      );
    });

    test('backticks suppress bold inside code span', () {
      final html = markdownSelectionToHtml('`**not bold**`');
      expect(html, '<p><code>**not bold**</code></p>');
      expect(html, isNot(contains('<strong>')));
    });

    test('nested mixed lists retain their hierarchy', () {
      const markdown = '''
- **Parent**
  1. Child with `code`
     - Grandchild
- Sibling
''';

      final html = markdownSelectionToHtml(markdown);

      expect(html, contains('<strong>Parent</strong>'));
      expect(html, contains('<code>code</code>'));
      expect(html, contains('<ul><li>Grandchild</li></ul>'));
      expect(html, contains('<ol>'));
      expect(html, isNot(contains('<p>  1.')));
      expect(html, isNot(contains('<p>     -')));
    });

    test('nested inline emphasis remains rich', () {
      final html = markdownSelectionToHtml('***very important***');

      expect(html, contains('<em><strong>very important</strong></em>'));
    });

    test('parenthesis and bracket LaTeX become semantic math nodes', () {
      final inline = markdownSelectionToHtml(r'Value: \(x_1 + x_2\)');
      final block = markdownSelectionToHtml(r'''\[
\frac{a}{b}
\]''');

      expect(inline, contains('class="math math-inline"'));
      expect(inline, contains('data-latex="x_1 + x_2"'));
      expect(block, contains('class="math math-block"'));
      expect(block, contains(r'data-latex="\frac{a}{b}"'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // findMarkdownRangeForSelection
  //
  // Flutter concatenates block selectables WITHOUT any separator, so the
  // matching must be whitespace-insensitive (strip all whitespace before
  // comparing).
  // ─────────────────────────────────────────────────────────────────────────
  group('findMarkdownRangeForSelection', () {
    test('plain paragraph matched verbatim', () {
      expect(
        findMarkdownRangeForSelection('Hello world', 'Hello world'),
        'Hello world',
      );
    });

    test('partial paragraph selection stays exact', () {
      const md =
          '1. **Safety with FVL**: Progestin-only contraceptives do not '
          'increase VTE risk.';

      expect(
        findMarkdownRangeForSelection(md, 'Progestin-only'),
        'Progestin-only',
      );
    });

    test(
      'partial formatted selection keeps style without surrounding text',
      () {
        expect(
          findMarkdownRangeForSelection(
            'Before **selected words** after',
            'selected words',
          ),
          '**selected words**',
        );
      },
    );

    test('bold line: visible text "bold word" maps to "**bold** word"', () {
      // gpt_markdown strips ** → "bold word" in selection.
      expect(
        findMarkdownRangeForSelection('**bold** word', 'bold word'),
        '**bold** word',
      );
    });

    test('heading: visible text "My heading" maps to "## My heading"', () {
      expect(
        findMarkdownRangeForSelection('## My heading', 'My heading'),
        '## My heading',
      );
    });

    test(
      'unordered list item: visible "First item" maps to "- First item"',
      () {
        // Bullet is a Container widget, NOT text → no "- " in selection.
        expect(
          findMarkdownRangeForSelection('- First item', 'First item'),
          '- First item',
        );
      },
    );

    test('ordered list item: visible "1. Step one" maps to "1. Step one"', () {
      // Number IS rendered as Text → "1. " is present in selection.
      expect(
        findMarkdownRangeForSelection('1. Step one', '1. Step one'),
        '1. Step one',
      );
    });

    test('multi-line selection', () {
      const md = '- Apple\n- Banana\n- Cherry';
      // Flutter gives "AppleBanana" (no separator) when selecting first two.
      final result = findMarkdownRangeForSelection(md, 'AppleBanana');
      expect(result, '- Apple\n- Banana');
    });

    test('rendered bullet characters map back to Markdown list markers', () {
      const md = '* Apple\n- Banana\n- Cherry';
      final result = findMarkdownRangeForSelection(md, '• Apple• Banana');
      expect(result, '* Apple\n- Banana');
    });

    test('Flutter object replacement bullets map back to Markdown markers', () {
      const md = '- Apple\n- Banana';
      final result = findMarkdownRangeForSelection(
        md,
        '\uFFFCApple\uFFFCBanana',
      );
      expect(result, md);
    });

    test('heading + paragraph (no separator in selection)', () {
      const md = '## Section\n\nSome text here.';
      // Flutter concatenates: "SectionSome text here."
      final result = findMarkdownRangeForSelection(
        md,
        'SectionSome text here.',
      );
      // The slice spans both blocks, blank line included; the HTML converter
      // treats the blank line as a block separator.
      expect(result, '## Section\n\nSome text here.');
      expect(
        markdownSelectionToHtml(result),
        '<h2>Section</h2><p>Some text here.</p>',
      );
    });

    test('blockquote', () {
      expect(
        findMarkdownRangeForSelection('> Quoted text', 'Quoted text'),
        '> Quoted text',
      );
    });

    test('returns selectedPlainText unchanged when no match', () {
      expect(
        findMarkdownRangeForSelection(
          '# Heading\n\nParagraph.',
          'xyz not found',
        ),
        'xyz not found',
      );
    });

    test('skips fenced code block content (non-selectable)', () {
      const md = 'Before\n```dart\nvoid f() {}\n```\nAfter';
      expect(findMarkdownRangeForSelection(md, 'Before'), 'Before');
      expect(findMarkdownRangeForSelection(md, 'After'), 'After');
    });

    test(
      'full round-trip: bold list items produce HTML with <strong> and <li>',
      () {
        const md = '# Results\n\n- **Alpha** wins\n- **Beta** loses\n\nDone.';
        // Flutter gives: "AlphawinsBetaloses" for the two list items.
        final mdSlice = findMarkdownRangeForSelection(md, 'AlphawinsBetaloses');
        expect(mdSlice, '- **Alpha** wins\n- **Beta** loses');
        final html = markdownSelectionToHtml(mdSlice);
        expect(html, contains('<strong>Alpha</strong>'));
        expect(html, contains('<strong>Beta</strong>'));
        expect(html, contains('<li>'));
      },
    );
  });

  group('buildMarkdownClipboardPayload', () {
    test('provides rich HTML and exact rendered plain text', () {
      const markdown =
          '1. **Safety with FVL**: Progestin-only contraceptives do not '
          'increase VTE risk.';
      const selected =
          '1. Safety with FVL: Progestin-only contraceptives do not '
          'increase VTE risk.';

      final payload = buildMarkdownClipboardPayload(
        selected,
        markdownSource: markdown,
      );

      expect(payload.plainText, selected);
      expect(
        payload.htmlText,
        '<ol><li><strong>Safety with FVL</strong>: Progestin-only '
        'contraceptives do not increase VTE risk.</li></ol>',
      );
    });

    test('partial selection remains exact in both representations', () {
      const markdown =
          '1. **Safety with FVL**: Progestin-only contraceptives do not '
          'increase VTE risk.';

      final payload = buildMarkdownClipboardPayload(
        'Progestin-only',
        markdownSource: markdown,
      );

      expect(payload.plainText, 'Progestin-only');
      expect(payload.htmlText, '<p>Progestin-only</p>');
    });

    test('partial bold selection is rich HTML but exact plain text', () {
      final payload = buildMarkdownClipboardPayload(
        'with FVL',
        markdownSource: 'Before **Safety with FVL** after',
      );

      expect(payload.plainText, 'with FVL');
      expect(payload.htmlText, '<p><strong>with FVL</strong></p>');
    });

    test('partial multi-line selection retains rich formatting', () {
      const markdown = '''
Before **start** tail
- **middle** item
After `end` tail
''';
      const selected = 'start tail\n•middle item\nAfter end';

      final payload = buildMarkdownClipboardPayload(
        selected,
        markdownSource: markdown,
      );

      expect(payload.plainText, selected);
      expect(payload.htmlText, contains('<strong>start</strong>'));
      expect(payload.htmlText, contains('<ul>'));
      expect(payload.htmlText, contains('<strong>middle</strong>'));
      expect(payload.htmlText, contains('<code>end</code>'));
      expect(payload.htmlText, isNot(contains('Before')));
      expect(payload.htmlText, isNot(contains('end</code> tail')));
    });

    test('nested list selection retains hierarchy and inline formatting', () {
      const markdown = '''
- **Parent**
  1. Child with `code`
     - Grandchild
- Sibling
''';
      const selected = '•Parent\n1. Child with code\n•Grandchild\n•Sibling';

      final payload = buildMarkdownClipboardPayload(
        selected,
        markdownSource: markdown,
      );

      expect(payload.plainText, selected);
      expect(payload.htmlText, contains('<strong>Parent</strong>'));
      expect(payload.htmlText, contains('<code>code</code>'));
      expect(payload.htmlText, contains('<ul><li>Grandchild</li></ul>'));
      expect(payload.htmlText, contains('<ol>'));
    });

    test('inline LaTeX does not collapse the selection to plain HTML', () {
      const markdown = r'Before **bold** and $E = mc^2$ after.';
      const selected = 'Before bold and \uFFFC after.';

      final payload = buildMarkdownClipboardPayload(
        selected,
        markdownSource: markdown,
      );

      expect(payload.plainText, selected);
      expect(payload.htmlText, contains('<strong>bold</strong>'));
      expect(payload.htmlText, contains('class="math math-inline"'));
      expect(payload.htmlText, contains('data-latex="E = mc^2"'));
      expect(payload.htmlText, isNot(contains('\uFFFC')));
    });

    test('block LaTeX between selected blocks remains in rich HTML', () {
      const markdown = r'''
**Before**

$$
\frac{a}{b}
$$

After
''';
      const selected = 'BeforeAfter';

      final payload = buildMarkdownClipboardPayload(
        selected,
        markdownSource: markdown,
      );

      expect(payload.plainText, selected);
      expect(payload.htmlText, contains('<strong>Before</strong>'));
      expect(payload.htmlText, contains('class="math math-block"'));
      expect(payload.htmlText, contains(r'data-latex="\frac{a}{b}"'));
      expect(payload.htmlText, contains('<p>After</p>'));
    });
  });

  group('copyMarkdownSelectionToClipboard', () {
    test('falls back to the exact rendered plain text', () async {
      MethodCall? clipboardCall;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        clipboardCall = call;
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await copyMarkdownSelectionToClipboard(
        '• Alpha• Beta',
        markdownSource: '- **Alpha**\n* Beta',
      );

      expect(clipboardCall?.method, 'Clipboard.setData');
      expect(clipboardCall?.arguments, <String, dynamic>{
        'text': '• Alpha• Beta',
      });
    });

    test('writes only a partial paragraph selection', () async {
      MethodCall? clipboardCall;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        clipboardCall = call;
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      const markdown =
          '1. **Safety with FVL**: Progestin-only contraceptives do not '
          'increase VTE risk.';
      await copyMarkdownSelectionToClipboard(
        'Progestin-only',
        markdownSource: markdown,
      );

      expect(clipboardCall?.method, 'Clipboard.setData');
      expect(clipboardCall?.arguments, <String, dynamic>{
        'text': 'Progestin-only',
      });
    });
  });
}
