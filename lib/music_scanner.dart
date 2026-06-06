import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'flac_metadata.dart';
import 'models.dart';
import 'rust_music_scanner.dart';

typedef ScanProgressCallback = void Function(ScanProgress progress);

Future<void> _rustScanWorker(List<Object?> message) async {
  final rootPath = message[0] as String;
  final coverCacheDir = message[1] as String;
  final resultPort = message[2] as SendPort;
  final progressPort = message[3] as SendPort?;

  try {
    final scanner = RustMusicScanner.tryLoad();
    if (scanner == null) {
      throw StateError('Rust scanner became unavailable in worker isolate');
    }
    final result = await scanner.scan(
      rootPath,
      coverCacheDir,
      onProgress: progressPort == null
          ? null
          : (progress) {
              progressPort.send([
                progress.filesSeen,
                progress.tracksParsed,
                progress.currentPath,
              ]);
            },
    );
    resultPort.send([true, result]);
  } catch (error, stackTrace) {
    resultPort.send([false, error.toString(), stackTrace.toString()]);
  }
}

class MusicScanner {
  RustMusicScanner? _rustScanner;

  Future<ScanResult> scan(
    String rootPath, {
    ScanProgressCallback? onProgress,
  }) async {
    final rustScanner = _loadRustScanner();
    if (rustScanner != null) {
      final coverCacheDir = await _coverCacheDir();
      onProgress?.call(
        ScanProgress(filesSeen: 0, tracksParsed: 0, currentPath: rootPath),
      );
      final shouldForwardProgress = onProgress != null;
      final progressPort = shouldForwardProgress ? ReceivePort() : null;
      StreamSubscription<Object?>? progressSub;
      final progressListener = onProgress;
      if (progressPort != null && progressListener != null) {
        progressSub = progressPort.listen((message) {
          if (message case [
            final int filesSeen,
            final int tracksParsed,
            final String path,
          ]) {
            progressListener(
              ScanProgress(
                filesSeen: filesSeen,
                tracksParsed: tracksParsed,
                currentPath: path,
              ),
            );
          }
        });
      }
      final progressSendPort = progressPort?.sendPort;
      final resultPort = ReceivePort();
      Isolate? worker;
      try {
        worker = await Isolate.spawn<List<Object?>>(_rustScanWorker, [
          rootPath,
          coverCacheDir,
          resultPort.sendPort,
          shouldForwardProgress ? progressSendPort : null,
        ]);
        final message = await resultPort.first;
        final result = switch (message) {
          [true, final ScanResult result] => result,
          [false, final String error, _] => throw StateError(error),
          _ => throw const FormatException('Unexpected Rust scanner response'),
        };
        onProgress?.call(
          ScanProgress(
            filesSeen: result.tracks.length,
            tracksParsed: result.tracks.length,
            currentPath: rootPath,
          ),
        );
        return result;
      } finally {
        worker?.kill(priority: Isolate.immediate);
        resultPort.close();
        await progressSub?.cancel();
        progressPort?.close();
      }
    }

    final stopwatch = Stopwatch()..start();
    final root = Directory(rootPath);
    if (!await root.exists()) {
      throw FileSystemException('Music root does not exist', rootPath);
    }

    final tracks = <Track>[];
    var filesSeen = 0;

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !isAudioPath(entity.path)) {
        continue;
      }

      filesSeen++;
      final track = await _parseTrack(entity);
      tracks.add(track);

      if (filesSeen == 1 || filesSeen % 25 == 0) {
        onProgress?.call(
          ScanProgress(
            filesSeen: filesSeen,
            tracksParsed: tracks.length,
            currentPath: entity.path,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }
    }

    tracks.sort(_compareTracks);
    final folders = _classifyFolders(tracks);
    final albums = _buildAlbums(tracks, folders);
    stopwatch.stop();

    onProgress?.call(
      ScanProgress(
        filesSeen: filesSeen,
        tracksParsed: tracks.length,
        currentPath: rootPath,
      ),
    );

    return ScanResult(
      rootPath: rootPath,
      engine: 'dart',
      tracks: tracks,
      folders: folders,
      albums: albums,
      elapsed: stopwatch.elapsed,
      coversCached: 0,
    );
  }

  RustMusicScanner? _loadRustScanner() {
    if (Platform.environment['MIAOSIC_DISABLE_RUST_SCANNER'] == '1') {
      return null;
    }
    return _rustScanner ??= RustMusicScanner.tryLoad();
  }

  Future<String> _coverCacheDir() async {
    final env = Platform.environment;
    final dataHome =
        env['XDG_DATA_HOME'] ??
        (env['HOME'] == null
            ? p.join(Directory.systemTemp.path, 'miaosic')
            : p.join(env['HOME']!, '.local', 'share'));
    final dir = Directory(p.join(dataHome, 'com.example.miaosic', 'covers'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  Future<Track> _parseTrack(File file) async {
    final stat = await file.stat();
    final metadata = await readFlacMetadata(file);
    final tags = metadata.tags;
    final fallback = _parseFileName(file.path);

    final title = _firstTag(tags, ['TITLE']) ?? fallback.title;
    final artist = _firstTag(tags, ['ARTIST']) ?? fallback.artist;
    final album = _firstTag(tags, ['ALBUM']) ?? '';
    final albumArtist =
        _firstTag(tags, ['ALBUMARTIST', 'ALBUM_ARTIST']) ?? artist;

    return Track(
      path: file.path,
      folderPath: logicalFolderFor(file),
      title: title,
      artist: artist,
      album: album,
      albumArtist: albumArtist,
      trackNumber: _parseNumber(_firstTag(tags, ['TRACKNUMBER', 'TRACK'])),
      discNumber: _parseNumber(_firstTag(tags, ['DISCNUMBER', 'DISC'])),
      year: _parseYear(_firstTag(tags, ['DATE', 'YEAR'])),
      durationMs: metadata.durationMs,
      sizeBytes: stat.size,
      modifiedMs: stat.modified.millisecondsSinceEpoch,
      coverArtPath: null,
    );
  }

  List<FolderSummary> _classifyFolders(List<Track> tracks) {
    final grouped = <String, List<Track>>{};
    for (final track in tracks) {
      grouped.putIfAbsent(track.folderPath, () => []).add(track);
    }

    final folders = <FolderSummary>[];
    for (final entry in grouped.entries) {
      final folderTracks = entry.value;
      final albums = _nonEmptySet(folderTracks.map((track) => track.album));
      final albumArtists = _nonEmptySet(
        folderTracks.map((track) => track.albumArtist),
      );
      final artists = _nonEmptySet(folderTracks.map((track) => track.artist));
      final years = folderTracks
          .map((track) => track.year)
          .whereType<int>()
          .toSet();
      final kind = _detectFolderKind(
        path: entry.key,
        tracks: folderTracks,
        albumCount: albums.length,
        albumArtistCount: albumArtists.length,
        artistCount: artists.length,
        yearCount: years.length,
      );

      folders.add(
        FolderSummary(
          path: entry.key,
          name: p.basename(entry.key),
          kind: kind.kind,
          confidence: kind.confidence,
          trackCount: folderTracks.length,
          albumCount: albums.length,
          albumArtistCount: albumArtists.length,
          artistCount: artists.length,
          yearCount: years.length,
          coverArtPath: _dominant(
            folderTracks.map((track) => track.coverArtPath ?? ''),
          ),
        ),
      );
    }

    folders.sort((a, b) {
      final kindCompare = a.kind.dbValue.compareTo(b.kind.dbValue);
      if (kindCompare != 0) {
        return kindCompare;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return folders;
  }

  List<AlbumSummary> _buildAlbums(
    List<Track> tracks,
    List<FolderSummary> folders,
  ) {
    final albumFolderPaths = folders
        .where((folder) => folder.kind == FolderKind.album)
        .map((folder) => folder.path)
        .toSet();
    final grouped = <String, List<Track>>{};
    for (final track in tracks) {
      if (albumFolderPaths.contains(track.folderPath)) {
        grouped.putIfAbsent(track.folderPath, () => []).add(track);
      }
    }

    final albums = <AlbumSummary>[];
    for (final entry in grouped.entries) {
      final folderTracks = entry.value;
      final albumTitle =
          _dominant(folderTracks.map((track) => track.album)) ??
          p.basename(entry.key);
      final albumArtist =
          _dominant(folderTracks.map((track) => track.albumArtist)) ??
          _dominant(folderTracks.map((track) => track.artist)) ??
          'Unknown Artist';
      final year = _dominantInt(folderTracks.map((track) => track.year));
      albums.add(
        AlbumSummary(
          folderPath: entry.key,
          title: albumTitle,
          albumArtist: albumArtist,
          year: year,
          trackCount: folderTracks.length,
          coverArtPath: _dominant(
            folderTracks.map((track) => track.coverArtPath ?? ''),
          ),
        ),
      );
    }

    albums.sort((a, b) {
      final artistCompare = a.albumArtist.toLowerCase().compareTo(
        b.albumArtist.toLowerCase(),
      );
      if (artistCompare != 0) {
        return artistCompare;
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return albums;
  }

  _DetectedKind _detectFolderKind({
    required String path,
    required List<Track> tracks,
    required int albumCount,
    required int albumArtistCount,
    required int artistCount,
    required int yearCount,
  }) {
    final trackCount = tracks.length;
    var albumScore = 0;
    var playlistScore = 0;
    final folderName = p.basename(path).toLowerCase();

    final dominantAlbumRatio = _dominantRatio(
      tracks.map((track) => track.album),
    );
    final dominantAlbumArtistRatio = _dominantRatio(
      tracks.map((track) => track.albumArtist),
    );
    final trackNumbers = tracks
        .map((track) => track.trackNumber)
        .whereType<int>()
        .toList();
    final hasMostlyOrderedTracks =
        trackNumbers.length >= trackCount * 0.75 &&
        _isMostlySequential(trackNumbers);

    if (trackCount <= 45) {
      albumScore += 2;
    }
    if (dominantAlbumRatio >= 0.85) {
      albumScore += 4;
    }
    if (dominantAlbumArtistRatio >= 0.85 || albumArtistCount <= 2) {
      albumScore += 3;
    }
    if (yearCount <= 2) {
      albumScore += 1;
    }
    if (hasMostlyOrderedTracks) {
      albumScore += 2;
    }
    if (RegExp(r'\(\d{4}\)$').hasMatch(folderName)) {
      albumScore += 1;
    }

    if (trackCount >= 40) {
      playlistScore += 3;
    }
    if (albumCount >= 10 || albumCount >= trackCount * 0.45) {
      playlistScore += 4;
    }
    if (albumArtistCount >= 8 || artistCount >= 10) {
      playlistScore += 3;
    }
    if (yearCount >= 5) {
      playlistScore += 1;
    }
    if (_playlistNamePattern.hasMatch(folderName)) {
      playlistScore += 3;
    }
    if (trackNumbers.length < trackCount * 0.55) {
      playlistScore += 1;
    }

    if (playlistScore >= albumScore + 2 && playlistScore >= 5) {
      return _DetectedKind(
        FolderKind.playlist,
        _confidence(playlistScore, albumScore),
      );
    }
    if (albumScore >= playlistScore + 2 && albumScore >= 6) {
      return _DetectedKind(
        FolderKind.album,
        _confidence(albumScore, playlistScore),
      );
    }
    return _DetectedKind(FolderKind.mixed, 0.5);
  }

  static final _playlistNamePattern = RegExp(
    r'(hits|best|essentials|classic|focus|road|trip|pop|rap|rock|r&b|k-pop|playlist|精选|歌单)',
  );

  double _confidence(int winner, int loser) {
    return (0.5 + (winner - loser).clamp(0, 8) / 16).clamp(0.5, 0.99);
  }

  Set<String> _nonEmptySet(Iterable<String> values) {
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  double _dominantRatio(Iterable<String> values) {
    final counts = <String, int>{};
    var total = 0;
    for (final value in values) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty) {
        continue;
      }
      counts[normalized] = (counts[normalized] ?? 0) + 1;
      total++;
    }
    if (total == 0 || counts.isEmpty) {
      return 0;
    }
    return counts.values.reduce((a, b) => a > b ? a : b) / total;
  }

  String? _dominant(Iterable<String> values) {
    final counts = <String, int>{};
    final originals = <String, String>{};
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final normalized = trimmed.toLowerCase();
      counts[normalized] = (counts[normalized] ?? 0) + 1;
      originals[normalized] = trimmed;
    }
    if (counts.isEmpty) {
      return null;
    }
    final key = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return originals[key];
  }

  int? _dominantInt(Iterable<int?> values) {
    final dominant = _dominant(
      values.whereType<int>().map((value) => value.toString()),
    );
    return dominant == null ? null : int.tryParse(dominant);
  }

  bool _isMostlySequential(List<int> values) {
    if (values.isEmpty) {
      return false;
    }
    final unique = values.toSet().toList()..sort();
    if (unique.length <= 1) {
      return false;
    }
    var adjacent = 0;
    for (var i = 1; i < unique.length; i++) {
      if (unique[i] - unique[i - 1] == 1) {
        adjacent++;
      }
    }
    return adjacent >= unique.length * 0.7;
  }

  static int _compareTracks(Track a, Track b) {
    final folderCompare = a.folderPath.toLowerCase().compareTo(
      b.folderPath.toLowerCase(),
    );
    if (folderCompare != 0) {
      return folderCompare;
    }
    final discCompare = (a.discNumber ?? 0).compareTo(b.discNumber ?? 0);
    if (discCompare != 0) {
      return discCompare;
    }
    final trackCompare = (a.trackNumber ?? 9999).compareTo(
      b.trackNumber ?? 9999,
    );
    if (trackCompare != 0) {
      return trackCompare;
    }
    return a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
  }
}

class _DetectedKind {
  const _DetectedKind(this.kind, this.confidence);

  final FolderKind kind;
  final double confidence;
}

class _FileNameFallback {
  const _FileNameFallback({required this.title, required this.artist});

  final String title;
  final String artist;
}

String? _firstTag(Map<String, String> tags, List<String> keys) {
  for (final key in keys) {
    final value = tags[key];
    if (value != null && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

int? _parseNumber(String? value) {
  if (value == null) {
    return null;
  }
  final match = RegExp(r'\d+').firstMatch(value);
  return match == null ? null : int.tryParse(match.group(0)!);
}

int? _parseYear(String? value) {
  if (value == null) {
    return null;
  }
  final match = RegExp(r'(19|20)\d{2}').firstMatch(value);
  return match == null ? null : int.tryParse(match.group(0)!);
}

_FileNameFallback _parseFileName(String path) {
  final stem = p.basenameWithoutExtension(path);
  final withoutNumber = stem.replaceFirst(RegExp(r'^\d+\.\s*'), '');
  final separator = withoutNumber.indexOf(' - ');
  if (separator > 0) {
    return _FileNameFallback(
      artist: withoutNumber.substring(0, separator).trim(),
      title: withoutNumber.substring(separator + 3).trim(),
    );
  }
  return _FileNameFallback(
    title: withoutNumber.trim(),
    artist: 'Unknown Artist',
  );
}
