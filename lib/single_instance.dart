import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// flock(2) lock modes from <sys/file.h>.
const _lockEx = 2; // LOCK_EX
const _lockNb = 4; // LOCK_NB

// creat, flock and close are all non-variadic C functions, so they are safe
// to bind through dart:ffi (variadic functions are not supported).
final DynamicLibrary _libc = DynamicLibrary.process();
final int Function(Pointer<Utf8>, int) _creat = _libc
    .lookupFunction<
      Int32 Function(Pointer<Utf8>, Uint32),
      int Function(Pointer<Utf8>, int)
    >('creat');
final int Function(int, int) _flock = _libc
    .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
      'flock',
    );
final int Function(int) _close = _libc
    .lookupFunction<Int32 Function(Int32), int Function(int)>('close');

/// The outcome of trying to acquire the single-instance lock.
sealed class SingleInstanceAcquireResult {
  const SingleInstanceAcquireResult();
}

/// This process is the only Miaosic instance and holds the lock.
class SingleInstanceAcquired extends SingleInstanceAcquireResult {
  const SingleInstanceAcquired(this.lock);

  final SingleInstanceLock lock;
}

/// Another Miaosic instance is already running.
class SingleInstanceAlreadyRunning extends SingleInstanceAcquireResult {
  const SingleInstanceAlreadyRunning();
}

/// The lock file could not be created, so the guard cannot run. Callers
/// typically start anyway (fail open) after warning the user.
class SingleInstanceLockUnavailable extends SingleInstanceAcquireResult {
  const SingleInstanceLockUnavailable(this.message);

  final String message;
}

/// A process-wide lock that prevents more than one Miaosic instance from
/// running at the same time.
///
/// The lock is an advisory `flock(2)` on a well-known lock file. The kernel
/// releases the lock automatically when the owning process exits, so a
/// crashed instance never leaves a stale lock behind. The lock file
/// descriptor stays open for the whole process lifetime; nothing closes it
/// except [release] or process exit.
class SingleInstanceLock {
  SingleInstanceLock._(this._fd, this.path);

  final int _fd;
  final String path;

  static SingleInstanceAcquireResult tryAcquire(String lockPath) {
    final parent = File(lockPath).parent;
    if (!parent.existsSync()) {
      try {
        parent.createSync(recursive: true);
      } on FileSystemException {
        return SingleInstanceLockUnavailable(
          'could not create lock directory: ${parent.path}',
        );
      }
    }
    final pathPointer = lockPath.toNativeUtf8();
    try {
      // creat opens with O_WRONLY | O_CREAT | O_TRUNC. The lock state lives
      // in the kernel (flock on the inode), so truncating the file is fine.
      final fd = _creat(pathPointer, 0x1A4 /* 0644 */);
      if (fd < 0) {
        return SingleInstanceLockUnavailable(
          'could not create lock file: $lockPath',
        );
      }
      if (_flock(fd, _lockEx | _lockNb) != 0) {
        _close(fd);
        return const SingleInstanceAlreadyRunning();
      }
      // Record the owning PID in the lock file for diagnostics.
      try {
        File(lockPath).writeAsStringSync('$pid\n');
      } on FileSystemException {
        // The PID is only for diagnostics; the lock itself is unaffected.
      }
      return SingleInstanceAcquired(SingleInstanceLock._(fd, lockPath));
    } finally {
      calloc.free(pathPointer);
    }
  }

  /// Releases the lock. The kernel also releases it when the process exits.
  void release() {
    _close(_fd);
  }
}

/// Resolves the default single-instance lock file path for this user.
///
/// Prefers the per-user runtime directory so the lock is cleaned up on
/// logout, then falls back to the application support directory and finally
/// to a user-writable temp location.
Future<String> defaultSingleInstanceLockPath() async {
  final env = Platform.environment;
  final runtimeDir = env['XDG_RUNTIME_DIR']?.trim();
  if (runtimeDir != null && runtimeDir.isNotEmpty) {
    return p.join(runtimeDir, 'miaosic.lock');
  }
  try {
    final appDir = await getApplicationSupportDirectory();
    return p.join(appDir.path, 'miaosic.lock');
  } catch (_) {
    return fallbackSingleInstanceLockPath();
  }
}

String fallbackSingleInstanceLockPath() {
  final env = Platform.environment;
  final dataHome = env['XDG_DATA_HOME']?.trim();
  final home = env['HOME']?.trim();
  final root = dataHome != null && dataHome.isNotEmpty
      ? dataHome
      : (home != null && home.isNotEmpty
            ? p.join(home, '.local', 'share')
            : Directory.systemTemp.path);
  return p.join(root, 'dev.vesein.miaosic', 'miaosic.lock');
}
