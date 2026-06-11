import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/library_diff.dart';
import 'package:miaosic/library_types.dart';
import 'package:miaosic/models.dart';
import 'package:miaosic/rescan_dialog.dart';

void main() {
  testWidgets('rescan dialog uses top close button and left full rescan', (
    tester,
  ) async {
    final state = ValueNotifier(const RescanUiState(phase: RescanPhase.idle));
    var fullRescanCount = 0;
    var editRootCount = 0;

    await tester.pumpWidget(
      _DialogHost(
        state: state,
        onEditMusicRoot: () => editRootCount += 1,
        onFullRescan: () => fullRescanCount += 1,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, 'Close'), findsNothing);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.text('/music'), findsOneWidget);
    expect(find.text('Ready to rescan'), findsWidgets);
    expect(find.widgetWithText(TextButton, 'Full rescan'), findsOneWidget);

    await tester.tap(find.byTooltip('Change music folder'));
    await tester.pump();
    await tester.tap(find.text('Full rescan'));
    await tester.pump();

    expect(editRootCount, 1);
    expect(fullRescanCount, 1);
    expect(find.text('Rescan library'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Rescan library'), findsNothing);
  });

  testWidgets('apply closes only after successful apply', (tester) async {
    final state = ValueNotifier(
      RescanUiState(phase: RescanPhase.ready, diff: _diff(hasChanges: true)),
    );
    var applyCount = 0;

    await tester.pumpWidget(
      _DialogHost(
        state: state,
        onApply: () async {
          applyCount += 1;
          return applyCount == 2;
        },
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(applyCount, 1);
    expect(find.text('Rescan library'), findsOneWidget);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(applyCount, 2);
    expect(find.text('Rescan library'), findsNothing);
  });

  testWidgets('apply closes after applying changes', (tester) async {
    final state = ValueNotifier(
      RescanUiState(phase: RescanPhase.ready, diff: _diff(hasChanges: true)),
    );
    var applyCount = 0;

    await tester.pumpWidget(
      _DialogHost(
        state: state,
        onApply: () async {
          applyCount += 1;
          return true;
        },
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(applyCount, 1);
    expect(find.text('Rescan library'), findsNothing);
  });

  testWidgets('rescan stays open when no changes are found', (tester) async {
    final state = ValueNotifier(const RescanUiState(phase: RescanPhase.idle));

    await tester.pumpWidget(
      _DialogHost(
        state: state,
        onRescan: () {
          state.value = const RescanUiState(
            phase: RescanPhase.scanning,
            message: 'Scanning local files',
          );
        },
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rescan'));
    await tester.pump();
    state.value = RescanUiState(
      phase: RescanPhase.ready,
      message: 'Library is up to date',
      diff: _diff(hasChanges: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rescan library'), findsOneWidget);
    expect(find.text('Library is up to date'), findsWidgets);
  });

  testWidgets('direct scan mode hides diff actions', (tester) async {
    final state = ValueNotifier(
      const RescanUiState(
        mode: LibraryScanMode.direct,
        phase: RescanPhase.error,
        message: 'Music folder scan failed',
        error: 'missing folder',
      ),
    );
    var scanCount = 0;

    await tester.pumpWidget(
      _DialogHost(state: state, onScanLibrary: () => scanCount += 1),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Scan library'), findsOneWidget);
    expect(find.text('Rescan library'), findsNothing);
    expect(find.text('Scan failed'), findsOneWidget);
    expect(find.text('missing folder'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Full rescan'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Apply'), findsNothing);
    expect(find.text('Retry scan'), findsOneWidget);

    await tester.tap(find.text('Retry scan'));
    await tester.pump();

    expect(scanCount, 1);
  });

  testWidgets('escape closes rescan dialog', (tester) async {
    final state = ValueNotifier(const RescanUiState(phase: RescanPhase.idle));

    await tester.pumpWidget(_DialogHost(state: state));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Rescan library'), findsNothing);
  });
}

class _DialogHost extends StatelessWidget {
  const _DialogHost({
    required this.state,
    this.onApply,
    this.onScanLibrary,
    this.onEditMusicRoot,
    this.onRescan,
    this.onFullRescan,
  });

  final ValueNotifier<RescanUiState> state;
  final Future<bool> Function()? onApply;
  final VoidCallback? onScanLibrary;
  final VoidCallback? onEditMusicRoot;
  final VoidCallback? onRescan;
  final VoidCallback? onFullRescan;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) {
                      return RescanDialog(
                        stateListenable: state,
                        trackCoverCacheListenable: ValueNotifier(const {}),
                        musicRoot: '/music',
                        canEditMusicRoot: true,
                        onEditMusicRoot: onEditMusicRoot ?? () {},
                        onApply: onApply ?? () async => true,
                        onScanLibrary: onScanLibrary ?? () {},
                        onRescan: onRescan ?? () {},
                        onFullRescan: onFullRescan ?? () {},
                      );
                    },
                  );
                },
                child: const Text('Open'),
              ),
            ),
          );
        },
      ),
    );
  }
}

LibraryDiff _diff({required bool hasChanges}) {
  final track = _track('/music/one.flac');
  return LibraryDiff(
    added: hasChanges
        ? [
            TrackChange(
              path: track.path,
              oldTrack: null,
              newTrack: track,
              reason: TrackChangeReason.added,
            ),
          ]
        : const [],
    removed: const [],
    modified: const [],
    unchangedCount: hasChanges ? 0 : 4,
    result: ScanResult(
      rootPath: '/music',
      engine: 'test',
      tracks: [if (hasChanges) track],
      folders: const [],
      albums: const [],
      elapsed: Duration.zero,
      coversCached: 0,
    ),
  );
}

Track _track(String path) {
  return Track(
    path: path,
    folderPath: '/music',
    title: 'One',
    artist: 'Artist',
    album: 'Album',
    albumArtist: 'Artist',
    trackNumber: 1,
    discNumber: null,
    year: null,
    durationMs: null,
    sizeBytes: 1,
    modifiedMs: 1,
    coverArtPath: null,
  );
}
