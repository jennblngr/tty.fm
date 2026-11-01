import 'package:flutter/material.dart';

import '../theme.dart';

// Small building blocks of the terminal look: "$ command" headers,
// "// comments", "[bracket]" links and "[████░░]" meters.

/// Page header: "$ command" and an optional "// comment" line.
class TtyPrompt extends StatelessWidget {
  const TtyPrompt(this.command, {super.key, this.comment, this.trailing});
  final String command;
  final String? comment;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    final style = Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w400);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '\$ ',
                      style: TextStyle(color: c.green),
                    ),
                    TextSpan(text: command),
                  ],
                ),
                style: style,
              ),
              if (comment != null) Comment(comment!),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Muted "// text".
class Comment extends StatelessWidget {
  const Comment(this.text, {super.key, this.maxLines});
  final String text;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Text(
    '// $text',
    maxLines: maxLines,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
    style: TextStyle(color: Tty.of(context).muted),
  );
}

/// Section title with a coloured glyph ("↺ écouté récemment"), an optional
/// muted comment and trailing links. [ruled] draws the thin line under it.
class TtySection extends StatelessWidget {
  const TtySection(this.title, {super.key, this.glyph, this.color, this.comment, this.trailing, this.ruled = false});
  final String title;
  final String? glyph;
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
                if (glyph == '♥')
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
        ?trailing,
      ],
    );
    if (!ruled) return row;
    return Container(
      padding: const EdgeInsets.only(bottom: 6),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: row,
    );
  }
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

/// Text meter: "[███████░░░]" (filled part coloured).
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
          TextSpan(
            text: '█' * n,
            style: TextStyle(color: color ?? c.green),
          ),
          TextSpan(text: '░' * (cells - n)),
          TextSpan(text: ']${suffix == null ? '' : ' $suffix'}'),
        ],
      ),
    );
  }
}

/// Initials of a name for coloured tiles: "nova kid" → "nk", "faune" → "fa".
String initialsOf(String name) {
  final words = name.toLowerCase().split(RegExp(r'[\s\-_/·—]+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.characters.take(2).toString();
  return '${words[0].characters.first}${words[1].characters.first}';
}

/// Coloured square with initials (or a glyph), the design's stand-in for art.
class InitialsTile extends StatelessWidget {
  const InitialsTile(this.label, {super.key, this.seed = 0, this.size = 48, this.radius = 4, this.color, this.glyph});
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
          ? Icon(Icons.favorite, color: fg, size: size * 0.4)
          : Text(
              glyph ?? initialsOf(label),
              style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: (size * 0.3).clamp(11, 40)),
            ),
    );
  }
}

/// One line of a terminal list: leading tile, coloured title, "// subtitle",
/// trailing bits. Used for tracks, albums and playlists alike.
class TtyRow extends StatelessWidget {
  const TtyRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.titleColor,
    this.onTap,
    this.bold = false,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final Color? titleColor;
  final VoidCallback? onTap;
  final bool bold;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 4 : 6),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: titleColor ?? c.text, fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
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

/// Unicode mini bars ("▂▅▇▃▆") derived from a seed: a decorative signature
/// for tiles, stable for a given item.
String sparkline(int seed, {int length = 6}) {
  const bars = '▁▂▃▄▅▆▇';
  var x = seed * 2654435761 & 0x7fffffff;
  final out = StringBuffer();
  for (var i = 0; i < length; i++) {
    x = (x * 1103515245 + 12345) & 0x7fffffff;
    out.write(bars[x % bars.length]);
  }
  return out.toString();
}

/// Scrollable page body with the design's margins (wider on desktop).
class TtyPage extends StatelessWidget {
  const TtyPage({super.key, required this.children, this.onRefresh, this.gap = 28});
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final list = ListView.separated(
      padding: wide ? const EdgeInsets.fromLTRB(32, 24, 32, 32) : const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: children.length,
      separatorBuilder: (_, _) => SizedBox(height: gap),
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
String greeting() => DateTime.now().hour >= 18 || DateTime.now().hour < 5 ? 'bonsoir' : 'bonjour';

/// Like marker. An icon rather than "♥": Android draws that character as a
/// colour emoji whatever the font.
class HeartIcon extends StatelessWidget {
  const HeartIcon(this.filled, {super.key, this.size = 16, this.color});
  final bool filled;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    return Icon(
      filled ? Icons.favorite : Icons.favorite_border,
      size: size,
      color: color ?? (filled ? c.red : c.muted),
    );
  }
}
