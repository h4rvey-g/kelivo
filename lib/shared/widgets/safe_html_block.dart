import 'package:csslib/parser.dart' as css_parser;
import 'package:csslib/visitor.dart' as css_ast;
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:gpt_markdown/custom_widgets/markdown_config.dart'
    show GptMarkdownConfig;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'markdown_line_lexer.dart';

const int _maxSafeHtmlSourceLength = 128 * 1024;

/// Extracts complete top-level `<div>` blocks before Markdown tokenization.
///
/// The placeholder map is registry-local, so user-authored text cannot mint a
/// token that resolves to rendered content.
final class MarkdownHtmlBlockRegistry {
  MarkdownHtmlBlockRegistry({this.enableMath = false});

  final bool enableMath;
  final Map<String, String> _blocks = {};
  final Map<String, String> _rewritten = {};
  String? _nonce;
  int _nextId = 0;

  String get placeholderSource {
    final nonce = _nonce;
    if (nonce == null) return '(?!)';
    return '\uE020${RegExp.escape(nonce)}:[0-9]+\uE021';
  }

  String rewrite(String text) {
    return _rewritten.putIfAbsent(text, () {
      _nonce ??= _nonceFor(text);
      final captures = _extract(text);
      if (captures.isEmpty) return text;

      final out = StringBuffer();
      var cursor = 0;
      for (final capture in captures) {
        out.write(text.substring(cursor, capture.start));
        final token = '\uE020$_nonce:${_nextId++}\uE021';
        _blocks[token] = capture.html;
        out.write(token);
        cursor = capture.end;
      }
      out.write(text.substring(cursor));
      return out.toString();
    });
  }

  String? lookup(String text) {
    if (_nonce == null || _blocks.isEmpty) return null;
    final match = RegExp(placeholderSource).firstMatch(text.trim());
    if (match == null) return null;
    return _blocks[match.group(0)!];
  }

  List<_HtmlCapture> _extract(String text) {
    final captures = <_HtmlCapture>[];
    final lexer = MarkdownLineLexer();
    final math = markdownScanDisplayMath(text, enableMath: enableMath);
    var topStart = -1;
    var i = 0;

    while (i < text.length) {
      var lineEnd = i;
      while (lineEnd < text.length &&
          !markdownIsLogicalLineBreak(text.codeUnitAt(lineEnd))) {
        lineEnd++;
      }
      final raw = text.substring(i, lineEnd);
      final indent = raw.length - raw.trimLeft().length;
      final trimmed = raw.substring(indent);
      final candidateOffset = i + indent;
      final inMath = lexer.htmlDivDepth == 0 && math.contains(candidateOffset);

      if (!inMath &&
          !lexer.fenced &&
          lexer.detailsDepth == 0 &&
          lexer.htmlDivDepth == 0 &&
          MarkdownHtmlDivWalker.open.matchAsPrefix(trimmed) != null) {
        topStart = i;
      }

      if (!inMath) lexer.consumeLine(raw);
      if (topStart >= 0 &&
          lexer.htmlDivDepth == 0 &&
          lexer.htmlDivClosedAt != null) {
        final htmlEnd = i + indent + lexer.htmlDivClosedAt!;
        final boundary = _blockBoundaryEnd(text, htmlEnd);
        if (boundary >= 0 && htmlEnd - topStart <= _maxSafeHtmlSourceLength) {
          captures.add(
            _HtmlCapture(
              start: topStart,
              end: boundary,
              html: text.substring(topStart, htmlEnd).trimLeft(),
            ),
          );
        }
        topStart = -1;
      }

      i = _skipLineBreak(text, lineEnd);
    }
    return captures;
  }

  static int _blockBoundaryEnd(String text, int end) {
    var i = end;
    while (i < text.length) {
      final unit = text.codeUnitAt(i);
      if (unit == 0x20 || unit == 0x09) {
        i++;
        continue;
      }
      return markdownIsLogicalLineBreak(unit) ? i : -1;
    }
    return i;
  }

  static int _skipLineBreak(String text, int offset) {
    if (offset >= text.length) return offset;
    final first = text.codeUnitAt(offset);
    if (first == 0x0D &&
        offset + 1 < text.length &&
        text.codeUnitAt(offset + 1) == 0x0A) {
      return offset + 2;
    }
    return offset + 1;
  }

  static String _nonceFor(String text) {
    var nonce = 0;
    while (text.contains('\uE020$nonce:')) {
      nonce++;
    }
    return '$nonce';
  }
}

final class _HtmlCapture {
  const _HtmlCapture({
    required this.start,
    required this.end,
    required this.html,
  });

  final int start;
  final int end;
  final String html;
}

/// Renders registry-issued blocks after reducing them to Kelivo's safe HTML
/// dialect. The package renderer never receives the original model output.
final class SafeHtmlBlockMd extends BlockMd {
  SafeHtmlBlockMd(this.registry);

  final MarkdownHtmlBlockRegistry registry;

  @override
  String get expString => registry.placeholderSource;

  @override
  Widget build(BuildContext context, String text, GptMarkdownConfig config) {
    final html = registry.lookup(text);
    if (html == null || html.length > _maxSafeHtmlSourceLength) {
      return const SizedBox.shrink();
    }

    final sanitized = _SafeHtmlSanitizer().sanitize(
      html_parser.parseFragment(html),
    );
    if (sanitized.html.trim().isEmpty) return const SizedBox.shrink();

    Widget child = HtmlWidget(
      sanitized.html,
      buildAsync: false,
      enableCaching: true,
      factoryBuilder: _SafeHtmlWidgetFactory.new,
      onTapUrl: config.onLinkTap == null
          ? null
          : (url) {
              config.onLinkTap!(url, sanitized.linkLabels[url] ?? '');
              return true;
            },
      textStyle: config.style ?? DefaultTextStyle.of(context).style,
    );

    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery != null && config.textScaler != null) {
      child = MediaQuery(
        data: mediaQuery.copyWith(textScaler: config.textScaler),
        child: child,
      );
    }

    return SizedBox(
      key: const ValueKey('markdown-safe-html-block'),
      width: double.infinity,
      child: Directionality(textDirection: config.textDirection, child: child),
    );
  }
}

const _flexWrapAttribute = 'data-kelivo-flex-wrap';
const _columnGapAttribute = 'data-kelivo-column-gap';
const _rowGapAttribute = 'data-kelivo-row-gap';

final class _SafeHtmlWidgetFactory extends WidgetFactory {
  @override
  Widget? buildFlex(
    BuildTree tree,
    List<Widget> children, {
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
    required Axis direction,
    MainAxisAlignment mainAxisAlignment = MainAxisAlignment.start,
    double spacing = 0.0,
    TextBaseline textBaseline = TextBaseline.alphabetic,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    if (tree.element.attributes[_flexWrapAttribute] != 'wrap') {
      return super.buildFlex(
        tree,
        children,
        crossAxisAlignment: crossAxisAlignment,
        direction: direction,
        mainAxisAlignment: mainAxisAlignment,
        spacing: spacing,
        textBaseline: textBaseline,
        textDirection: textDirection,
      );
    }

    final columnGap =
        double.tryParse(tree.element.attributes[_columnGapAttribute] ?? '') ??
        spacing;
    final rowGap =
        double.tryParse(tree.element.attributes[_rowGapAttribute] ?? '') ??
        spacing;

    return Wrap(
      direction: direction,
      alignment: _wrapAlignment(mainAxisAlignment),
      spacing: direction == Axis.horizontal ? columnGap : rowGap,
      runSpacing: direction == Axis.horizontal ? rowGap : columnGap,
      crossAxisAlignment: _wrapCrossAlignment(crossAxisAlignment),
      textDirection: textDirection,
      children: children,
    );
  }

  static WrapAlignment _wrapAlignment(MainAxisAlignment alignment) {
    return switch (alignment) {
      MainAxisAlignment.start => WrapAlignment.start,
      MainAxisAlignment.end => WrapAlignment.end,
      MainAxisAlignment.center => WrapAlignment.center,
      MainAxisAlignment.spaceBetween => WrapAlignment.spaceBetween,
      MainAxisAlignment.spaceAround => WrapAlignment.spaceAround,
      MainAxisAlignment.spaceEvenly => WrapAlignment.spaceEvenly,
    };
  }

  static WrapCrossAlignment _wrapCrossAlignment(CrossAxisAlignment alignment) {
    return switch (alignment) {
      CrossAxisAlignment.start => WrapCrossAlignment.start,
      CrossAxisAlignment.end => WrapCrossAlignment.end,
      CrossAxisAlignment.center => WrapCrossAlignment.center,
      CrossAxisAlignment.stretch => WrapCrossAlignment.start,
      CrossAxisAlignment.baseline => WrapCrossAlignment.center,
    };
  }
}

final class _SafeHtmlSanitizer {
  static const _maxDepth = 32;
  static const _maxNodes = 1200;

  static const _hiddenTags = {
    'script',
    'style',
    'iframe',
    'object',
    'embed',
    'applet',
    'frame',
    'frameset',
    'template',
    'noscript',
    'link',
    'meta',
    'base',
    'form',
    'input',
    'button',
    'textarea',
    'select',
    'option',
    'video',
    'audio',
    'canvas',
    'svg',
    'math',
  };

  static const _allowedTags = {
    'a',
    'abbr',
    'article',
    'aside',
    'b',
    'blockquote',
    'br',
    'cite',
    'code',
    'del',
    'div',
    'em',
    'footer',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'header',
    'hr',
    'i',
    'kbd',
    'li',
    'main',
    'mark',
    'nav',
    'ol',
    'p',
    's',
    'section',
    'small',
    'span',
    'strong',
    'sub',
    'sup',
    'u',
    'ul',
  };

  int _visitedNodes = 0;
  final Map<String, String> _linkLabels = {};

  _SanitizedHtml sanitize(dom.DocumentFragment source) {
    final fragment = dom.DocumentFragment();
    fragment.nodes.addAll(_sanitizeNodes(source.nodes, depth: 0));
    return _SanitizedHtml(
      html: fragment.outerHtml,
      linkLabels: Map.unmodifiable(_linkLabels),
    );
  }

  List<dom.Node> _sanitizeNodes(List<dom.Node> nodes, {required int depth}) {
    if (depth > _maxDepth || _visitedNodes >= _maxNodes) return const [];
    final cleanNodes = <dom.Node>[];

    for (final node in nodes) {
      if (++_visitedNodes > _maxNodes) break;
      if (node is dom.Text) {
        cleanNodes.add(dom.Text(node.data));
        continue;
      }
      if (node is! dom.Element) continue;

      final tag = (node.localName ?? '').toLowerCase();
      if (_hiddenTags.contains(tag)) continue;
      final children = _sanitizeNodes(node.nodes, depth: depth + 1);
      if (!_allowedTags.contains(tag)) {
        cleanNodes.addAll(children);
        continue;
      }

      final clean = dom.Element.tag(tag)..nodes.addAll(children);
      final style = _sanitizeStyle(node.attributes['style']);
      if (style.css.isNotEmpty) clean.attributes['style'] = style.css;
      if (style.displayFlex && style.flexWrap) {
        clean.attributes[_flexWrapAttribute] = 'wrap';
        clean.attributes[_columnGapAttribute] = '${style.columnGap ?? 0}';
        clean.attributes[_rowGapAttribute] = '${style.rowGap ?? 0}';
      }

      if (tag == 'a') {
        final href = _safeHref(node.attributes['href']);
        if (href != null) {
          clean.attributes['href'] = href;
          _linkLabels.putIfAbsent(href, () => clean.text);
        }
      }
      cleanNodes.add(clean);
    }
    return cleanNodes;
  }
}

final class _SanitizedHtml {
  const _SanitizedHtml({required this.html, required this.linkLabels});

  final String html;
  final Map<String, String> linkLabels;
}

final class _SanitizedStyle {
  const _SanitizedStyle({
    required this.css,
    required this.displayFlex,
    required this.flexWrap,
    required this.columnGap,
    required this.rowGap,
  });

  final String css;
  final bool displayFlex;
  final bool flexWrap;
  final double? columnGap;
  final double? rowGap;
}

_SanitizedStyle _sanitizeStyle(String? source) {
  final declarations = _parseCssDeclarations(source);
  if (declarations.isEmpty) {
    return const _SanitizedStyle(
      css: '',
      displayFlex: false,
      flexWrap: false,
      columnGap: null,
      rowGap: null,
    );
  }

  final clean = <String, String>{};
  final display = declarations['display']?.trim().toLowerCase();
  final displayFlex = display == 'flex' || display == 'inline-flex';
  if (displayFlex) {
    clean['display'] = 'flex';
  } else if (const {
    'block',
    'inline',
    'inline-block',
    'none',
  }.contains(display)) {
    clean['display'] = display!;
  }

  _copyBox(clean, declarations, 'padding', max: 96);
  _copyBox(clean, declarations, 'margin', max: 96);
  _copyColor(clean, declarations, 'color');
  final background =
      declarations['background-color'] ?? declarations['background'];
  final backgroundColor = _color(background);
  if (backgroundColor != null) {
    clean['background-color'] = _cssColor(backgroundColor);
  }

  final border = _sanitizeBorder(declarations['border']);
  if (border != null) clean['border'] = border;
  _copyLength(clean, declarations, 'border-radius', max: 64);

  final gap = _length(declarations['gap'], max: 64);
  final columnGap = _length(declarations['column-gap'], max: 64) ?? gap;
  final rowGap = _length(declarations['row-gap'], max: 64) ?? gap;
  if (gap != null) clean['gap'] = '${gap}px';

  _copyKeyword(clean, declarations, 'flex-direction', const {'row', 'column'});
  _copyKeyword(clean, declarations, 'justify-content', const {
    'flex-start',
    'flex-end',
    'center',
    'space-between',
    'space-around',
    'space-evenly',
  });
  _copyKeyword(clean, declarations, 'align-items', const {
    'flex-start',
    'flex-end',
    'center',
    'baseline',
    'stretch',
  });

  final fontWeight = _sanitizeFontWeight(declarations['font-weight']);
  if (fontWeight != null) clean['font-weight'] = fontWeight;
  _copyKeyword(clean, declarations, 'font-style', const {'normal', 'italic'});
  _copyLength(clean, declarations, 'font-size', min: 8, max: 72);

  final lineHeight = _lineHeight(declarations['line-height']);
  if (lineHeight != null) clean['line-height'] = '$lineHeight';
  final decoration = _sanitizeTextDecoration(declarations['text-decoration']);
  if (decoration != null) clean['text-decoration'] = decoration;

  final flexWrap = declarations['flex-wrap']?.trim().toLowerCase() == 'wrap';
  return _SanitizedStyle(
    css: clean.entries.map((entry) => '${entry.key}:${entry.value}').join(';'),
    displayFlex: displayFlex,
    flexWrap: flexWrap,
    columnGap: columnGap,
    rowGap: rowGap,
  );
}

Map<String, String> _parseCssDeclarations(String? source) {
  if (source == null || source.trim().isEmpty || source.length > 4096) {
    return const {};
  }
  try {
    final sheet = css_parser.parse('.kelivo-html{$source}');
    final rules = sheet.topLevels.whereType<css_ast.RuleSet>();
    if (rules.isEmpty) return const {};
    final result = <String, String>{};
    for (final node in rules.first.declarationGroup.declarations) {
      if (node is! css_ast.Declaration || node.expression == null) continue;
      final printer = css_ast.CssPrinter();
      node.expression!.visit(printer);
      final value = printer.toString().trim();
      if (value.isEmpty) continue;
      result[node.property.toLowerCase()] = value;
    }
    return result;
  } catch (_) {
    return const {};
  }
}

void _copyBox(
  Map<String, String> clean,
  Map<String, String> declarations,
  String property, {
  required double max,
}) {
  final shorthand = declarations[property]
      ?.trim()
      .split(RegExp(r'\s+'))
      .map((value) => _length(value, max: max))
      .toList();
  if (shorthand != null &&
      shorthand.isNotEmpty &&
      shorthand.length <= 4 &&
      shorthand.every((value) => value != null)) {
    clean[property] = shorthand.map((value) => '${value!}px').join(' ');
  }
  for (final side in const ['top', 'right', 'bottom', 'left']) {
    _copyLength(clean, declarations, '$property-$side', max: max);
  }
}

void _copyLength(
  Map<String, String> clean,
  Map<String, String> declarations,
  String property, {
  double min = 0,
  required double max,
}) {
  final value = _length(declarations[property], min: min, max: max);
  if (value != null) clean[property] = '${value}px';
}

void _copyColor(
  Map<String, String> clean,
  Map<String, String> declarations,
  String property,
) {
  final value = _color(declarations[property]);
  if (value != null) clean[property] = _cssColor(value);
}

void _copyKeyword(
  Map<String, String> clean,
  Map<String, String> declarations,
  String property,
  Set<String> allowed,
) {
  final value = declarations[property]?.trim().toLowerCase();
  if (value != null && allowed.contains(value)) clean[property] = value;
}

double? _length(String? raw, {double min = 0, required double max}) {
  if (raw == null) return null;
  final match = RegExp(
    r'^(-?(?:\d+(?:\.\d+)?|\.\d+))(?:px)?$',
    caseSensitive: false,
  ).firstMatch(raw.trim());
  final value = double.tryParse(match?.group(1) ?? '');
  if (value == null || !value.isFinite) return null;
  return value.clamp(min, max).toDouble();
}

String? _sanitizeBorder(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parts = raw.trim().split(RegExp(r'\s+'));
  if (parts.any((part) => part.toLowerCase() == 'none')) return 'none';
  final width = parts
      .map((part) => _length(part, max: 8))
      .whereType<double>()
      .firstOrNull;
  if (width == null || width <= 0) return null;
  final color =
      parts.map(_color).whereType<Color>().firstOrNull ??
      const Color(0xFF808080);
  final style = parts
      .map((part) => part.toLowerCase())
      .where(const {'solid', 'dashed', 'dotted', 'double'}.contains)
      .firstOrNull;
  return '${width}px ${style ?? 'solid'} ${_cssColor(color)}';
}

Color? _color(String? raw) {
  if (raw == null) return null;
  final value = raw.trim().toLowerCase();
  if (value == 'transparent') return Colors.transparent;
  const named = <String, Color>{
    'black': Color(0xFF000000),
    'white': Color(0xFFFFFFFF),
    'red': Color(0xFFFF0000),
    'green': Color(0xFF008000),
    'blue': Color(0xFF0000FF),
    'gray': Color(0xFF808080),
    'grey': Color(0xFF808080),
    'yellow': Color(0xFFFFFF00),
    'orange': Color(0xFFFFA500),
    'purple': Color(0xFF800080),
  };
  if (named.containsKey(value)) return named[value];
  if (value.startsWith('#')) {
    var hex = value.substring(1);
    final originalLength = hex.length;
    if (hex.length == 3 || hex.length == 4) {
      hex = hex.split('').map((char) => '$char$char').join();
    }
    if (hex.length == 6) hex = 'ff$hex';
    if (hex.length == 8 && (originalLength == 4 || originalLength == 8)) {
      hex = '${hex.substring(6)}${hex.substring(0, 6)}';
    }
    final number = int.tryParse(hex, radix: 16);
    return number == null ? null : Color(number);
  }
  final match = RegExp(
    r'^rgba?\(\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)(?:\s*,\s*(\d*(?:\.\d+)?))?\s*\)$',
  ).firstMatch(value);
  if (match == null) return null;
  final red = (double.tryParse(match.group(1)!) ?? 0).clamp(0, 255).round();
  final green = (double.tryParse(match.group(2)!) ?? 0).clamp(0, 255).round();
  final blue = (double.tryParse(match.group(3)!) ?? 0).clamp(0, 255).round();
  final alpha = (double.tryParse(match.group(4) ?? '1') ?? 1).clamp(0, 1);
  return Color.fromRGBO(red, green, blue, alpha.toDouble());
}

String _cssColor(Color color) {
  final argb = color.toARGB32();
  final alpha = (argb >> 24) & 0xFF;
  final red = (argb >> 16) & 0xFF;
  final green = (argb >> 8) & 0xFF;
  final blue = argb & 0xFF;
  if (alpha == 0xFF) {
    return '#${red.toRadixString(16).padLeft(2, '0')}'
        '${green.toRadixString(16).padLeft(2, '0')}'
        '${blue.toRadixString(16).padLeft(2, '0')}';
  }
  final opacity = (alpha / 255).toStringAsFixed(3);
  return 'rgba($red,$green,$blue,$opacity)';
}

String? _sanitizeFontWeight(String? raw) {
  final value = raw?.trim().toLowerCase();
  if (value == 'normal') return 'normal';
  if (value == 'bold' || value == 'bolder') return 'bold';
  final numeric = int.tryParse(value ?? '');
  if (numeric == null) return null;
  return '${(numeric.clamp(100, 900) ~/ 100) * 100}';
}

double? _lineHeight(String? raw) {
  if (raw == null) return null;
  final value = double.tryParse(raw.trim());
  if (value == null || !value.isFinite) return null;
  return value.clamp(0.8, 3).toDouble();
}

String? _sanitizeTextDecoration(String? raw) {
  final value = raw?.toLowerCase() ?? '';
  if (value.contains('underline')) return 'underline';
  if (value.contains('line-through')) return 'line-through';
  if (value.trim() == 'none') return 'none';
  return null;
}

String? _safeHref(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  if (!uri.hasScheme) return value.startsWith('#') ? value : null;
  return const {'http', 'https', 'mailto'}.contains(uri.scheme.toLowerCase())
      ? value
      : null;
}
