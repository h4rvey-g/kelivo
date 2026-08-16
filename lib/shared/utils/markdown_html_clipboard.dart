import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:super_clipboard/super_clipboard.dart';

// ---------------------------------------------------------------------------
// Markdown → HTML
// ---------------------------------------------------------------------------

const _inlineDollarLatexPattern =
    r'(?<![\\$A-Za-z0-9])\$(?!\$)((?:\\.|[^$\\\n]){1,20000})\$(?![$A-Za-z0-9])';
const _inlineParenLatexPattern = r'\\\(([^\n]{1,20000}?)\\\)';
final _inlineDollarLatexRegExp = RegExp(_inlineDollarLatexPattern);
final _inlineParenLatexRegExp = RegExp(_inlineParenLatexPattern);

final _clipboardMarkdownExtensions = md.ExtensionSet(
  md.ExtensionSet.gitHubFlavored.blockSyntaxes,
  md.ExtensionSet.gitHubFlavored.inlineSyntaxes
      .where((syntax) => syntax is! md.InlineHtmlSyntax)
      .toList(growable: false),
);

String _escapeHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

bool _isValidDollarLatexBody(String body) =>
    body.isNotEmpty && body.trim() == body;

md.Element _mathElement(String latex, {required bool block}) {
  final escaped = _escapeHtml(latex.trim());
  final element = md.Element.text(block ? 'div' : 'span', escaped)
    ..attributes['class'] = block ? 'math math-block' : 'math math-inline'
    ..attributes['data-latex'] = escaped
    ..attributes['style'] = block
        ? 'font-family: serif; font-style: italic; text-align: center; '
              'white-space: pre-wrap;'
        : 'font-family: serif; font-style: italic;';
  return element;
}

class _InlineDollarLatexSyntax extends md.InlineSyntax {
  _InlineDollarLatexSyntax()
    : super(_inlineDollarLatexPattern, startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final body = match.group(1)!;
    if (_isValidDollarLatexBody(body)) {
      parser.addNode(_mathElement(body, block: false));
    } else {
      parser.addNode(md.Text(_escapeHtml(match.group(0)!)));
    }
    return true;
  }
}

class _InlineParenLatexSyntax extends md.InlineSyntax {
  _InlineParenLatexSyntax()
    : super(_inlineParenLatexPattern, startCharacter: 0x5c);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(_mathElement(match.group(1)!, block: false));
    return true;
  }
}

class _LatexBlockSyntax extends md.BlockSyntax {
  const _LatexBlockSyntax();

  static final _pattern = RegExp(r'^\s*(?:\$\$|\\\[)');

  @override
  RegExp get pattern => _pattern;

  @override
  md.Node parse(md.BlockParser parser) {
    final openingLine = parser.current.content.trim();
    final dollarDelimited = openingLine.startsWith(r'$$');
    final opening = dollarDelimited ? r'$$' : r'\[';
    final closing = dollarDelimited ? r'$$' : r'\]';
    final bodyLines = <String>[];

    var remainder = openingLine.substring(opening.length);
    parser.advance();

    bool consumeClosing(String value) {
      final closingIndex = value.lastIndexOf(closing);
      if (closingIndex == -1 ||
          value.substring(closingIndex + closing.length).trim().isNotEmpty) {
        return false;
      }
      bodyLines.add(value.substring(0, closingIndex));
      return true;
    }

    var closed = remainder.isNotEmpty && consumeClosing(remainder);
    if (!closed && remainder.isNotEmpty) bodyLines.add(remainder);

    while (!closed && !parser.isDone) {
      remainder = parser.current.content;
      parser.advance();
      closed = consumeClosing(remainder);
      if (!closed) bodyLines.add(remainder);
    }

    return _mathElement(bodyLines.join('\n'), block: true);
  }
}

class _CompactHtmlRenderer implements md.NodeVisitor {
  final _buffer = StringBuffer();
  final _elementStack = <String>[];

  String render(List<md.Node> nodes) {
    for (final node in nodes) {
      node.accept(this);
    }
    return _buffer.toString();
  }

  @override
  void visitText(md.Text text) {
    var value = text.textContent;
    final inFencedCode =
        _elementStack.length >= 2 &&
        _elementStack.last == 'code' &&
        _elementStack[_elementStack.length - 2] == 'pre';
    if (inFencedCode && value.endsWith('\n')) {
      value = value.substring(0, value.length - 1);
    }
    if (!inFencedCode && RegExp(r'<(?:/?[A-Za-z]|!|\?)').hasMatch(value)) {
      value = _escapeHtml(value);
    }
    _buffer.write(value);
  }

  @override
  bool visitElementBefore(md.Element element) {
    _buffer.write('<${element.tag}');
    for (final attribute in element.attributes.entries) {
      _buffer.write(' ${attribute.key}="${attribute.value}"');
    }
    _buffer.write('>');
    if (element.isEmpty) return false;
    _elementStack.add(element.tag);
    return true;
  }

  @override
  void visitElementAfter(md.Element element) {
    _buffer.write('</${element.tag}>');
    _elementStack.removeLast();
  }
}

/// Converts Markdown to a compact HTML fragment suitable for the clipboard.
///
/// A real Markdown AST preserves nested lists and mixed block structures.
/// LaTeX is represented as styled semantic nodes carrying the original source
/// in `data-latex`, so rich paste targets do not force the whole selection to
/// plain text when a non-selectable math widget appears in the source.
String markdownSelectionToHtml(String markdown) {
  if (markdown.trim().isEmpty) return '';

  final document = md.Document(
    blockSyntaxes: const [_LatexBlockSyntax()],
    inlineSyntaxes: [_InlineDollarLatexSyntax(), _InlineParenLatexSyntax()],
    extensionSet: _clipboardMarkdownExtensions,
    encodeHtml: true,
  );
  return _CompactHtmlRenderer().render(document.parse(markdown.trim()));
}

// ---------------------------------------------------------------------------
// Offset-mapped projection
//
// Goal: given the original Markdown source, determine which source characters
// are *visible* (i.e. rendered as selectable text), building a parallel list
// of (sourceIndex, visibleChar) pairs.
//
// Key observations from gpt_markdown's widget tree:
//
//  • Block prefixes are DROPPED from selectable text:
//      "# Title"    → "Title"
//      "- Item"     → "Item"    (bullet is a Container widget, not text)
//      "> Quote"    → "Quote"
//  • Ordered-list markers ARE selectable ("1." is a Text.rich TextSpan):
//      "1. Step"    → "1. Step"
//  • Inline syntax is stripped by Flutter's text selection:
//      "**bold**"   → "bold"
//      "*italic*"   → "italic"
//      "`code`"     → "code"
//  • Fenced code blocks render in a non-selectable widget — skip entirely.
//  • Blank lines produce no visible characters.
// ---------------------------------------------------------------------------

class _InlineMarkdownSpan {
  const _InlineMarkdownSpan({
    required this.openingMarker,
    required this.closingMarker,
    required this.contentStart,
    required this.contentEnd,
  });

  final String openingMarker;
  final String closingMarker;
  final int contentStart;
  final int contentEnd;

  bool contains(int sourceOffset) =>
      sourceOffset >= contentStart && sourceOffset <= contentEnd;
}

class _Projection {
  /// sourceIndex[i] = position in the original source string for visibleText[i]
  final List<int> sourceIndex;
  final String visibleText;
  final List<_InlineMarkdownSpan> inlineSpans;

  const _Projection(this.visibleText, this.sourceIndex, this.inlineSpans);
}

const _selectionDecorationRunes = <int>{
  0x2022, // bullet
  0x2023, // triangular bullet
  0x25aa, // small square
  0x25cb, // white circle
  0x25cf, // black circle
  0x25e6, // white bullet
  0xfffc, // Flutter object replacement character
};

String _removeSelectionDecorations(String text) {
  return String.fromCharCodes(
    text.runes.where((rune) => !_selectionDecorationRunes.contains(rune)),
  );
}

_Projection _buildProjection(String source) {
  final chars = <String>[];
  final indices = <int>[];
  final inlineSpans = <_InlineMarkdownSpan>[];

  void emit(int srcIdx, String ch) {
    chars.add(ch);
    indices.add(srcIdx);
  }

  final lines = source.split('\n');
  int srcPos = 0;
  bool inFence = false;
  String? mathBlockClosing;

  for (final line in lines) {
    final lineLen = line.length;
    final lineStart = srcPos;
    final trimmedLine = line.trim();

    // Skip fenced code blocks (non-selectable widget).
    if (!inFence && RegExp(r'^(`{3,}|~{3,})').hasMatch(line)) {
      inFence = true;
      srcPos += lineLen + 1;
      continue;
    }
    if (inFence) {
      if (RegExp(r'^(`{3,}|~{3,})\s*$').hasMatch(line)) {
        inFence = false;
      }
      srcPos += lineLen + 1;
      continue;
    }

    // Math widgets are wrapped in SelectionContainer.disabled. Skip their
    // source from the visible projection so text selected across a formula
    // still maps to one contiguous Markdown source range.
    if (mathBlockClosing != null) {
      if (trimmedLine.endsWith(mathBlockClosing)) mathBlockClosing = null;
      srcPos += lineLen + 1;
      continue;
    }
    final opensDollarMath = trimmedLine.startsWith(r'$$');
    final opensBracketMath = trimmedLine.startsWith(r'\[');
    if (opensDollarMath || opensBracketMath) {
      final opening = opensDollarMath ? r'$$' : r'\[';
      final closing = opensDollarMath ? r'$$' : r'\]';
      final remainder = trimmedLine.substring(opening.length);
      final closingIndex = remainder.lastIndexOf(closing);
      final closesOnSameLine =
          closingIndex >= 0 &&
          remainder.substring(closingIndex + closing.length).trim().isEmpty;
      if (!closesOnSameLine) mathBlockClosing = closing;
      srcPos += lineLen + 1;
      continue;
    }

    // Blank line: no visible text.
    if (trimmedLine.isEmpty) {
      srcPos += lineLen + 1;
      continue;
    }

    // HR: no visible text.
    if (RegExp(r'^\s{0,3}[-*_]{3,}\s*$').hasMatch(line)) {
      srcPos += lineLen + 1;
      continue;
    }

    // Inter-line separator (used only by the whitespace-insensitive search;
    // real Flutter selection may omit newlines between blocks).
    if (chars.isNotEmpty) {
      final nlSrcIdx = srcPos > 0 ? srcPos - 1 : 0;
      emit(nlSrcIdx, '\n');
    }

    // Determine content start for this line.
    int contentStart = 0;

    // ATX heading: "## text" → skip "## "
    final hmPfx = RegExp(r'^\s{0,3}(#{1,6}) ').firstMatch(line);
    if (hmPfx != null) {
      contentStart = hmPfx.group(0)!.length;
      _emitInlineMd(line, lineStart, contentStart, emit, inlineSpans.add);
      srcPos += lineLen + 1;
      continue;
    }

    // Unordered list: "- text" → skip "- " (bullet is not selectable text)
    final ulPfx = RegExp(r'^\s*[-*+]\s+').firstMatch(line);
    if (ulPfx != null) {
      contentStart = ulPfx.group(0)!.length;
      _emitInlineMd(line, lineStart, contentStart, emit, inlineSpans.add);
      srcPos += lineLen + 1;
      continue;
    }

    // Ordered list: "1. text" → KEEP "1. " (rendered as selectable text)
    final olPfx = RegExp(r'^(\s*)(\d+[.)])\s+').firstMatch(line);
    if (olPfx != null) {
      final leadingLength = olPfx.group(1)!.length;
      final marker = olPfx.group(2)!;
      for (int i = 0; i < marker.length; i++) {
        emit(lineStart + leadingLength + i, marker[i]);
      }
      emit(lineStart + olPfx.group(0)!.length - 1, ' ');
      contentStart = olPfx.group(0)!.length;
      _emitInlineMd(line, lineStart, contentStart, emit, inlineSpans.add);
      srcPos += lineLen + 1;
      continue;
    }

    // Blockquote: "> text" → skip "> "
    final bqPfx = RegExp(r'^\s{0,3}> ?').firstMatch(line);
    if (bqPfx != null) {
      contentStart = bqPfx.group(0)!.length;
      _emitInlineMd(line, lineStart, contentStart, emit, inlineSpans.add);
      srcPos += lineLen + 1;
      continue;
    }

    // Plain paragraph.
    _emitInlineMd(line, lineStart, 0, emit, inlineSpans.add);
    srcPos += lineLen + 1;
  }

  return _Projection(chars.join(), indices, inlineSpans);
}

/// Emits the recursively rendered inline text and maps every visible
/// character to its absolute source offset.
void _emitInlineMd(
  String line,
  int lineStart,
  int contentStart,
  void Function(int, String) emit,
  void Function(_InlineMarkdownSpan) emitSpan,
) {
  void emitRange(int start, int end) {
    var i = start;
    while (i < end) {
      final dollarMath = _inlineDollarLatexRegExp.matchAsPrefix(line, i);
      if (dollarMath != null &&
          dollarMath.end <= end &&
          _isValidDollarLatexBody(dollarMath.group(1)!)) {
        i = dollarMath.end;
        continue;
      }
      final parenMath = _inlineParenLatexRegExp.matchAsPrefix(line, i);
      if (parenMath != null && parenMath.end <= end) {
        i = parenMath.end;
        continue;
      }

      // Inline code is literal: only the surrounding backticks disappear.
      if (line[i] == '`') {
        final close = line.indexOf('`', i + 1);
        if (close != -1 && close < end) {
          emitSpan(
            _InlineMarkdownSpan(
              openingMarker: '`',
              closingMarker: '`',
              contentStart: lineStart + i + 1,
              contentEnd: lineStart + close - 1,
            ),
          );
          for (var j = i + 1; j < close; j++) {
            emit(lineStart + j, line[j]);
          }
          i = close + 1;
          continue;
        }
      }

      String? marker;
      if (i + 2 < end) {
        final triple = line.substring(i, i + 3);
        if (triple == '***' || triple == '___') marker = triple;
      }
      if (marker == null && i + 1 < end) {
        final pair = line.substring(i, i + 2);
        if (pair == '**' || pair == '__' || pair == '~~') marker = pair;
      }
      marker ??= (line[i] == '*' || line[i] == '_') ? line[i] : null;
      if (marker != null) {
        final close = line.indexOf(marker, i + marker.length);
        if (close != -1 && close < end) {
          emitSpan(
            _InlineMarkdownSpan(
              openingMarker: marker,
              closingMarker: marker,
              contentStart: lineStart + i + marker.length,
              contentEnd: lineStart + close - 1,
            ),
          );
          emitRange(i + marker.length, close);
          i = close + marker.length;
          continue;
        }
      }

      // Markdown links render only their label as selectable text.
      if (line[i] == '[') {
        final labelEnd = line.indexOf('](', i + 1);
        final destinationEnd = labelEnd == -1
            ? -1
            : line.indexOf(')', labelEnd + 2);
        if (labelEnd != -1 && destinationEnd != -1 && destinationEnd < end) {
          emitSpan(
            _InlineMarkdownSpan(
              openingMarker: '[',
              closingMarker: line.substring(labelEnd, destinationEnd + 1),
              contentStart: lineStart + i + 1,
              contentEnd: lineStart + labelEnd - 1,
            ),
          );
          emitRange(i + 1, labelEnd);
          i = destinationEnd + 1;
          continue;
        }
      }

      // Backslash escapes render the escaped punctuation without the slash.
      if (line[i] == r'\' && i + 1 < end) {
        emit(lineStart + i + 1, line[i + 1]);
        i += 2;
        continue;
      }

      emit(lineStart + i, line[i]);
      i++;
    }
  }

  emitRange(contentStart, line.length);
}

// ---------------------------------------------------------------------------
// findMarkdownRangeForSelection
//
// Maps selected rendered plain-text back to the Markdown source that produced
// it. Block-level Markdown is recovered only when the selection covers whole
// rendered lines; a partial-line selection must remain exact.
//
// WHY WHITESPACE-FREE MATCHING:
// Flutter's _SelectableRegionContainerDelegate.getSelectedContent() writes:
//
//     final buffer = StringBuffer();
//     for (final selection in selections) buffer.write(selection.plainText);
//
// There is NO separator between blocks.  Selecting a heading plus two list
// items yields "TitleItem oneItem two" — no newlines, no spaces between
// blocks.  Stripping ALL whitespace before the substring search makes the
// algorithm immune to this concatenation behaviour.
// ---------------------------------------------------------------------------

/// Returns the slice of [markdownSource] (including original Markdown syntax)
/// whose rendered plain-text corresponds to [selectedPlainText]. Whole rendered
/// lines recover their block-level Markdown syntax. Partial-line selections
/// keep exact visible bounds while recovering any inline style at their edges,
/// so copying a word cannot expand to its entire paragraph.
///
/// Returns [selectedPlainText] unchanged when no match can be found.
String findMarkdownRangeForSelection(
  String markdownSource,
  String selectedPlainText,
) {
  if (selectedPlainText.trim().isEmpty) return selectedPlainText;

  final proj = _buildProjection(markdownSource);
  if (proj.visibleText.isEmpty) return selectedPlainText;

  final ws = RegExp(r'\s');

  // Build whitespace-free versions of both sides, keeping index maps back
  // to positions in proj.visibleText / selectedPlainText respectively.
  final projCompactBuf = StringBuffer();
  final projCompactToProj = <int>[];
  for (int i = 0; i < proj.visibleText.length; i++) {
    if (ws.hasMatch(proj.visibleText[i])) continue;
    projCompactBuf.write(proj.visibleText[i]);
    projCompactToProj.add(i);
  }
  final projCompact = projCompactBuf.toString();

  final directSelection = selectedPlainText.replaceAll(ws, '');
  if (directSelection.isEmpty) return selectedPlainText;

  // Depending on the platform and paste target, Flutter's WidgetSpan used
  // for unordered-list bullets may surface as a visible bullet or an object
  // replacement character. These characters are decorations, not part of
  // the source Markdown, so retry without them when the direct match fails.
  final selectionCandidates = <String>[
    directSelection,
    _removeSelectionDecorations(directSelection),
  ];

  var hit = -1;
  var matchedSelection = '';
  for (final candidate in selectionCandidates.toSet()) {
    if (candidate.isEmpty) continue;
    hit = projCompact.indexOf(candidate);
    if (hit != -1) {
      matchedSelection = candidate;
      break;
    }
  }
  if (hit == -1) return selectedPlainText;

  // Map compact indices → proj.visibleText indices → source indices.
  final projStartPos = projCompactToProj[hit];
  final projEndPos = projCompactToProj[hit + matchedSelection.length - 1];

  final srcStart = proj.sourceIndex[projStartPos];
  final srcEnd = proj.sourceIndex[projEndPos];

  // Locate the source lines touched by the selection.
  int lineStart = srcStart;
  while (lineStart > 0 && markdownSource[lineStart - 1] != '\n') {
    lineStart--;
  }

  int lineEnd = srcEnd;
  while (lineEnd < markdownSource.length - 1 &&
      markdownSource[lineEnd + 1] != '\n') {
    lineEnd++;
  }

  // Recover block prefixes and inline Markdown only when every visible
  // character on both boundary lines was selected. Expanding a partial-line
  // selection to these boundaries would copy text the user did not select.
  final previousCompactIndex = hit - 1;
  final nextCompactIndex = hit + matchedSelection.length;
  final startsAtRenderedLineBoundary =
      previousCompactIndex < 0 ||
      proj.sourceIndex[projCompactToProj[previousCompactIndex]] < lineStart;
  final endsAtRenderedLineBoundary =
      nextCompactIndex >= projCompactToProj.length ||
      proj.sourceIndex[projCompactToProj[nextCompactIndex]] > lineEnd;

  if (!startsAtRenderedLineBoundary || !endsAtRenderedLineBoundary) {
    // Keep the visible range exact while restoring any inline style active at
    // either edge. This lets a partial bold/code selection paste richly
    // without bringing along text outside the selection.
    final sourceFragment = markdownSource.substring(srcStart, srcEnd + 1);

    final openingSpans =
        proj.inlineSpans.where((span) => span.contains(srcStart)).toList()
          ..sort((a, b) => a.contentStart.compareTo(b.contentStart));
    final closingSpans =
        proj.inlineSpans.where((span) => span.contains(srcEnd)).toList()
          ..sort((a, b) => a.contentEnd.compareTo(b.contentEnd));

    return '${openingSpans.map((span) => span.openingMarker).join()}'
        '$sourceFragment'
        '${closingSpans.map((span) => span.closingMarker).join()}';
  }

  return markdownSource.substring(lineStart, lineEnd + 1);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Clipboard representations for a rendered Markdown selection.
class MarkdownClipboardPayload {
  const MarkdownClipboardPayload({
    required this.plainText,
    required this.htmlText,
  });

  /// Exact rendered text selected by the user.
  final String plainText;

  /// Rich representation used by paste targets that accept HTML.
  final String htmlText;
}

/// Builds plain-text and rich-text representations for the same selection.
MarkdownClipboardPayload buildMarkdownClipboardPayload(
  String selectedPlainText, {
  String? markdownSource,
}) {
  final markdownForHtml = (markdownSource != null && markdownSource.isNotEmpty)
      ? findMarkdownRangeForSelection(markdownSource, selectedPlainText)
      : selectedPlainText;

  return MarkdownClipboardPayload(
    plainText: selectedPlainText,
    htmlText: markdownSelectionToHtml(markdownForHtml),
  );
}

/// Writes both rich HTML and exact plain text to the system clipboard.
///
/// Normal paste in rich-text applications prefers `text/html`. Paste without
/// formatting (for example Cmd+Shift+V) uses the `text/plain` representation.
/// If the richer clipboard API is unavailable, this falls back to plain text.
Future<void> copyMarkdownSelectionToClipboard(
  String selectedPlainText, {
  String? markdownSource,
}) async {
  if (selectedPlainText.trim().isEmpty) return;

  final payload = buildMarkdownClipboardPayload(
    selectedPlainText,
    markdownSource: markdownSource,
  );

  try {
    final clipboard = SystemClipboard.instance;
    if (clipboard != null && payload.htmlText.isNotEmpty) {
      final item = DataWriterItem();
      // Add the highest-fidelity representation first. Some platforms use
      // registration order when choosing a preferred clipboard flavor.
      item.add(Formats.htmlText(payload.htmlText));
      item.add(Formats.plainText(payload.plainText));
      await clipboard.write([item]);
      return;
    }
  } catch (_) {
    // Keep copying functional when the native rich clipboard is unavailable.
  }

  await Clipboard.setData(ClipboardData(text: payload.plainText));
}
