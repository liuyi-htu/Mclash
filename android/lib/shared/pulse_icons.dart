// Lucide icon geometry; licenses are reproduced in THIRD_PARTY_NOTICES/lucide.txt.
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class PulseIcon extends Icon {
  const PulseIcon(super.icon, {super.key, super.size = 20, super.color});
  static final glyphs = {
    Icons.home_outlined: 'house',
    Icons.hub_outlined: 'waypoints',
    Icons.inventory_2_outlined: 'files',
    Icons.settings_outlined: 'settings',
    Icons.power_settings_new: 'power',
    Icons.search: 'search',
  };
  @override
  Widget build(BuildContext context) {
    final glyph = glyphs[icon];
    if (glyph == null) return super.build(context);
    final theme = IconTheme.of(context);
    final actualSize = size ?? theme.size ?? 20;
    return SizedBox.square(
        dimension: actualSize,
        child: CustomPaint(
            painter: _PulseIconPainter(
                glyph,
                color ??
                    theme.color ??
                    Theme.of(context).colorScheme.onSurface)));
  }
}

class _PulseIconPainter extends CustomPainter {
  const _PulseIconPainter(this.glyph, this.color);
  final String glyph;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (glyph) {
      case 'house':
        {
          final path = Path();
          path.moveTo(15, 21);
          path.lineTo(15, 13);
          path.arcToPoint(Offset(14, 12),
              radius: Radius.elliptical(1, 1),
              rotation: 0,
              largeArc: false,
              clockwise: false);
          path.lineTo(10, 12);
          path.arcToPoint(Offset(9, 13),
              radius: Radius.elliptical(1, 1),
              rotation: 0,
              largeArc: false,
              clockwise: false);
          path.lineTo(9, 21);
          canvas.drawPath(path, paint);
        }
        {
          final path = Path();
          path.moveTo(3, 10);
          path.arcToPoint(Offset(3.709, 8.472),
              radius: Radius.elliptical(2, 2),
              rotation: 0,
              largeArc: false,
              clockwise: true);
          path.lineTo(10.709, 2.472);
          path.arcToPoint(Offset(13.291, 2.472),
              radius: Radius.elliptical(2, 2),
              rotation: 0,
              largeArc: false,
              clockwise: true);
          path.lineTo(20.291, 8.472);
          path.arcToPoint(Offset(21, 10),
              radius: Radius.elliptical(2, 2),
              rotation: 0,
              largeArc: false,
              clockwise: true);
          path.lineTo(21, 19);
          path.arcToPoint(Offset(19, 21),
              radius: Radius.elliptical(2, 2),
              rotation: 0,
              largeArc: false,
              clockwise: true);
          path.lineTo(5, 21);
          path.arcToPoint(Offset(3, 19),
              radius: Radius.elliptical(2, 2),
              rotation: 0,
              largeArc: false,
              clockwise: true);
          path.close();
          canvas.drawPath(path, paint);
        }
        break;
      case 'waypoints':
        {
          final path = Path();
          path.moveTo(10.586, 5.414);
          path.lineTo(5.414, 10.586);
          canvas.drawPath(path, paint);
        }
        {
          final path = Path();
          path.moveTo(18.586, 13.414);
          path.lineTo(13.414, 18.586);
          canvas.drawPath(path, paint);
        }
        {
          final path = Path();
          path.moveTo(6, 12);
          path.lineTo(18, 12);
          canvas.drawPath(path, paint);
        }
        canvas.drawCircle(Offset(12, 20), 2, paint);
        canvas.drawCircle(Offset(12, 4), 2, paint);
        canvas.drawCircle(Offset(20, 12), 2, paint);
        canvas.drawCircle(Offset(4, 12), 2, paint);
        break;
      case 'files':
        {
          final path = Path();
          path.moveTo(15, 2);
          path.lineTo(11, 2);
          path.arcToPoint(Offset(9, 4),
              radius: Radius.elliptical(2, 2),
              rotation: 0,
              largeArc: false,
              clockwise: false);
          path.lineTo(9, 15);
          path.arcToPoint(Offset(11, 17),
              radius: Radius.elliptical(2, 2),
              rotation: 0,
              largeArc: false,
              clockwise: false);
          path.lineTo(19, 17);
          path.arcToPoint(Offset(21, 15),
              radius: Radius.elliptical(2, 2),
              rotation: 0,
              largeArc: false,
              clockwise: false);
          path.lineTo(21, 8);
          canvas.drawPath(path, paint);
        }
        {
          final path = Path();
          path.moveTo(16.706, 2.706);
          path.arcToPoint(Offset(15, 2),
              radius: Radius.elliptical(2.4, 2.4),
              rotation: 0,
              largeArc: false,
              clockwise: false);
          path.lineTo(15, 7);
          path.arcToPoint(Offset(16, 8),
              radius: Radius.elliptical(1, 1),
              rotation: 0,
              largeArc: false,
              clockwise: false);
          path.lineTo(21, 8);
          path.arcToPoint(Offset(20.294, 6.294),
              radius: Radius.elliptical(2.4, 2.4),
              rotation: 0,
              largeArc: false,
              clockwise: false);
          path.close();
          canvas.drawPath(path, paint);
        }
        {
          final path = Path();
          path.moveTo(5, 7);
          path.arcToPoint(Offset(3, 9),
              radius: Radius.elliptical(2, 2),
              rotation: 0,
              largeArc: false,
              clockwise: false);
          path.lineTo(3, 20);
          path.arcToPoint(Offset(5, 22),
              radius: Radius.elliptical(2, 2),
              rotation: 0,
              largeArc: false,
              clockwise: false);
          path.lineTo(13, 22);
          path.arcToPoint(Offset(14.732, 21),
              radius: Radius.elliptical(2, 2),
              rotation: 0,
              largeArc: false,
              clockwise: false);
          canvas.drawPath(path, paint);
        }
        break;
      case 'settings':
        {
          final path = Path();
          path.moveTo(9.671, 4.136);
          path.arcToPoint(Offset(14.33, 4.136),
              radius: Radius.elliptical(2.34, 2.34),
              rotation: 0,
              largeArc: false,
              clockwise: true);
          path.arcToPoint(Offset(17.649, 6.051),
              radius: Radius.elliptical(2.34, 2.34),
              rotation: 0,
              largeArc: false,
              clockwise: false);
          path.arcToPoint(Offset(19.979, 10.084),
              radius: Radius.elliptical(2.34, 2.34),
              rotation: 0,
              largeArc: false,
              clockwise: true);
          path.arcToPoint(Offset(19.979, 13.915),
              radius: Radius.elliptical(2.34, 2.34),
              rotation: 0,
              largeArc: false,
              clockwise: false);
          path.arcToPoint(Offset(17.649, 17.948),
              radius: Radius.elliptical(2.34, 2.34),
              rotation: 0,
              largeArc: false,
              clockwise: true);
          path.arcToPoint(Offset(14.33, 19.863),
              radius: Radius.elliptical(2.34, 2.34),
              rotation: 0,
              largeArc: false,
              clockwise: false);
          path.arcToPoint(Offset(9.671, 19.863),
              radius: Radius.elliptical(2.34, 2.34),
              rotation: 0,
              largeArc: false,
              clockwise: true);
          path.arcToPoint(Offset(6.351, 17.948),
              radius: Radius.elliptical(2.34, 2.34),
              rotation: 0,
              largeArc: false,
              clockwise: false);
          path.arcToPoint(Offset(4.021, 13.915),
              radius: Radius.elliptical(2.34, 2.34),
              rotation: 0,
              largeArc: false,
              clockwise: true);
          path.arcToPoint(Offset(4.021, 10.084),
              radius: Radius.elliptical(2.34, 2.34),
              rotation: 0,
              largeArc: false,
              clockwise: false);
          path.arcToPoint(Offset(6.35, 6.051),
              radius: Radius.elliptical(2.34, 2.34),
              rotation: 0,
              largeArc: false,
              clockwise: true);
          path.arcToPoint(Offset(9.669, 4.136),
              radius: Radius.elliptical(2.34, 2.34),
              rotation: 0,
              largeArc: false,
              clockwise: false);
          canvas.drawPath(path, paint);
        }
        canvas.drawCircle(Offset(12, 12), 3, paint);
        break;
      case 'power':
        {
          final path = Path();
          path.moveTo(12, 2);
          path.lineTo(12, 12);
          canvas.drawPath(path, paint);
        }
        {
          final path = Path();
          path.moveTo(18.4, 6.6);
          path.arcToPoint(Offset(5.63, 6.64),
              radius: Radius.elliptical(9, 9),
              rotation: 0,
              largeArc: true,
              clockwise: true);
          canvas.drawPath(path, paint);
        }
        break;
      case 'search':
        {
          final path = Path();
          path.moveTo(21, 21);
          path.lineTo(16.66, 16.66);
          canvas.drawPath(path, paint);
        }
        canvas.drawCircle(Offset(11, 11), 8, paint);
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PulseIconPainter old) =>
      old.glyph != glyph || old.color != color;
}

void registerPulseIconLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(['Lucide'], r'''ISC License

Copyright (c) 2026 Lucide Icons and Contributors

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

---

The following Lucide icons are derived from the Feather project:

airplay, alert-circle, alert-octagon, alert-triangle, aperture, arrow-down-circle, arrow-down-left, arrow-down-right, arrow-down, arrow-left-circle, arrow-left, arrow-right-circle, arrow-right, arrow-up-circle, arrow-up-left, arrow-up-right, arrow-up, at-sign, calendar, cast, check, chevron-down, chevron-left, chevron-right, chevron-up, chevrons-down, chevrons-left, chevrons-right, chevrons-up, circle, clipboard, clock, code, columns, command, compass, corner-down-left, corner-down-right, corner-left-down, corner-left-up, corner-right-down, corner-right-up, corner-up-left, corner-up-right, crosshair, database, divide-circle, divide-square, dollar-sign, download, external-link, feather, frown, hash, headphones, help-circle, info, italic, key, layout, life-buoy, link-2, link, loader, lock, log-in, log-out, maximize, meh, minimize, minimize-2, minus-circle, minus-square, minus, monitor, moon, more-horizontal, more-vertical, move, music, navigation-2, navigation, octagon, pause-circle, percent, plus-circle, plus-square, plus, power, radio, rss, search, server, share, shopping-bag, sidebar, smartphone, smile, square, table-2, tablet, target, terminal, trash-2, trash, triangle, tv, type, upload, x-circle, x-octagon, x-square, x, zoom-in, zoom-out

The MIT License (MIT) (for the icons listed above)

Copyright (c) 2013-present Cole Bemis

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
''');
  });
}
