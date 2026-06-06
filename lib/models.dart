import 'dart:io';

import 'package:path/path.dart' as p;

const defaultMusicRoot = '/mnt/data/music';

enum FolderKind {
  album('album'),
  playlist('playlist'),
  mixed('mixed'),
  unknown('unknown');

  const FolderKind(this.dbValue);

  final String dbValue;

  static FolderKind fromDb(String value) {
    return FolderKind.values.firstWhere(
      (kind) => kind.dbValue == value,
      orElse: () => FolderKind.unknown,
    );
  }
}

class Track {
  const Track({
    this.id,
    required this.path,
    required this.folderPath,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumArtist,
    required this.trackNumber,
    required this.discNumber,
    required this.year,
    required this.durationMs,
    required this.sizeBytes,
    required this.modifiedMs,
  });

  final int? id;
  final String path;
  final String folderPath;
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final int? durationMs;
  final int sizeBytes;
  final int modifiedMs;

  String get fileName => p.basename(path);
  String get folderName => p.basename(folderPath);

  Track copyWith({int? id}) {
    return Track(
      id: id ?? this.id,
      path: path,
      folderPath: folderPath,
      title: title,
      artist: artist,
      album: album,
      albumArtist: albumArtist,
      trackNumber: trackNumber,
      discNumber: discNumber,
      year: year,
      durationMs: durationMs,
      sizeBytes: sizeBytes,
      modifiedMs: modifiedMs,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'path': path,
      'folder_path': folderPath,
      'title': title,
      'artist': artist,
      'album': album,
      'album_artist': albumArtist,
      'track_number': trackNumber,
      'disc_number': discNumber,
      'year': year,
      'duration_ms': durationMs,
      'size_bytes': sizeBytes,
      'modified_ms': modifiedMs,
    };
  }

  static Track fromMap(Map<String, Object?> map) {
    return Track(
      id: map['id'] as int?,
      path: map['path'] as String,
      folderPath: map['folder_path'] as String,
      title: map['title'] as String,
      artist: map['artist'] as String,
      album: map['album'] as String,
      albumArtist: map['album_artist'] as String,
      trackNumber: map['track_number'] as int?,
      discNumber: map['disc_number'] as int?,
      year: map['year'] as int?,
      durationMs: map['duration_ms'] as int?,
      sizeBytes: map['size_bytes'] as int,
      modifiedMs: map['modified_ms'] as int,
    );
  }
}

class FolderSummary {
  const FolderSummary({
    required this.path,
    required this.name,
    required this.kind,
    required this.confidence,
    required this.trackCount,
    required this.albumCount,
    required this.albumArtistCount,
    required this.artistCount,
    required this.yearCount,
  });

  final String path;
  final String name;
  final FolderKind kind;
  final double confidence;
  final int trackCount;
  final int albumCount;
  final int albumArtistCount;
  final int artistCount;
  final int yearCount;

  Map<String, Object?> toMap() {
    return {
      'path': path,
      'name': name,
      'kind': kind.dbValue,
      'confidence': confidence,
      'track_count': trackCount,
      'album_count': albumCount,
      'album_artist_count': albumArtistCount,
      'artist_count': artistCount,
      'year_count': yearCount,
    };
  }

  static FolderSummary fromMap(Map<String, Object?> map) {
    return FolderSummary(
      path: map['path'] as String,
      name: map['name'] as String,
      kind: FolderKind.fromDb(map['kind'] as String),
      confidence: map['confidence'] as double,
      trackCount: map['track_count'] as int,
      albumCount: map['album_count'] as int,
      albumArtistCount: map['album_artist_count'] as int,
      artistCount: map['artist_count'] as int,
      yearCount: map['year_count'] as int,
    );
  }
}

class AlbumSummary {
  const AlbumSummary({
    required this.folderPath,
    required this.title,
    required this.albumArtist,
    required this.year,
    required this.trackCount,
  });

  final String folderPath;
  final String title;
  final String albumArtist;
  final int? year;
  final int trackCount;

  Map<String, Object?> toMap() {
    return {
      'folder_path': folderPath,
      'title': title,
      'album_artist': albumArtist,
      'year': year,
      'track_count': trackCount,
    };
  }

  static AlbumSummary fromMap(Map<String, Object?> map) {
    return AlbumSummary(
      folderPath: map['folder_path'] as String,
      title: map['title'] as String,
      albumArtist: map['album_artist'] as String,
      year: map['year'] as int?,
      trackCount: map['track_count'] as int,
    );
  }
}

class ScanResult {
  const ScanResult({
    required this.rootPath,
    required this.engine,
    required this.tracks,
    required this.folders,
    required this.albums,
    required this.elapsed,
  });

  final String rootPath;
  final String engine;
  final List<Track> tracks;
  final List<FolderSummary> folders;
  final List<AlbumSummary> albums;
  final Duration elapsed;
}

class ScanProgress {
  const ScanProgress({
    required this.filesSeen,
    required this.tracksParsed,
    required this.currentPath,
  });

  final int filesSeen;
  final int tracksParsed;
  final String currentPath;
}

bool isAudioPath(String path) {
  final extension = p.extension(path).toLowerCase();
  return extension == '.flac';
}

String logicalFolderFor(File file) {
  final parent = file.parent.path;
  final name = p.basename(parent).toLowerCase();
  final isDiscFolder = RegExp(r'^(disc|disk|cd)\s*[\divx]+$').hasMatch(name);
  if (isDiscFolder) {
    return p.dirname(parent);
  }
  return parent;
}
