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

    test('unordered list item: visible "First item" maps to "- First item"', () {
      // Bullet is a Container widget, NOT text → no "- " in selection.
      expect(
        findMarkdownRangeForSelection('- First item', 'First item'),
        '- First item',
      );
    });

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
      final result = findMarkdownRangeForSelection(md, 'SectionSome text here.');
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
        findMarkdownRangeForSelection('# Heading\n\nParagraph.', 'xyz not found'),
        'xyz not found',
      );
    });

    test('skips fenced code block content (non-selectable)', () {
      const md = 'Before\n```dart\nvoid f() {}\n```\nAfter';
      expect(findMarkdownRangeForSelection(md, 'Before'), 'Before');
      expect(findMarkdownRangeForSelection(md, 'After'), 'After');
    });

    test('full round-trip: bold list items produce HTML with <strong> and <li>', () {
      const md = '# Results\n\n- **Alpha** wins\n- **Beta** loses\n\nDone.';
      // Flutter gives: "AlphawinsBetaloses" for the two list items.
      final mdSlice = findMarkdownRangeForSelection(md, 'AlphawinsBetaloses');
      expect(mdSlice, '- **Alpha** wins\n- **Beta** loses');
      final html = markdownSelectionToHtml(mdSlice);
      expect(html, contains('<strong>Alpha</strong>'));
      expect(html, contains('<strong>Beta</strong>'));
      expect(html, contains('<li>'));
    });
  });

  group('copyMarkdownSelectionToClipboard', () {
    test('writes recovered Markdown as the only plain-text payload', () async {
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
        'text': '- **Alpha**\n* Beta',
      });
    });
  });
}
