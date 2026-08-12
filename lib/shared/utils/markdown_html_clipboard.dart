import 'dart:async';

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

  // Code first (suppresses bold/italic inside backticks).
  String applyInline(String s) {
    s = s.replaceAllMapped(
      RegExp(r'`([^`]+)`'),
      (m) => '<code>${esc(m.group(1)!)}</code>',
    );
    s = s.replaceAllMapped(
      RegExp(r'(\*\*|__)(.+?)\1'),
      (m) => '<strong>${m.group(2)!}</strong>',
    );
    s = s.replaceAllMapped(
      RegExp(r'(\*|_)(.+?)\1'),
      (m) => '<em>${m.group(2)!}</em>',
    );
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
        final attr =
            fenceLang.isNotEmpty ? ' class="language-$fenceLang"' : '';
        buf.write(
          '<pre><code$attr>${esc(codeLines.join('\n'))}</code></pre>',
        );
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

class _Projection {
  /// sourceIndex[i] = position in the original source string for visibleText[i]
  final List<int> sourceIndex;
  final String visibleText;

  const _Projection(this.visibleText, this.sourceIndex);
}

_Projection _buildProjection(String source) {
  final chars = <String>[];
  final indices = <int>[];

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
      _emitInlineMd(line, lineStart, contentStart, emit);
      srcPos += lineLen + 1;
      continue;
    }

    // Unordered list: "- text" → skip "- " (bullet is not selectable text)
    final ulPfx = RegExp(r'^[-*+] ').firstMatch(line);
    if (ulPfx != null) {
      contentStart = ulPfx.group(0)!.length;
      _emitInlineMd(line, lineStart, contentStart, emit);
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
      _emitInlineMd(line, lineStart, contentStart, emit);
      srcPos += lineLen + 1;
      continue;
    }

    // Blockquote: "> text" → skip "> "
    final bqPfx = RegExp(r'^> ?').firstMatch(line);
    if (bqPfx != null) {
      contentStart = bqPfx.group(0)!.length;
      _emitInlineMd(line, lineStart, contentStart, emit);
      srcPos += lineLen + 1;
      continue;
    }

    // HR: no visible text.
    if (RegExp(r'^[-*_]{3,}\s*$').hasMatch(line)) {
      srcPos += lineLen + 1;
      continue;
    }

    // Plain paragraph.
    _emitInlineMd(line, lineStart, 0, emit);
    srcPos += lineLen + 1;
  }

  return _Projection(chars.join(), indices);
}

/// Emit visible characters for [line] starting at [contentStart],
/// resolving inline markup (bold, italic, inline code) and mapping each
/// character to its absolute source offset [lineStart + localOffset].
void _emitInlineMd(
  String line,
  int lineStart,
  int contentStart,
  void Function(int, String) emit,
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
// Maps the selected rendered plain-text back to the Markdown source lines
// that produced it.
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
/// whose rendered plain-text corresponds to [selectedPlainText], extended to
/// whole-line boundaries so that [markdownSelectionToHtml] receives valid input.
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

  final selCompact = selectedPlainText.replaceAll(ws, '');
  if (selCompact.isEmpty) return selectedPlainText;

  final hit = projCompact.indexOf(selCompact);
  if (hit == -1) return selectedPlainText;

  // Map compact indices → proj.visibleText indices → source indices.
  final projStartPos = projCompactToProj[hit];
  final projEndPos = projCompactToProj[hit + selCompact.length - 1];

  final srcStart = proj.sourceIndex[projStartPos];
  final srcEnd = proj.sourceIndex[projEndPos];

  // Extend to whole Markdown line boundaries.
  int lineStart = srcStart;
  while (lineStart > 0 && markdownSource[lineStart - 1] != '\n') {
    lineStart--;
  }

  int lineEnd = srcEnd;
  while (
    lineEnd < markdownSource.length - 1 &&
    markdownSource[lineEnd + 1] != '\n'
  ) {
    lineEnd++;
  }

  return markdownSource.substring(lineStart, lineEnd + 1);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Writes [selectedPlainText] and its HTML equivalent to the system clipboard.
///
/// If [markdownSource] is provided the HTML is derived from the Markdown lines
/// that produced the selection (preserving bold, lists, headings, etc.).
/// Falls back to plain-text-only copy when super_clipboard is unavailable.
Future<void> copyMarkdownSelectionToClipboard(
  String selectedPlainText, {
  String? markdownSource,
}) async {
  if (selectedPlainText.trim().isEmpty) return;

  final markdownForHtml =
      (markdownSource != null && markdownSource.isNotEmpty)
          ? findMarkdownRangeForSelection(markdownSource, selectedPlainText)
          : selectedPlainText;

  final htmlContent = markdownSelectionToHtml(markdownForHtml);

  try {
    final clipboard = SystemClipboard.instance;
    if (clipboard != null && htmlContent.isNotEmpty) {
      final item = DataWriterItem();
      item.add(Formats.plainText(selectedPlainText));
      item.add(Formats.htmlText(htmlContent));
      await clipboard.write([item]);
      return;
    }
  } catch (_) {
    // Fall through to plain-text fallback.
  }

  await Clipboard.setData(ClipboardData(text: selectedPlainText));
}
