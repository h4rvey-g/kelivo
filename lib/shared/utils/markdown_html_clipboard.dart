import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

// ---------------------------------------------------------------------------
// Markdown → HTML
// ---------------------------------------------------------------------------

/// Convert a Markdown string to a minimal HTML snippet for the clipboard.
///
/// Handles the subset produced by AI responses:
///   • ATX headings  (# … ######)
///   • Unordered lists  (- / * / +)
///   • Ordered lists    (1. 2. …)
///   • Bold   **…** / __…__
///   • Italic  *…* / _…_
///   • Inline code  `…`
///   • Fenced code blocks  (``` … ```)
///   • Blockquotes  (> …)
///   • Horizontal rules  (--- / ***)
///   • Plain paragraphs
String markdownSelectionToHtml(String markdown) {
  if (markdown.trim().isEmpty) return '';

  final lines = markdown.split('\n');
  final buf = StringBuffer();

  bool inFence = false;
  String fenceLang = '';
  final codeLines = <String>[];
  bool inUl = false;
  bool inOl = false;

  void flushLists() {
    if (inUl) {
      buf.write('</ul>');
      inUl = false;
    }
    if (inOl) {
      buf.write('</ol>');
      inOl = false;
    }
  }

  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  // Inline Markdown: process code spans first using placeholders so that
  // bold/italic regexes cannot match inside already-emitted <code> content.
  String applyInline(String s) {
    final codePlaceholders = <String>[];
    s = s.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) {
      final idx = codePlaceholders.length;
      codePlaceholders.add('<code>${esc(m.group(1)!)}</code>');
      return '\x00$idx\x00'; // null-byte fences, safe as Markdown is plain text
    });
    s = s.replaceAllMapped(
      RegExp(r'(\*\*|__)(.+?)\1'),
      (m) => '<strong>${m.group(2)!}</strong>',
    );
    s = s.replaceAllMapped(
      RegExp(r'(\*|_)(.+?)\1'),
      (m) => '<em>${m.group(2)!}</em>',
    );
    // Restore code placeholders.
    for (int i = 0; i < codePlaceholders.length; i++) {
      s = s.replaceAll('\x00$i\x00', codePlaceholders[i]);
    }
    return s;
  }

  for (final raw in lines) {
    // ── Fenced code block ─────────────────────────────────────────────────
    if (!inFence) {
      final fm = RegExp(r'^(`{3,}|~{3,})(.*)$').firstMatch(raw);
      if (fm != null) {
        flushLists();
        inFence = true;
        fenceLang = fm.group(2)!.trim();
        codeLines.clear();
        continue;
      }
    } else {
      if (RegExp(r'^(`{3,}|~{3,})\s*$').hasMatch(raw)) {
        final attr = fenceLang.isNotEmpty ? ' class="language-$fenceLang"' : '';
        buf.write('<pre><code$attr>${esc(codeLines.join('\n'))}</code></pre>');
        inFence = false;
        codeLines.clear();
        continue;
      }
      codeLines.add(raw);
      continue;
    }

    // ── Blank line ────────────────────────────────────────────────────────
    if (raw.trim().isEmpty) {
      flushLists();
      continue;
    }

    // ── ATX heading ───────────────────────────────────────────────────────
    final hm = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(raw);
    if (hm != null) {
      flushLists();
      final lvl = hm.group(1)!.length;
      buf.write('<h$lvl>${applyInline(esc(hm.group(2)!.trim()))}</h$lvl>');
      continue;
    }

    // ── Horizontal rule ───────────────────────────────────────────────────
    if (RegExp(r'^[-*_]{3,}\s*$').hasMatch(raw)) {
      flushLists();
      buf.write('<hr>');
      continue;
    }

    // ── Blockquote ────────────────────────────────────────────────────────
    final bq = RegExp(r'^>\s?(.*)$').firstMatch(raw);
    if (bq != null) {
      flushLists();
      buf.write(
        '<blockquote><p>${applyInline(esc(bq.group(1)!))}</p></blockquote>',
      );
      continue;
    }

    // ── Unordered list ────────────────────────────────────────────────────
    final ul = RegExp(r'^[-*+]\s+(.+)$').firstMatch(raw);
    if (ul != null) {
      if (inOl) {
        buf.write('</ol>');
        inOl = false;
      }
      if (!inUl) {
        buf.write('<ul>');
        inUl = true;
      }
      buf.write('<li>${applyInline(esc(ul.group(1)!))}</li>');
      continue;
    }

    // ── Ordered list ──────────────────────────────────────────────────────
    final ol = RegExp(r'^(\d+)\.\s+(.+)$').firstMatch(raw);
    if (ol != null) {
      if (inUl) {
        buf.write('</ul>');
        inUl = false;
      }
      if (!inOl) {
        buf.write('<ol>');
        inOl = true;
      }
      buf.write('<li>${applyInline(esc(ol.group(2)!))}</li>');
      continue;
    }

    // ── Plain paragraph ───────────────────────────────────────────────────
    flushLists();
    buf.write('<p>${applyInline(esc(raw))}</p>');
  }

  if (inFence && codeLines.isNotEmpty) {
    buf.write('<pre><code>${esc(codeLines.join('\n'))}</code></pre>');
  }
  flushLists();
  return buf.toString();
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
    required this.marker,
    required this.contentStart,
    required this.contentEnd,
  });

  final String marker;
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

  for (final line in lines) {
    final lineLen = line.length;
    final lineStart = srcPos;

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

    // Blank line: no visible text.
    if (line.trim().isEmpty) {
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
    final hmPfx = RegExp(r'^(#{1,6}) ').firstMatch(line);
    if (hmPfx != null) {
      contentStart = hmPfx.group(0)!.length;
      _emitInlineMd(line, lineStart, contentStart, emit, inlineSpans.add);
      srcPos += lineLen + 1;
      continue;
    }

    // Unordered list: "- text" → skip "- " (bullet is not selectable text)
    final ulPfx = RegExp(r'^[-*+] ').firstMatch(line);
    if (ulPfx != null) {
      contentStart = ulPfx.group(0)!.length;
      _emitInlineMd(line, lineStart, contentStart, emit, inlineSpans.add);
      srcPos += lineLen + 1;
      continue;
    }

    // Ordered list: "1. text" → KEEP "1. " (rendered as selectable text)
    final olPfx = RegExp(r'^(\d+\.) ').firstMatch(line);
    if (olPfx != null) {
      final prefix = olPfx.group(0)!; // e.g. "1. "
      for (int i = 0; i < prefix.length; i++) {
        emit(lineStart + i, prefix[i]);
      }
      contentStart = prefix.length;
      _emitInlineMd(line, lineStart, contentStart, emit, inlineSpans.add);
      srcPos += lineLen + 1;
      continue;
    }

    // Blockquote: "> text" → skip "> "
    final bqPfx = RegExp(r'^> ?').firstMatch(line);
    if (bqPfx != null) {
      contentStart = bqPfx.group(0)!.length;
      _emitInlineMd(line, lineStart, contentStart, emit, inlineSpans.add);
      srcPos += lineLen + 1;
      continue;
    }

    // HR: no visible text.
    if (RegExp(r'^[-*_]{3,}\s*$').hasMatch(line)) {
      srcPos += lineLen + 1;
      continue;
    }

    // Plain paragraph.
    _emitInlineMd(line, lineStart, 0, emit, inlineSpans.add);
    srcPos += lineLen + 1;
  }

  return _Projection(chars.join(), indices, inlineSpans);
}

/// Emit visible characters for [line] starting at [contentStart],
/// resolving inline markup (bold, italic, inline code) and mapping each
/// character to its absolute source offset [lineStart + localOffset].
void _emitInlineMd(
  String line,
  int lineStart,
  int contentStart,
  void Function(int, String) emit,
  void Function(_InlineMarkdownSpan) emitSpan,
) {
  final content = line.substring(contentStart);
  int i = 0;

  while (i < content.length) {
    final rest = content.substring(i);

    // Inline code: `…` → emit inner content, skip backticks.
    if (rest.startsWith('`')) {
      final close = rest.indexOf('`', 1);
      if (close != -1) {
        final inner = rest.substring(1, close);
        emitSpan(
          _InlineMarkdownSpan(
            marker: '`',
            contentStart: lineStart + contentStart + i + 1,
            contentEnd: lineStart + contentStart + i + close - 1,
          ),
        );
        for (int j = 0; j < inner.length; j++) {
          emit(lineStart + contentStart + i + 1 + j, inner[j]);
        }
        i += close + 1;
        continue;
      }
    }

    // Bold: **…** or __…__
    if (rest.startsWith('**') || rest.startsWith('__')) {
      final marker = rest.substring(0, 2);
      final close = rest.indexOf(marker, 2);
      if (close != -1) {
        final inner = rest.substring(2, close);
        emitSpan(
          _InlineMarkdownSpan(
            marker: marker,
            contentStart: lineStart + contentStart + i + 2,
            contentEnd: lineStart + contentStart + i + close - 1,
          ),
        );
        for (int j = 0; j < inner.length; j++) {
          emit(lineStart + contentStart + i + 2 + j, inner[j]);
        }
        i += close + 2;
        continue;
      }
    }

    // Italic: *…* or _…_
    if (rest.startsWith('*') || rest.startsWith('_')) {
      final marker = rest[0];
      final close = rest.indexOf(marker, 1);
      if (close != -1) {
        final inner = rest.substring(1, close);
        emitSpan(
          _InlineMarkdownSpan(
            marker: marker,
            contentStart: lineStart + contentStart + i + 1,
            contentEnd: lineStart + contentStart + i + close - 1,
          ),
        );
        for (int j = 0; j < inner.length; j++) {
          emit(lineStart + contentStart + i + 1 + j, inner[j]);
        }
        i += close + 1;
        continue;
      }
    }

    // Plain character.
    emit(lineStart + contentStart + i, content[i]);
    i++;
  }
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
    if (sourceFragment.contains('\n')) return selectedPlainText;

    final openingSpans =
        proj.inlineSpans.where((span) => span.contains(srcStart)).toList()
          ..sort((a, b) => a.contentStart.compareTo(b.contentStart));
    final closingSpans =
        proj.inlineSpans.where((span) => span.contains(srcEnd)).toList()
          ..sort((a, b) => a.contentEnd.compareTo(b.contentEnd));

    return '${openingSpans.map((span) => span.marker).join()}'
        '$sourceFragment'
        '${closingSpans.map((span) => span.marker).join()}';
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
