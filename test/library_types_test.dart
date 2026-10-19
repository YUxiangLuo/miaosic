import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/library_types.dart';
import 'package:miaosic/models.dart';

void main() {
  test('copyWith keeps progress and error unless they are passed', () {
    const progress = ScanProgress(
      filesSeen: 4,
      tracksParsed: 3,
      currentPath: '/music/a.flac',
    );
    const state = RescanUiState(
      phase: RescanPhase.scanning,
      message: 'Scanning local files',
      progress: progress,
      error: 'old',
    );

    final kept = state.copyWith(message: 'Still scanning');
    expect(kept.progress, progress);
    expect(kept.error, 'old');
    expect(kept.message, 'Still scanning');

    final cleared = state.copyWith(progress: null, error: null);
    expect(cleared.progress, isNull);
    expect(cleared.error, isNull);
    expect(cleared.phase, RescanPhase.scanning);
  });
}
