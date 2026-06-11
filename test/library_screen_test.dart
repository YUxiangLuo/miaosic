import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:miaosic/library_controller.dart';
import 'package:miaosic/library_screen.dart';
import 'package:miaosic/llm_settings.dart';
import 'package:miaosic/models.dart';
import 'package:miaosic/playback_controller.dart';

void main() {
  setUpAll(MediaKit.ensureInitialized);

  testWidgets('injected controllers are not disposed by LibraryScreen', (
    tester,
  ) async {
    final library = _InjectedLibraryController();
    final playback = _InjectedPlaybackController();
    ThemeMode? requestedThemeMode;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          themeMode: ThemeMode.light,
          onThemeModeChanged: (mode) => requestedThemeMode = mode,
          libraryController: library,
          playbackController: playback,
        ),
      ),
    );
    await tester.pump();

    expect(library.opened, isTrue);
    await tester.tap(find.byTooltip('Switch to dark mode'));
    await tester.pump();

    expect(requestedThemeMode, ThemeMode.dark);
    expect(library.savedThemeMode, 'dark');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(library.disposedByScreen, isFalse);
    expect(playback.disposedByScreen, isFalse);

    playback.disposeForTest();
    library.disposeForTest();
  });

  testWidgets(
    'music root dialog keeps its text controller alive until submit',
    (tester) async {
      final library = _InjectedLibraryController(canEditMusicRoot: true);
      final playback = _InjectedPlaybackController();

      await tester.pumpWidget(
        MaterialApp(
          home: LibraryScreen(
            themeMode: ThemeMode.light,
            onThemeModeChanged: (_) {},
            libraryController: library,
            playbackController: playback,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Library settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Change music folder'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, '/music');

      await tester.enterText(find.byType(TextField), '/next/music');
      await tester.tap(find.text('Save and rescan'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(library.changedMusicRoot, '/next/music');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      playback.disposeForTest();
      library.disposeForTest();
    },
  );
}

class _InjectedLibraryController extends LibraryController {
  _InjectedLibraryController({this.canEditMusicRoot = false});

  bool opened = false;
  bool disposedByScreen = false;
  final bool canEditMusicRoot;
  String? savedThemeMode;
  String? changedMusicRoot;

  @override
  Future<void> open() async {
    opened = true;
    notifyListeners();
  }

  @override
  void dispose() {
    disposedByScreen = true;
    super.dispose();
  }

  void disposeForTest() {
    super.dispose();
  }

  @override
  Future<void> saveThemeMode(String value) async {
    savedThemeMode = value;
  }

  @override
  Future<bool> changeMusicRoot(String nextRoot) async {
    changedMusicRoot = nextRoot;
    return true;
  }

  @override
  List<Track> get tracks => const [];

  @override
  List<FolderSummary> get folders => const [];

  @override
  List<AlbumSummary> get albums => const [];

  @override
  Map<String, String?> get trackCoverCache => const {};

  @override
  LastPlaybackState? get lastPlayback => null;

  @override
  LlmSettings get llmSettings => const LlmSettings.defaults();

  @override
  String get musicRoot => '/music';

  @override
  String get themeMode => 'light';

  @override
  bool get loading => false;

  @override
  bool get settingsLoaded => true;

  @override
  bool get canChangeMusicRoot => canEditMusicRoot;

  @override
  bool get canRestoreLastPlayback => false;

  @override
  List<FolderSummary> get playlistFolders => const [];

  @override
  int get playlistCount => 0;

  @override
  Map<String, List<Track>> get tracksByFolder => const {};
}

class _InjectedPlaybackController extends PlaybackController {
  bool disposedByScreen = false;

  @override
  Track? get currentTrack => null;

  @override
  bool get playing => false;

  @override
  bool isCurrentQueue(List<Track> queue) => false;

  @override
  void dispose() {
    disposedByScreen = true;
    super.dispose();
  }

  void disposeForTest() {
    super.dispose();
  }
}
