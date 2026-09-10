// Native engine regression check. flutter test uses the SDK's test engine and
// cannot detect missing font support in our bundled libflutter_linux_gtk.so.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

Future<Uint8List> renderGlyph(String text) async {
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(fontSize: 48, textDirection: TextDirection.ltr),
  )..addText(text);
  final paragraph = builder.build()
    ..layout(const ui.ParagraphConstraints(width: 96));
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawParagraph(paragraph, const Offset(8, 8));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(112, 96);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('Glyph readback returned no pixels');
      return Uint8List.fromList(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
    paragraph.dispose();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('中文字体检查：音乐、专辑、歌词'))),
    ),
  );
  await WidgetsBinding.instance.endOfFrame;
  try {
    final missing = await renderGlyph('\u{10FFFF}');
    final glyphs = <Uint8List>[];
    for (final rune in '中文音乐专辑歌词'.runes) {
      final character = String.fromCharCode(rune);
      final pixels = await renderGlyph(character);
      final hasInk = [
        for (var i = 3; i < pixels.length; i += 4) pixels[i],
      ].any((alpha) => alpha != 0);
      if (!hasInk || samePixels(pixels, missing)) {
        throw StateError('Missing Chinese glyph: $character');
      }
      if (glyphs.any((other) => samePixels(pixels, other))) {
        throw StateError(
          'Chinese characters render as identical glyphs: $character',
        );
      }
      glyphs.add(pixels);
    }
    stdout.writeln(
      'FONT_PROBE_OK: 8 distinct Chinese glyphs rendered using system font fallback',
    );
    exit(0);
  } catch (error, stack) {
    stderr.writeln('FONT_PROBE_FAILED: $error\n$stack');
    exit(1);
  }
}

bool samePixels(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
