import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import 'library_database.dart';
import 'library_diff.dart';
import 'models.dart';
import 'music_scanner.dart';
import 'playback_controller.dart';
import 'playlist_cover_indexer.dart';

part 'album_views.dart';
part 'app.dart';
part 'library_formatters.dart';
part 'library_screen.dart';
part 'library_sidebar.dart';
part 'library_widgets.dart';
part 'playlist_views.dart';
part 'rescan_dialog.dart';
part 'track_views.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  imageCache.maximumSize = 1600;
  imageCache.maximumSizeBytes = 256 * 1024 * 1024;
  MediaKit.ensureInitialized();
  runApp(const MiaosicApp());
}
