import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'single_instance.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final result = SingleInstanceLock.tryAcquire(
    await defaultSingleInstanceLockPath(),
  );
  switch (result) {
    case SingleInstanceAcquired():
      // The lock file descriptor stays open for the whole process lifetime,
      // so the kernel keeps the lock until this process exits.
      break;
    case SingleInstanceAlreadyRunning():
      stderr.writeln('Miaosic is already running.');
      exit(0);
    case SingleInstanceLockUnavailable(:final message):
      // The guard could not run; start anyway rather than block the user.
      stderr.writeln('Warning: $message');
  }
  imageCache.maximumSize = 1600;
  imageCache.maximumSizeBytes = 256 * 1024 * 1024;
  MediaKit.ensureInitialized();
  runApp(const MiaosicApp());
  if (Platform.environment['MIAOSIC_SMOKE_TEST'] == '1') {
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
    stdout.writeln('MIAOSIC_SMOKE_READY');
  }
}
