import 'dart:async';

import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

/// Converts a Markdown snippet to a minimal well-formed HTML string suitable
/// for placing on the system clipboard alongside a plain-text version.
///
/// Only the subset of Markdown commonly produced by AI responses is handled:
///   • ATX headings  (#, ##, ###)
///   • Unordered lists (- / * / +)
///   • Ordered lists  (1. 2. 3.)
///   • Bold  **text** or __text__
///   • Italic  *text* or _text_
///   • Inline code  `code`
///   • Horizontal rules  (--- / ***)
///   • Blockquotes  (> text)
///   • Fenced code blocks  (``` … ```)
///   • Bare line breaks / paragraphs
///
/// Anything else is left as-is in a <p> or inline text node, which is safe
/// enough for clipboard consumers.
String markdownSelectionToHtml(String markdown) {
  if (markdown.trim().isEmpty) return '';

  final lines = markdown.split('\n');
  final buf = StringBuffer();

  // State for multi-line constructs.
  bool inFencedCode = false;
  String fencedLang = '';
  final codeLines = <String>[];

  // Ordered / unordered list state.
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

  String htmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// Apply inline spans: bold, italic, inline code.
  /// Order matters: code first (suppresses further parsing inside backticks).
  String applyInline(String s) {
    // Inline code – preserve content literally.
    final codeRe = RegExp(r'`([^`]+)`');
    s = s.replaceAllMapped(
      codeRe,
      (m) => '<code>${htmlEscape(m.group(1)!)}</code>',
    );

    // Bold (**text** or __text__).
    final boldRe = RegExp(r'(\*\*|__)(.+?)\1');
    s = s.replaceAllMapped(boldRe, (m) => '<strong>${m.group(2)!}</strong>');

    // Italic (*text* or _text_).
    final italicRe = RegExp(r'(\*|_)(.+?)\1');
    s = s.replaceAllMapped(italicRe, (m) => '<em>${m.group(2)!}</em>');

    return s;
  }

  for (int i = 0; i < lines.length; i++) {
    final raw = lines[i];

    // ── Fenced code block handling ──────────────────────────────────────────
    if (!inFencedCode) {
      final fenceStart = RegExp(r'^(`{3,}|~{3,})(.*)$');
      final fm = fenceStart.firstMatch(raw);
      if (fm != null) {
        flushLists();
        inFencedCode = true;
        fencedLang = fm.group(2)!.trim();
        codeLines.clear();
        continue;
      }
    } else {
      final fenceEnd = RegExp(r'^(`{3,}|~{3,})\s*$');
      if (fenceEnd.hasMatch(raw)) {
        final langAttr =
            fencedLang.isNotEmpty ? ' class="language-$fencedLang"' : '';
        buf.write(
          '<pre><code$langAttr>${htmlEscape(codeLines.join('\n'))}</code></pre>',
        );
        inFencedCode = false;
        fencedLang = '';
        codeLines.clear();
        continue;
      }
      codeLines.add(raw);
      continue;
    }

    // ── Blank line ───────────────────────────────────────────────────────────
    if (raw.trim().isEmpty) {
      flushLists();
      continue;
    }

    // ── ATX Heading ──────────────────────────────────────────────────────────
    final headingRe = RegExp(r'^(#{1,6})\s+(.+)$');
    final hm = headingRe.firstMatch(raw);
    if (hm != null) {
      flushLists();
      final level = hm.group(1)!.length;
      final text = applyInline(htmlEscape(hm.group(2)!.trim()));
      buf.write('<h$level>$text</h$level>');
      continue;
    }

    // ── Horizontal rule ──────────────────────────────────────────────────────
    if (RegExp(r'^[-*_]{3,}\s*$').hasMatch(raw)) {
      flushLists();
      buf.write('<hr>');
      continue;
    }

    // ── Blockquote ───────────────────────────────────────────────────────────
    final bqRe = RegExp(r'^>\s?(.*)$');
    final bq = bqRe.firstMatch(raw);
    if (bq != null) {
      flushLists();
      final text = applyInline(htmlEscape(bq.group(1)!));
      buf.write('<blockquote><p>$text</p></blockquote>');
      continue;
    }

    // ── Unordered list ───────────────────────────────────────────────────────
    final ulRe = RegExp(r'^[-*+]\s+(.+)$');
    final ul = ulRe.firstMatch(raw);
    if (ul != null) {
      if (inOl) {
        buf.write('</ol>');
        inOl = false;
      }
      if (!inUl) {
        buf.write('<ul>');
        inUl = true;
      }
      final text = applyInline(htmlEscape(ul.group(1)!));
      buf.write('<li>$text</li>');
      continue;
    }

    // ── Ordered list ─────────────────────────────────────────────────────────
    final olRe = RegExp(r'^\d+\.\s+(.+)$');
    final ol = olRe.firstMatch(raw);
    if (ol != null) {
      if (inUl) {
        buf.write('</ul>');
        inUl = false;
      }
      if (!inOl) {
        buf.write('<ol>');
        inOl = true;
      }
      final text = applyInline(htmlEscape(ol.group(1)!));
      buf.write('<li>$text</li>');
      continue;
    }

    // ── Plain paragraph line ─────────────────────────────────────────────────
    flushLists();
    final text = applyInline(htmlEscape(raw));
    buf.write('<p>$text</p>');
  }

  // Flush any trailing open structures.
  if (inFencedCode && codeLines.isNotEmpty) {
    buf.write(
      '<pre><code>${htmlEscape(codeLines.join('\n'))}</code></pre>',
    );
  }
  flushLists();

  return buf.toString();
}

/// Writes [plainText] and its HTML equivalent (derived from treating
/// [plainText] as Markdown) to the system clipboard.
///
/// Falls back to a plain-text-only write if [SystemClipboard] is unavailable
/// (e.g. during tests or on platforms where super_clipboard is not supported).
Future<void> copyMarkdownSelectionToClipboard(String plainText) async {
  if (plainText.trim().isEmpty) return;

  final htmlContent = markdownSelectionToHtml(plainText);

  try {
    final clipboard = SystemClipboard.instance;
    if (clipboard != null && htmlContent.isNotEmpty) {
      final item = DataWriterItem();
      // super_clipboard requires plainText alongside htmlText on some platforms.
      item.add(Formats.plainText(plainText));
      item.add(Formats.htmlText(htmlContent));
      await clipboard.write([item]);
      return;
    }
  } catch (_) {
    // Ignore super_clipboard errors; fall through to plain-text fallback.
  }

  // Plain-text fallback (always succeeds in tests and on unsupported platforms).
  await Clipboard.setData(ClipboardData(text: plainText));
}
