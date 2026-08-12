import 'dart:async';

import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

// ---------------------------------------------------------------------------
// markdownSelectionToHtml
//
// Converts a Markdown string to a minimal HTML snippet suitable for the
// system clipboard. Handles the subset produced by AI responses:
//   • ATX headings (#, ##, ###)
//   • Unordered lists  (- / * / +)
//   • Ordered lists    (1. 2. 3.)
//   • Bold             **text** or __text__
//   • Italic           *text* or _text_
//   • Inline code      `code`
//   • Fenced code blocks (``` … ```)
//   • Blockquotes      (> text)
//   • Horizontal rules (--- / ***)
//   • Plain paragraphs
// ---------------------------------------------------------------------------
String markdownSelectionToHtml(String markdown) {
  if (markdown.trim().isEmpty) return '';

  final lines = markdown.split('\n');
  final buf = StringBuffer();

  bool inFencedCode = false;
  String fencedLang = '';
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

  /// Apply inline spans — code first (suppresses bold/italic inside backticks).
  String inline(String s) {
    // Inline code: capture raw content, escape inside.
    final codeRe = RegExp(r'`([^`]+)`');
    s = s.replaceAllMapped(codeRe, (m) => '<code>${esc(m.group(1)!)}</code>');
    // Bold (**…** or __…__).
    s = s.replaceAllMapped(
      RegExp(r'(\*\*|__)(.+?)\1'),
      (m) => '<strong>${m.group(2)!}</strong>',
    );
    // Italic (*…* or _…_).
    s = s.replaceAllMapped(
      RegExp(r'(\*|_)(.+?)\1'),
      (m) => '<em>${m.group(2)!}</em>',
    );
    return s;
  }

  for (final raw in lines) {
    // ── Fenced code block ─────────────────────────────────────────────────
    if (!inFencedCode) {
      final fm = RegExp(r'^(`{3,}|~{3,})(.*)$').firstMatch(raw);
      if (fm != null) {
        flushLists();
        inFencedCode = true;
        fencedLang = fm.group(2)!.trim();
        codeLines.clear();
        continue;
      }
    } else {
      if (RegExp(r'^(`{3,}|~{3,})\s*$').hasMatch(raw)) {
        final attr = fencedLang.isNotEmpty ? ' class="language-$fencedLang"' : '';
        buf.write('<pre><code$attr>${esc(codeLines.join('\n'))}</code></pre>');
        inFencedCode = false;
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

    // ── ATX Heading ───────────────────────────────────────────────────────
    final hm = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(raw);
    if (hm != null) {
      flushLists();
      final lvl = hm.group(1)!.length;
      buf.write('<h$lvl>${inline(esc(hm.group(2)!.trim()))}</h$lvl>');
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
      buf.write('<blockquote><p>${inline(esc(bq.group(1)!))}</p></blockquote>');
      continue;
    }

    // ── Unordered list ────────────────────────────────────────────────────
    final ul = RegExp(r'^[-*+]\s+(.+)$').firstMatch(raw);
    if (ul != null) {
      if (inOl) { buf.write('</ol>'); inOl = false; }
      if (!inUl) { buf.write('<ul>'); inUl = true; }
      buf.write('<li>${inline(esc(ul.group(1)!))}</li>');
      continue;
    }

    // ── Ordered list ──────────────────────────────────────────────────────
    final ol = RegExp(r'^\d+\.\s+(.+)$').firstMatch(raw);
    if (ol != null) {
      if (inUl) { buf.write('</ul>'); inUl = false; }
      if (!inOl) { buf.write('<ol>'); inOl = true; }
      buf.write('<li>${inline(esc(ol.group(1)!))}</li>');
      continue;
    }

    // ── Plain paragraph ───────────────────────────────────────────────────
    flushLists();
    buf.write('<p>${inline(esc(raw))}</p>');
  }

  if (inFencedCode && codeLines.isNotEmpty) {
    buf.write('<pre><code>${esc(codeLines.join('\n'))}</code></pre>');
  }
  flushLists();

  return buf.toString();
}

// ---------------------------------------------------------------------------
// _renderedLineText
//
// Given a raw Markdown line, return the plain text that gpt_markdown renders
// for it — i.e., the text that ends up in the Flutter selection system.
//
// Rules match the gpt_markdown component regexes:
//   UnOrderedList : r"(?:\-|\*)\ ([^\n]+)$"   → group(1)
//   OrderedList   : r"([0-9]+)\.\ ([^\n]+)$"  → group(2)
//   HTag          : r"#{1,6}\ ([^\n]+?)$"      → group(1), then inline stripped
//   BlockQuote    : r"> ?(.*)"                 → group(1)
//   Fenced code   : rendered as non-selectable code widget (skip)
//   Everything else: the line itself minus inline markup
// ---------------------------------------------------------------------------
String _renderedLineText(String mdLine) {
  // Unordered list item: "- text" or "* text"
  final ulM = RegExp(r'^[-*+]\s+(.+)$').firstMatch(mdLine);
  if (ulM != null) return _stripInlineMarkup(ulM.group(1)!.trim());

  // Ordered list item: "1. text"
  final olM = RegExp(r'^\d+\.\s+(.+)$').firstMatch(mdLine);
  if (olM != null) return _stripInlineMarkup(olM.group(1)!.trim());

  // ATX heading: "## text"
  final hM = RegExp(r'^#{1,6}\s+(.+)$').firstMatch(mdLine);
  if (hM != null) return _stripInlineMarkup(hM.group(1)!.trim());

  // Blockquote: "> text"
  final bqM = RegExp(r'^>\s?(.*)$').firstMatch(mdLine);
  if (bqM != null) return _stripInlineMarkup(bqM.group(1)!);

  // Fenced fence line itself (``` or ~~~) → empty, skip
  if (RegExp(r'^(`{3,}|~{3,})').hasMatch(mdLine)) return '';

  // HR
  if (RegExp(r'^[-*_]{3,}\s*$').hasMatch(mdLine)) return '';

  // Plain line: strip inline markup
  return _stripInlineMarkup(mdLine);
}

/// Remove inline Markdown syntax (**bold**, *italic*, `code`, __under__)
/// to produce the visible plain text that Flutter's text engine presents.
String _stripInlineMarkup(String s) {
  // Inline code: remove backticks, keep content.
  s = s.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m.group(1)!);
  // Bold (**…** or __…__).
  s = s.replaceAllMapped(RegExp(r'(\*\*|__)(.+?)\1'), (m) => m.group(2)!);
  // Italic (*…* or _…_).
  s = s.replaceAllMapped(RegExp(r'(\*|_)(.+?)\1'), (m) => m.group(2)!);
  return s;
}

// ---------------------------------------------------------------------------
// findMarkdownLinesForSelection
//
// Given the full Markdown source and the plain text that the user selected
// (as reported by Flutter's selection system), find the contiguous Markdown
// lines that produce that selection and return them joined with '\n'.
//
// Strategy:
//  1. Build a list of (mdLine, renderedText) pairs, skipping blank lines and
//     fenced-code-block delimiters that produce no selectable text.
//  2. Build the full rendered string (joined with '\n') of all visible lines.
//  3. Find the start of selectedPlain in the rendered string.
//  4. Map the character offset range back to the list of (line, renderedText)
//     pairs to find which mdLines are covered.
//  5. Return those original mdLines joined with '\n'.
//
// If no match is found (e.g. selection spans a code block boundary or the
// text has drifted) return selectedPlain unchanged as the best we can do.
// ---------------------------------------------------------------------------
String findMarkdownLinesForSelection(String markdownSource, String selectedPlain) {
  if (selectedPlain.trim().isEmpty) return selectedPlain;

  final srcLines = markdownSource.split('\n');

  // Build (originalLine, renderedText) skipping empties and fence markers.
  final rendered = <({String md, String text})>[];
  bool inCode = false;
  for (final line in srcLines) {
    if (!inCode && RegExp(r'^(`{3,}|~{3,})').hasMatch(line)) {
      inCode = true;
      // Fence opener: not selectable, add a placeholder so the code content
      // lines are also excluded (they render inside a non-selectable widget).
      continue;
    }
    if (inCode) {
      if (RegExp(r'^(`{3,}|~{3,})\s*$').hasMatch(line)) {
        inCode = false;
      }
      // Lines inside fenced blocks are not selectable as text.
      continue;
    }
    final t = _renderedLineText(line);
    if (t.isEmpty && line.trim().isEmpty) continue; // blank separator
    rendered.add((md: line, text: t));
  }

  if (rendered.isEmpty) return selectedPlain;

  // Build the joined rendered text (lines separated by '\n') and search.
  final joinedRendered = rendered.map((e) => e.text).join('\n');

  // Normalise both sides: collapse runs of whitespace/newlines so minor
  // differences in whitespace handling don't break the match.
  String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  final normSelected = norm(selectedPlain);
  final normJoined = norm(joinedRendered);

  final startIdx = normJoined.indexOf(normSelected);
  if (startIdx == -1) {
    // Fallback: couldn't match — return the original selected plain text so
    // the plain-text fallback path in copyMarkdownSelectionToClipboard is used.
    return selectedPlain;
  }

  // Map character offset back to line indices.
  // Build cumulative lengths in normJoined per rendered entry.
  int pos = 0;
  int firstLine = -1;
  int lastLine = -1;
  final endIdx = startIdx + normSelected.length;

  for (int i = 0; i < rendered.length; i++) {
    final lineNorm = norm(rendered[i].text);
    final lineEnd = pos + lineNorm.length;

    if (firstLine == -1 && lineEnd > startIdx) firstLine = i;
    if (lineEnd >= endIdx) {
      lastLine = i;
      break;
    }

    pos = lineEnd + 1; // +1 for the '\n' separator
  }

  if (firstLine == -1) return selectedPlain;
  if (lastLine == -1) lastLine = rendered.length - 1;

  return rendered
      .sublist(firstLine, lastLine + 1)
      .map((e) => e.md)
      .join('\n');
}

// ---------------------------------------------------------------------------
// copyMarkdownSelectionToClipboard
//
// Writes [selectedPlainText] plus its HTML equivalent to the system clipboard.
// If [markdownSource] is provided, the HTML is derived from the Markdown lines
// that correspond to the selection (preserving bold, lists, headings, etc.).
// Falls back to plain-text-only copy if super_clipboard is unavailable.
// ---------------------------------------------------------------------------
Future<void> copyMarkdownSelectionToClipboard(
  String selectedPlainText, {
  String? markdownSource,
}) async {
  if (selectedPlainText.trim().isEmpty) return;

  // Resolve which Markdown lines the selection covers.
  final markdownForHtml = (markdownSource != null && markdownSource.isNotEmpty)
      ? findMarkdownLinesForSelection(markdownSource, selectedPlainText)
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
