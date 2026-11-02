import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../icons.dart';
import '../theme.dart';

// Small building blocks of the terminal look: "$ command" headers,
// "// comments", "[bracket]" links and "[████░░]" meters.

/// Page header: "[brand] $ command", trailing actions, and an optional
/// "// comment" line under it across the full width.
class TtyPrompt extends StatelessWidget {
  const TtyPrompt(this.command, {super.key, this.comment, this.commentSpans, this.trailing, this.brand});
  final String command;
  final String? comment;
  final List<InlineSpan>? commentSpans; // one line, in place of [comment]
  final Widget? trailing;
  final String? brand; // "tty.fm", in mauve before the prompt

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    // 15 px on desktop, body size (13 px) on mobile, as on the mockups.
    final text = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final style = (wide ? text.titleMedium! : text.bodyMedium!).copyWith(fontWeight: FontWeight.w400);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // As tall as a [SquareIconButton], so that the title sits at the
        // same height whether the header has icons or not.
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: wide ? 36 : 40),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (brand != null)
                        TextSpan(
                          text: '$brand ',
                          style: TextStyle(color: c.mauve),
                        ),
                      TextSpan(
                        text: '\$ ',
                        style: TextStyle(color: c.green),
                      ),
                      TextSpan(text: command),
                    ],
                  ),
                  style: style,
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        // 12 px before the comment, as on the mockups: from the title text on
        // mobile (the 40 px row already leaves ~10 px under its 19.5 px
        // line), from the row on desktop.
        if (comment != null || commentSpans != null) ...[
          SizedBox(height: wide ? 12 : 2),
          commentSpans != null ? Comment.rich(commentSpans!) : Comment(comment!),
        ],
      ],
    );
  }
}

/// Muted "// text". [Comment.rich]: on one line, spans with their own
/// colours (the home's message of the day).
class Comment extends StatelessWidget {
  const Comment(this.text, {super.key, this.maxLines}) : spans = null;
  const Comment.rich(this.spans, {super.key}) : text = '', maxLines = 1;
  final String text;
  final List<InlineSpan>? spans;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      text: '// ',
      children: spans ?? [TextSpan(text: text)],
    ),
    maxLines: maxLines,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
    style: TextStyle(color: Tty.of(context).muted),
  );
}

/// Section title with a coloured glyph ("↺ écouté récemment"), an optional
/// muted comment and trailing links. [ruled] draws the thin line under it.
/// [svg] (see icons.dart) draws the glyph for those JetBrains Mono lacks.
class TtySection extends StatelessWidget {
  const TtySection(
    this.title, {
    super.key,
    this.glyph,
    this.svg,
    this.color,
    this.comment,
    this.trailing,
    this.ruled = false,
  });
  final String title;
  final String? glyph;
  final String? svg;
  final Color? color;
  final String? comment;
  final Widget? trailing;
  final bool ruled;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                if (svg != null)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SvgPicture.string(
                        svg!,
                        width: 12,
                        height: 12,
                        colorFilter: ColorFilter.mode(color ?? c.green, BlendMode.srcIn),
                      ),
                    ),
                  )
                else if (glyph == '♥')
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: HeartIcon(true, size: 13, color: color ?? c.red),
                    ),
                  )
                else if (glyph != null)
                  TextSpan(
                    text: '$glyph ',
                    style: TextStyle(color: color ?? c.green),
                  ),
                TextSpan(text: title),
                if (comment != null)
                  TextSpan(
                    text: ' // $comment',
                    style: TextStyle(color: c.muted, fontWeight: FontWeight.w400),
                  ),
              ],
            ),
            style: const TextStyle(fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null)
          // One text line tall: the padding of a [TtyLink] overflows instead
          // of pushing the content further below the title.
          IntrinsicWidth(
            child: SizedBox(
              height: _lineHeight(context),
              child: OverflowBox(maxHeight: double.infinity, child: trailing),
            ),
          ),
      ],
    );
    if (!ruled) return row;
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: row,
    );
  }
}

double _lineHeight(BuildContext context) {
  final style = DefaultTextStyle.of(context).style;
  return (style.fontSize ?? 13) * (style.height ?? 1.5);
}

/// "[label]" link or toggle. Active: green and bold.
class TtyLink extends StatelessWidget {
  const TtyLink(this.label, {super.key, this.onTap, this.active = false, this.color, this.tooltip});
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    final link = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Text(
          '[$label]',
          style: TextStyle(
            color: color ?? (active ? c.green : c.muted),
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
    return tooltip == null ? link : Tooltip(message: tooltip, child: link);
  }
}

/// Meter "[▮▮▮▮▮▮▮▯▯▯]": filled cells coloured, empty ones in [Tty.empty].
/// Drawn rather than written with "█░", which JetBrains Mono lacks (the
/// fallback font draws them lower). 10 cells for a %, 8 for the volume.
class TtyMeter extends StatelessWidget {
  const TtyMeter(this.value, {super.key, this.cells = 10, this.color, this.suffix});
  final double value; // 0..1
  final int cells;
  final Color? color;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    final n = (value.clamp(0.0, 1.0) * cells).round();
    return Text.rich(
      TextSpan(
        style: TextStyle(color: c.muted),
        children: [
          const TextSpan(text: '['),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: MiniGraph(List.filled(n, 8) + List.filled(cells - n, 0), color: color ?? c.green, empty: c.empty),
          ),
          TextSpan(text: ']${suffix == null ? '' : ' $suffix'}'),
        ],
      ),
    );
  }
}

/// Mini bar graph sized like text: each bar is 0.6em wide (one character
/// column, 7 units of bar + 1 of gap) and the graph 0.75em high, sitting on
/// the baseline. [heights] go from 1 to 8 eighths; with [empty] set, a 0
/// draws a full cell in that colour (meters).
class MiniGraph extends StatelessWidget {
  const MiniGraph(this.heights, {super.key, this.color, this.empty, this.fontSize});
  final List<int> heights;
  final Color? color;
  final Color? empty;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final em = fontSize ?? style.fontSize ?? 13;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(0.6 * em * heights.length, 0.75 * em),
        painter: _MiniGraphPainter(heights, color ?? style.color ?? Tty.of(context).text, empty),
      ),
    );
  }
}

class _MiniGraphPainter extends CustomPainter {
  _MiniGraphPainter(this.heights, this.color, this.empty);
  final List<int> heights;
  final Color color;
  final Color? empty;

  @override
  void paint(Canvas canvas, Size size) {
    if (heights.isEmpty) return;
    // viewBox 0 0 (8n − 1) 8, stretched to the size.
    final sx = size.width / (8 * heights.length - 1);
    final sy = size.height / 8;
    final on = Paint()..color = color;
    final off = empty == null ? null : (Paint()..color = empty!);
    for (var i = 0; i < heights.length; i++) {
      final h = heights[i].clamp(0, 8);
      final paint = h == 0 ? off : on;
      if (paint == null) continue;
      final top = h == 0 ? 0 : 8 - h;
      canvas.drawRect(Rect.fromLTRB(8 * i * sx, top * sy, (8 * i + 7) * sx, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_MiniGraphPainter old) =>
      old.color != color || old.empty != empty || !_listEquals(old.heights, heights);

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// [MiniGraph] inside a [Text.rich], on the baseline.
InlineSpan miniGraphSpan(List<int> heights, {Color? color}) => WidgetSpan(
  alignment: PlaceholderAlignment.baseline,
  baseline: TextBaseline.alphabetic,
  child: MiniGraph(heights, color: color),
);

/// Initials of a name for coloured tiles: "nova kid" → "nk", "faune" → "fa".
String initialsOf(String name) {
  final words = name.toLowerCase().split(RegExp(r'[\s\-_/·—]+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.characters.take(2).toString();
  return '${words[0].characters.first}${words[1].characters.first}';
}

/// Coloured square with initials (or a glyph), the design's stand-in for art.
class InitialsTile extends StatelessWidget {
  const InitialsTile(this.label, {super.key, this.seed = 0, this.size = 48, this.radius = 6, this.color, this.glyph});
  final String label;
  final int seed;
  final double size;
  final double radius;
  final Color? color;
  final String? glyph;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    final fg = color ?? c.accentFor(seed);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.tint(fg), borderRadius: BorderRadius.circular(radius)),
      child: glyph == '♥'
          ? HeartIcon(true, color: fg, size: size * 0.3)
          : Text(
              glyph ?? initialsOf(label),
              style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: (size * 0.3).clamp(11, 40)),
            ),
    );
  }
}

/// One line of a terminal list: leading tile, coloured title, "// subtitle",
/// trailing bits. Used for tracks, albums and playlists alike. [aside] sits
/// at the end of the title line, at the top of the block, rather than
/// centred like [trailing].
class TtyRow extends StatelessWidget {
  const TtyRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.aside,
    this.titleColor,
    this.onTap,
    this.bold = false,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final Widget? aside;
  final Color? titleColor;
  final VoidCallback? onTap;
  final bool bold;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: titleColor ?? c.text, fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 4 : 8),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (aside == null)
                    titleText
                  else
                    Row(
                      children: [
                        Expanded(child: titleText),
                        const SizedBox(width: 8),
                        aside!,
                      ],
                    ),
                  if (subtitle != null) Comment(subtitle!, maxLines: 1),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

/// Rounded panel used for cards and stat boxes.
class TtyPanel extends StatelessWidget {
  const TtyPanel({super.key, required this.child, this.color, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final Color? color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(color: color ?? Tty.of(context).panel, borderRadius: BorderRadius.circular(8)),
    child: child,
  );
}

/// Bar heights (1–7 eighths) derived from a seed, for a [MiniGraph]: a
/// decorative signature for tiles, stable for a given item.
List<int> sparkline(int seed, {int length = 6}) {
  var x = seed * 2654435761 & 0x7fffffff;
  return [for (var i = 0; i < length; i++) (x = (x * 1103515245 + 12345) & 0x7fffffff) % 7 + 1];
}

/// Scrollable page body with the design's margins and gap between sections
/// (24 px on mobile, 32 px on desktop).
class TtyPage extends StatelessWidget {
  const TtyPage({super.key, required this.children, this.onRefresh, this.gap});
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final double? gap;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final list = ListView.separated(
      padding: wide ? const EdgeInsets.fromLTRB(32, 24, 32, 32) : const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: children.length,
      separatorBuilder: (_, _) => SizedBox(height: gap ?? (wide ? 32 : 24)),
      itemBuilder: (_, i) => children[i],
    );
    final body = onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list);
    return Scaffold(body: SafeArea(child: body));
  }
}

/// Lays children in as many columns of at least [minWidth] as fit.
class TtyGrid extends StatelessWidget {
  const TtyGrid({super.key, required this.children, this.minWidth = 220, this.spacing = 8, this.maxColumns = 99});
  final List<Widget> children;
  final double minWidth;
  final double spacing;
  final int maxColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final cols = ((box.maxWidth + spacing) / (minWidth + spacing)).floor().clamp(1, maxColumns);
      final w = (box.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final c in children) SizedBox(width: w, child: c)],
      );
    },
  );
}

/// "aujourd'hui", "hier", "il y a 3 j", then the date.
String relativeDay(DateTime t) {
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  if (days <= 0) return "aujourd'hui";
  if (days == 1) return 'hier';
  if (days < 30) return 'il y a $days j';
  return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year}';
}

/// "bonjour" / "bonsoir" depending on the hour.
String greeting([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  return h >= 18 || h < 5 ? 'bonsoir' : 'bonjour';
}

/// Icon button in a square box: 40×40 on mobile, 36×36 on desktop. Filled
/// icons, muted when disabled. [svg] (see icons.dart) replaces [icon] for
/// the icons drawn on the mockups.
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({
    super.key,
    this.icon,
    this.svg,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.size = 22,
    this.badge,
  }) : assert((icon == null) != (svg == null), 'icon or svg');
  final IconData? icon;
  final String? svg;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;
  final Color? badge; // small dot in the top-right corner

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    final box = MediaQuery.sizeOf(context).width >= 900 ? 36.0 : 40.0;
    final fg = onPressed == null ? c.empty : (color ?? c.text);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox.square(
          dimension: box,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (svg != null)
                SvgPicture.string(
                  svg!,
                  width: size,
                  height: size,
                  colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
                  semanticsLabel: tooltip,
                )
              else
                Icon(icon, size: size, color: fg, semanticLabel: tooltip),
              if (badge != null)
                Positioned(
                  top: box / 2 - size / 2 - 1,
                  right: box / 2 - size / 2 - 1,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: badge, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Like marker. An icon rather than "♥": Android draws that character as a
/// colour emoji whatever the font. Filled, it is the mockups' heart.
class HeartIcon extends StatelessWidget {
  const HeartIcon(this.filled, {super.key, this.size = 16, this.color});
  final bool filled;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    final fg = color ?? (filled ? c.red : c.muted);
    if (!filled) return Icon(Icons.favorite_border, size: size, color: fg);
    return SvgPicture.string(heartSvg, width: size, height: size, colorFilter: ColorFilter.mode(fg, BlendMode.srcIn));
  }
}
