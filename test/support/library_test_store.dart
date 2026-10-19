import 'package:miaosic/library_database.dart';
import 'package:miaosic/models.dart';
import 'package:miaosic/music_scanner.dart';
import 'package:miaosic/playlist_cover_indexer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Real in-memory persistence with controllable scan results and no cover worker.
class LibraryTestStore {
  LibraryTestStore({
    List<Track> tracks = const [],
    List<FolderSummary> folders = const [],
    List<AlbumSummary> albums = const [],
    this.favoriteTracks = const [],
    this.lastPlayback,
  }) : scanner = FakeMusicScanner(
         ScanResult(
           rootPath: '/music',
           engine: 'test',
           tracks: tracks,
           folders: folders,
           albums: albums,
           elapsed: Duration.zero,
           coversCached: 0,
         ),
       );

  final FakeMusicScanner scanner;
  final List<Track> favoriteTracks;
  final LastPlaybackState? lastPlayback;

  Future<LibraryDatabase> open() async {
    final database = await LibraryDatabase.openAtPath(
      inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
    await database.saveMusicRoot('/music');
    await database.replaceLibrary(scanner.result);
    for (final track in favoriteTracks.reversed) {
      await database.setTrackFavorite(track.path, true);
    }
    final saved = lastPlayback;
    if (saved != null) await database.saveLastPlayback(saved);
    return database;
  }

  void setScanTracks(List<Track> tracks) {
    final previous = scanner.result;
    scanner.result = ScanResult(
      rootPath: previous.rootPath,
      engine: 'test',
      tracks: tracks,
      folders: previous.folders,
      albums: previous.albums,
      elapsed: Duration.zero,
      coversCached: 0,
    );
  }
}

class FakeMusicScanner extends MusicScanner {
  FakeMusicScanner(this.result) : super(rustScannerLoader: () => null);

  ScanResult result;

  @override
  Future<ScanResult> scan(
    String rootPath, {
    ScanProgressCallback? onProgress,
    List<Track>? previousTracks,
  }) async => result;
}

class NoopTrackCoverIndexer extends TrackCoverIndexer {
  @override
  Future<bool> indexTracks({
    required List<Track> tracks,
    required LibraryDatabase database,
    Map<String, String?>? knownCache,
    required bool Function() shouldPause,
    required TrackCoverCacheUpdated onCacheUpdated,
  }) async => false; // Do not prune the real cover cache from a widget test.
}
