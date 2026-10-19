import 'package:flutter/foundation.dart';

import 'app_diagnostics.dart';
import 'library_scan_state.dart';
import 'models.dart';
import 'music_scanner.dart';

/// Owns the scanner's lifecycle. Database policies stay in LibraryController.
class LibraryScanTask extends ValueNotifier<RescanUiState> {
  LibraryScanTask(this._scanner)
    : super(const RescanUiState(phase: RescanPhase.idle));

  final MusicScanner _scanner;
  bool _running = false;
  bool _disposed = false;

  bool get running => _running;

  Future<T?> run<T>({
    required RescanUiState initialState,
    required String errorMessage,
    required Future<T> Function() work,
  }) async {
    if (_disposed || _running) return null;
    _scanner.prepareForScan();
    _running = true;
    value = initialState;
    try {
      return await work();
    } on ScanCancelledException {
      if (!_disposed) {
        value = RescanUiState(
          mode: initialState.mode,
          phase: RescanPhase.idle,
          message: 'Scan cancelled',
        );
      }
    } catch (error, stackTrace) {
      reportAppError('library scan', error, stackTrace);
      if (!_disposed) {
        value = RescanUiState(
          mode: initialState.mode,
          phase: RescanPhase.error,
          message: errorMessage,
          error: error.toString(),
        );
      }
    } finally {
      _running = false;
      if (!_disposed) {
        value = value.copyWith(progress: null);
      }
    }
    return null;
  }

  Future<ScanResult> scan(String rootPath, {List<Track>? previousTracks}) {
    if (_disposed) throw const ScanCancelledException();
    return _scanner.scan(
      rootPath,
      previousTracks: previousTracks,
      onProgress: (progress) {
        if (!_disposed) value = value.copyWith(progress: progress);
      },
    );
  }

  void cancel() => _scanner.cancel();

  @override
  void dispose() {
    _disposed = true;
    _scanner.cancel();
    super.dispose();
  }
}
