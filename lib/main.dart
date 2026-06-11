import 'package:flutter/material.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  imageCache.maximumSize = 1600;
  imageCache.maximumSizeBytes = 256 * 1024 * 1024;
  runApp(const MiaosicApp());
}
