import 'dart:math';

import 'package:material_ui/material_ui.dart';

import 'package:last_card_core/cards.dart';

import 'theme.dart';

const cardAspect = 1.45;

/// Renders a single card face, or the card back when [face] is null.
class PlayingCard extends StatelessWidget {
  const PlayingCard({
    super.key,
    this.face,
    this.width = 72,
    this.dimmed = false,
    this.glow,
    this.wildColors = CardColor.light,
  });

  final CardFace? face;
  final double width;
  final bool dimmed;
  final Color? glow;

  /// Colors drawn on wild cards (light or dark side).
  final List<CardColor> wildColors;

  @override
  Widget build(BuildContext context) {
    final h = width * cardAspect;
    final r = width * 0.13;
    final f = face;
    final compact = width < 44;
    return Container(
      width: width,
      height: h,
      padding: EdgeInsets.all(width * (compact ? 0.06 : 0.05)),
      decoration: BoxDecoration(
        color: Palette.cardWhite,
        borderRadius: BorderRadius.circular(r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: width * 0.08,
            offset: Offset(0, width * 0.04),
          ),
          if (glow != null)
            BoxShadow(color: glow!, blurRadius: width * 0.28, spreadRadius: 1),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r * 0.7),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (f == null)
              _Back(width: width)
            else
              _Face(face: f, width: width, compact: compact, wilds: wildColors),
            // Unplayable: darkened on the dark table, faded on the light one.
            if (dimmed)
              ColoredBox(
                color: Palette.dark
                    ? Colors.black.withValues(alpha: 0.42)
                    : Colors.white.withValues(alpha: 0.55),
              ),
          ],
        ),
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({
    required this.face,
    required this.width,
    required this.compact,
    required this.wilds,
  });

  final CardFace face;
  final double width;
  final bool compact;
  final List<CardColor> wilds;

  @override
  Widget build(BuildContext context) {
    final bg = Palette.of(face.color);
    final center = _glyph(face, width * (compact ? 0.42 : 0.46));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        gradient: face.isWild
            ? null
            : RadialGradient(
                colors: [Color.lerp(bg, Colors.white, 0.18)!, bg],
                radius: 0.75,
              ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (face.isWild)
            SizedBox.square(
              dimension: width * (face.kind == CardKind.wild ? 0.62 : 0.5),
              child: CustomPaint(painter: _PinwheelPainter(wilds)),
            ),
          if (face.kind != CardKind.wild) center,
          if (!compact) ...[
            Positioned(
              left: width * 0.07,
              top: width * 0.04,
              child: _glyph(face, width * 0.17, corner: true),
            ),
            Positioned(
              right: width * 0.07,
              bottom: width * 0.04,
              child: RotatedBox(
                quarterTurns: 2,
                child: _glyph(face, width * 0.17, corner: true),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _glyph(CardFace f, double size, {bool corner = false}) {
    final shadow = [
      Shadow(
        color: Colors.black.withValues(alpha: corner ? 0.25 : 0.42),
        offset: Offset(size * 0.04, size * 0.06),
      ),
    ];
    Widget text(String s, {double scale = 1}) => Text(
      s,
      textAlign: TextAlign.center,
      style: font(size * scale, weight: 700, color: Colors.white, height: 1)
          .copyWith(
            shadows: shadow,
            letterSpacing: -size * 0.03,
            decoration:
                f.kind == CardKind.number && (f.value == 6 || f.value == 9)
                ? TextDecoration.underline
                : null,
            decorationColor: Colors.white,
            decorationThickness: 2.2,
          ),
    );
    Widget icon(IconData i, {double scale = 0.9}) =>
        Icon(i, size: size * scale, color: Colors.white, shadows: shadow);

    return switch (f.kind) {
      CardKind.number => text('${f.value}', scale: corner ? 1 : 1.15),
      CardKind.draw || CardKind.wildDraw => text('+${f.draw}', scale: 0.82),
      CardKind.wildReverseDraw =>
        corner
            ? text('+${f.draw}', scale: 0.8)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  text('+${f.draw}', scale: 0.78),
                  icon(Icons.sync_alt_rounded, scale: 0.5),
                ],
              ),
      CardKind.skip => icon(Icons.block_rounded),
      CardKind.reverse => icon(Icons.sync_alt_rounded),
      CardKind.skipAll => icon(Icons.fast_forward_rounded),
      CardKind.discardAll => icon(Icons.layers_clear_rounded, scale: 0.82),
      CardKind.flip => icon(Icons.flip_rounded, scale: 0.85),
      CardKind.wild =>
        corner
            ? SizedBox.square(
                dimension: size * 0.8,
                child: CustomPaint(painter: _PinwheelPainter(wilds)),
              )
            : const SizedBox.shrink(),
      CardKind.wildDrawColor => text('+?', scale: 0.8),
    };
  }
}

class _Back extends StatelessWidget {
  const _Back({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Palette.of(CardColor.wild),
      child: Center(
        child: Transform.rotate(
          angle: -0.32,
          child: Container(
            width: width * 0.78,
            height: width * (width < 44 ? 0.5 : 0.46),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Palette.brand,
              borderRadius: BorderRadius.circular(width * 0.12),
              border: Border.all(
                color: Palette.cardWhite,
                width: max(1, width * 0.025),
              ),
            ),
            child: width < 44
                ? null
                : Text(
                    'LAST\nCARD',
                    textAlign: TextAlign.center,
                    style: font(
                      width * 0.14,
                      weight: 700,
                      color: Colors.white,
                      height: 0.95,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _PinwheelPainter extends CustomPainter {
  _PinwheelPainter(this.colors);

  final List<CardColor> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 4; i++) {
      paint.color = Palette.of(colors[i]);
      canvas.drawArc(rect, -pi / 2 + i * pi / 2 + 0.25, pi / 2, true, paint);
    }
    canvas.drawCircle(
      rect.center,
      size.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1, size.width * 0.05)
        ..color = Palette.cardWhite,
    );
  }

  @override
  bool shouldRepaint(_PinwheelPainter old) => old.colors != colors;
}
