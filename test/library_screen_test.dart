import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:miaosic/album_playback_view.dart';
import 'package:miaosic/audio_output_settings.dart';
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

  testWidgets('does not auto-open now playing before thirty seconds', (
    tester,
  ) async {
    final fixture = _LibraryFixture.album();
    var now = DateTime(2026);
    final library = _InjectedLibraryController(
      tracks: fixture.tracks,
      albums: [fixture.album],
      tracksByFolder: {fixture.album.folderPath: fixture.tracks},
    );
    final playback = _InjectedPlaybackController(
      currentTrack: fixture.tracks.first,
      playing: true,
      currentQueue: fixture.tracks,
    );

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: () => now,
    );

    expect(find.byType(AlbumPlaybackView), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now = now.add(const Duration(seconds: 29));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.byType(AlbumPlaybackView), findsNothing);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets('auto-opens album now playing after thirty seconds away', (
    tester,
  ) async {
    final fixture = _LibraryFixture.album();
    var now = DateTime(2026);
    final library = _InjectedLibraryController(
      tracks: fixture.tracks,
      albums: [fixture.album],
      tracksByFolder: {fixture.album.folderPath: fixture.tracks},
    );
    final playback = _InjectedPlaybackController(
      currentTrack: fixture.tracks.first,
      playing: true,
      currentQueue: fixture.tracks,
    );

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: () => now,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now = now.add(const Duration(seconds: 31));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.byType(AlbumPlaybackView), findsOneWidget);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets('does not auto-open now playing while playback is paused', (
    tester,
  ) async {
    final fixture = _LibraryFixture.album();
    var now = DateTime(2026);
    final library = _InjectedLibraryController(
      tracks: fixture.tracks,
      albums: [fixture.album],
      tracksByFolder: {fixture.album.folderPath: fixture.tracks},
    );
    final playback = _InjectedPlaybackController(
      currentTrack: fixture.tracks.first,
      playing: false,
      currentQueue: fixture.tracks,
    );

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: () => now,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now = now.add(const Duration(seconds: 31));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.byType(AlbumPlaybackView), findsNothing);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets('skips auto-open now playing while settings dialog is open', (
    tester,
  ) async {
    final fixture = _LibraryFixture.album();
    var now = DateTime(2026);
    final library = _InjectedLibraryController(
      tracks: fixture.tracks,
      albums: [fixture.album],
      tracksByFolder: {fixture.album.folderPath: fixture.tracks},
    );
    final playback = _InjectedPlaybackController(
      currentTrack: fixture.tracks.first,
      playing: true,
      currentQueue: fixture.tracks,
    );

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: () => now,
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now = now.add(const Duration(seconds: 31));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(AlbumPlaybackView), findsNothing);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets('favorites now playing returns to Favorites and space pauses', (
    tester,
  ) async {
    final fixture = _LibraryFixture.album();
    var now = DateTime(2026);
    final library = _InjectedLibraryController(
      tracks: fixture.tracks,
      favoriteTracks: fixture.tracks,
      tracksByFolder: {fixture.album.folderPath: fixture.tracks},
    );
    final playback = _InjectedPlaybackController(
      currentTrack: fixture.tracks.first,
      playing: true,
      currentQueue: fixture.tracks,
    );

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: () => now,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now = now.add(const Duration(seconds: 31));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('1 favorite track'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(playback.toggleCount, 1);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets('favorites now playing preserves shuffled queue when returning', (
    tester,
  ) async {
    final favoriteTracks = _favoriteTracks(8);
    var now = DateTime(2026);
    final library = _InjectedLibraryController(
      tracks: favoriteTracks,
      favoriteTracks: favoriteTracks,
    );
    final playback = _InjectedPlaybackController();

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: () => now,
    );

    await tester.tap(find.widgetWithText(InkWell, 'Favorites'));
    await tester.pump();
    for (var attempt = 0; attempt < 20; attempt += 1) {
      await tester.tap(find.byTooltip('Shuffle favorites'));
      await tester.pump();
      if (!_sameTrackOrder(playback.currentQueueForTest, favoriteTracks)) {
        break;
      }
    }
    expect(playback.currentQueueForTest, isNotEmpty);
    expect(
      _sameTrackOrder(playback.currentQueueForTest, favoriteTracks),
      false,
    );

    await tester.tap(find.widgetWithText(InkWell, 'Albums'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now = now.add(const Duration(seconds: 31));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(
      find.text('${favoriteTracks.length} favorite tracks'),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(playback.toggleCount, 1);
    expect(
      _sameTrackOrder(playback.currentQueueForTest, favoriteTracks),
      isFalse,
    );

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets('restores persisted favorites playback', (tester) async {
    final favoriteTracks = _favoriteTracks(3);
    final library = _InjectedLibraryController(
      tracks: favoriteTracks,
      favoriteTracks: favoriteTracks,
      lastPlaybackState: LastPlaybackState(
        kind: LastPlaybackKind.favorites,
        folderPath: '',
        trackPath: favoriteTracks[1].path,
        playing: false,
        shuffled: false,
      ),
      canRestorePlayback: true,
    );
    final playback = _InjectedPlaybackController();

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: DateTime.now,
    );
    await tester.pump();

    expect(playback.restoreCount, 1);
    expect(playback.currentTrack?.path, favoriteTracks[1].path);
    expect(
      playback.currentQueueForTest.map((track) => track.path),
      favoriteTracks.map((track) => track.path),
    );
    expect(playback.playing, isFalse);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets('shows repeated playback failures as separate events', (
    tester,
  ) async {
    final library = _InjectedLibraryController();
    final playback = _InjectedPlaybackController();

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: DateTime.now,
    );

    playback.emitPlaybackErrorForTest('Could not seek: test failure');
    tester.binding.scheduleFrame();
    await tester.pumpAndSettle();
    expect(find.text('Could not seek: test failure'), findsOneWidget);

    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold)),
    ).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(find.text('Could not seek: test failure'), findsNothing);

    playback.emitPlaybackErrorForTest('Could not seek: test failure');
    tester.binding.scheduleFrame();
    await tester.pumpAndSettle();
    expect(find.text('Could not seek: test failure'), findsOneWidget);

    await _disposeLibraryScreen(tester, library, playback);
  });
}

class _LibraryFixture {
  _LibraryFixture.album()
    : album = const AlbumSummary(
        folderPath: '/music/Artist/Album',
        title: 'Album',
        albumArtist: 'Artist',
        year: 2026,
        trackCount: 1,
        coverArtPath: null,
      ),
      tracks = [
        _track(
          '/music/Artist/Album/01 Opening.flac',
          folderPath: '/music/Artist/Album',
          title: 'Opening',
          album: 'Album',
          artist: 'Artist',
        ),
      ];

  final AlbumSummary album;
  final List<Track> tracks;
}

Future<void> _pumpLibraryScreen(
  WidgetTester tester, {
  required _InjectedLibraryController library,
  required _InjectedPlaybackController playback,
  required LibraryScreenClock now,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: LibraryScreen(
        themeMode: ThemeMode.light,
        onThemeModeChanged: (_) {},
        libraryController: library,
        playbackController: playback,
        now: now,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _disposeLibraryScreen(
  WidgetTester tester,
  _InjectedLibraryController library,
  _InjectedPlaybackController playback,
) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  playback.disposeForTest();
  library.disposeForTest();
}

Track _track(
  String path, {
  required String folderPath,
  required String title,
  required String album,
  required String artist,
}) {
  return Track(
    path: path,
    folderPath: folderPath,
    title: title,
    artist: artist,
    album: album,
    albumArtist: artist,
    trackNumber: 1,
    discNumber: null,
    year: 2026,
    durationMs: 180000,
    sizeBytes: 42,
    modifiedMs: 1,
    coverArtPath: null,
  );
}

List<Track> _favoriteTracks(int count) {
  return [
    for (var index = 0; index < count; index += 1)
      _track(
        '/music/Favorites/${index + 1}.flac',
        folderPath: '/music/Favorites',
        title: 'Favorite ${index + 1}',
        album: 'Favorites',
        artist: 'Artist $index',
      ),
  ];
}

bool _sameTrackOrder(List<Track> left, List<Track> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index].path != right[index].path) {
      return false;
    }
  }
  return true;
}

class _InjectedLibraryController extends LibraryController {
  _InjectedLibraryController({
    this.canEditMusicRoot = false,
    List<Track> tracks = const [],
    List<FolderSummary> folders = const [],
    List<AlbumSummary> albums = const [],
    List<Track> favoriteTracks = const [],
    Map<String, List<Track>> tracksByFolder = const {},
    this.lastPlaybackState,
    this.canRestorePlayback = false,
  }) : _tracks = List.unmodifiable(tracks),
       _folders = List.unmodifiable(folders),
       _albums = List.unmodifiable(albums),
       _favoriteTracks = List.unmodifiable(favoriteTracks),
       _tracksByFolder = Map.unmodifiable(tracksByFolder);

  bool opened = false;
  bool disposedByScreen = false;
  final bool canEditMusicRoot;
  final List<Track> _tracks;
  final List<FolderSummary> _folders;
  final List<AlbumSummary> _albums;
  final List<Track> _favoriteTracks;
  final Map<String, List<Track>> _tracksByFolder;
  final LastPlaybackState? lastPlaybackState;
  final bool canRestorePlayback;
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
  List<Track> get tracks => _tracks;

  @override
  List<FolderSummary> get folders => _folders;

  @override
  List<AlbumSummary> get albums => _albums;

  @override
  List<Track> get favoriteTracks => _favoriteTracks;

  @override
  Set<String> get favoriteTrackPaths =>
      _favoriteTracks.map((track) => track.path).toSet();

  @override
  Map<String, String?> get trackCoverCache => const {};

  @override
  LastPlaybackState? get lastPlayback => lastPlaybackState;

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
  bool get canRestoreLastPlayback => canRestorePlayback;

  @override
  List<FolderSummary> get playlistFolders => _folders
      .where((folder) => folder.kind == FolderKind.playlist)
      .toList(growable: false);

  @override
  int get playlistCount => playlistFolders.length;

  @override
  int get favoriteCount => _favoriteTracks.length;

  @override
  Map<String, List<Track>> get tracksByFolder => _tracksByFolder;
}

class _InjectedPlaybackController extends PlaybackController {
  _InjectedPlaybackController({
    Track? currentTrack,
    bool playing = false,
    List<Track> currentQueue = const [],
  }) {
    _currentTrack = currentTrack;
    _playing = playing;
    _currentQueue = List.unmodifiable(currentQueue);
  }

  bool disposedByScreen = false;
  AudioOutputSettings? appliedAudioOutputSettings;
  int toggleCount = 0;
  int restoreCount = 0;
  Track? _currentTrack;
  bool _playing = false;
  List<Track> _currentQueue = const [];
  String? _playbackError;
  int _playbackErrorRevision = 0;

  @override
  Track? get currentTrack => _currentTrack;

  @override
  bool get playing => _playing;

  @override
  AudioDevice get audioDevice => const AudioDevice('auto', '');

  @override
  List<AudioDevice> get audioDevices => const [AudioDevice('auto', '')];

  List<Track> get currentQueueForTest => _currentQueue;

  @override
  String? get audioOutputWarning => null;

  @override
  String? get audioOutputError => null;

  @override
  String? get playbackError => _playbackError;

  @override
  int get playbackErrorRevision => _playbackErrorRevision;

  void emitPlaybackErrorForTest(String message) {
    _playbackError = message;
    _playbackErrorRevision += 1;
    notifyListeners();
  }

  @override
  bool isCurrentQueue(List<Track> queue) {
    if (_currentQueue.length != queue.length) {
      return false;
    }
    for (var index = 0; index < queue.length; index += 1) {
      if (_currentQueue[index].path != queue[index].path) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<void> applyAudioOutputSettings(AudioOutputSettings settings) async {
    appliedAudioOutputSettings = settings;
  }

  @override
  Future<void> togglePlayPause(List<Track> defaultQueue) async {
    toggleCount += 1;
    _playing = !_playing;
    notifyListeners();
  }

  @override
  Future<void> playQueueFrom(List<Track> queue, Track track) async {
    _currentQueue = queue;
    _currentTrack = track;
    _playing = true;
    notifyListeners();
  }

  @override
  Future<void> restoreQueueFrom(
    List<Track> queue,
    Track track, {
    required bool play,
  }) async {
    restoreCount += 1;
    _currentQueue = List.unmodifiable(queue);
    _currentTrack = track;
    _playing = play;
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
}
