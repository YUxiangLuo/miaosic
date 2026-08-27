import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/single_instance.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('miaosic_single_instance_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  String lockPath() => '${tempDir.path}/miaosic.lock';

  test('first instance acquires the lock', () {
    final result = SingleInstanceLock.tryAcquire(lockPath());
    expect(result, isA<SingleInstanceAcquired>());
    final lock = (result as SingleInstanceAcquired).lock;
    expect(lock.path, lockPath());
    lock.release();
  });

  test('second instance is rejected while the first holds the lock', () {
    final first = SingleInstanceLock.tryAcquire(lockPath());
    expect(first, isA<SingleInstanceAcquired>());

    final second = SingleInstanceLock.tryAcquire(lockPath());
    expect(second, isA<SingleInstanceAlreadyRunning>());

    (first as SingleInstanceAcquired).lock.release();
  });

  test('lock can be re-acquired after release', () {
    final first = SingleInstanceLock.tryAcquire(lockPath());
    (first as SingleInstanceAcquired).lock.release();

    final second = SingleInstanceLock.tryAcquire(lockPath());
    expect(second, isA<SingleInstanceAcquired>());
    (second as SingleInstanceAcquired).lock.release();
  });

  test('lock file records the owning pid', () {
    final result = SingleInstanceLock.tryAcquire(lockPath());
    expect(result, isA<SingleInstanceAcquired>());

    final content = File(lockPath()).readAsStringSync().trim();
    expect(content, pid.toString());

    (result as SingleInstanceAcquired).lock.release();
  });

  test('missing parent directory is created before locking', () {
    final nested = '${tempDir.path}/nested/dir/miaosic.lock';
    final result = SingleInstanceLock.tryAcquire(nested);
    expect(result, isA<SingleInstanceAcquired>());
    (result as SingleInstanceAcquired).lock.release();
  });

  test('lock is reported unavailable when the lock file cannot be created', () {
    // A regular file in the path makes creat fail with ENOTDIR.
    final blocker = File('${tempDir.path}/blocker')..writeAsStringSync('x');
    final result = SingleInstanceLock.tryAcquire(
      '${blocker.path}/miaosic.lock',
    );
    expect(result, isA<SingleInstanceLockUnavailable>());
  });
}
