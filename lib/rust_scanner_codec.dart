import 'models.dart';

// Incremental requests are a native protocol, independent of database rows.
Map<String, Object?> encodeRustTrack(Track track) => {
  'path': track.path,
  'folder_path': track.folderPath,
  'title': track.title,
  'artist': track.artist,
  'album': track.album,
  'album_artist': track.albumArtist,
  'track_number': track.trackNumber,
  'disc_number': track.discNumber,
  'year': track.year,
  'duration_ms': track.durationMs,
  'size_bytes': track.sizeBytes,
  'modified_ms': track.modifiedMs,
  // Folder covers are recomputed by Rust, rather than reused from storage.
};

class RustTrackCoverResult {
  const RustTrackCoverResult({required this.path, required this.coverArtPath});

  final String path;
  final String? coverArtPath;

  static RustTrackCoverResult fromJson(Map<String, Object?> json) {
    return RustTrackCoverResult(
      path: json['path'] as String,
      coverArtPath: json['cover_art_path'] as String?,
    );
  }
}

ScanResult decodeRustScanResult(Map<String, Object?> json) {
  return ScanResult(
    rootPath: json['root_path'] as String,
    engine: 'rust',
    tracks: _list(json['tracks']).map(_trackFromJson).toList(),
    folders: _list(json['folders']).map(_folderFromJson).toList(),
    albums: _list(json['albums']).map(_albumFromJson).toList(),
    elapsed: Duration(milliseconds: _int(json['elapsed_ms']) ?? 0),
    coversCached: _int(json['covers_cached']) ?? 0,
  );
}

Track _trackFromJson(Map<String, Object?> json) {
  return Track(
    path: json['path'] as String,
    folderPath: json['folder_path'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    album: json['album'] as String,
    albumArtist: json['album_artist'] as String,
    trackNumber: _int(json['track_number']),
    discNumber: _int(json['disc_number']),
    year: _int(json['year']),
    durationMs: _int(json['duration_ms']),
    sizeBytes: _int(json['size_bytes']) ?? 0,
    modifiedMs: _int(json['modified_ms']) ?? 0,
    coverArtPath: json['cover_art_path'] as String?,
  );
}

FolderSummary _folderFromJson(Map<String, Object?> json) {
  return FolderSummary(
    path: json['path'] as String,
    name: json['name'] as String,
    kind: FolderKind.fromDb(json['kind'] as String),
    confidence: _double(json['confidence']),
    trackCount: _int(json['track_count']) ?? 0,
    albumCount: _int(json['album_count']) ?? 0,
    albumArtistCount: _int(json['album_artist_count']) ?? 0,
    artistCount: _int(json['artist_count']) ?? 0,
    yearCount: _int(json['year_count']) ?? 0,
    coverArtPath: json['cover_art_path'] as String?,
  );
}

AlbumSummary _albumFromJson(Map<String, Object?> json) {
  return AlbumSummary(
    folderPath: json['folder_path'] as String,
    title: json['title'] as String,
    albumArtist: json['album_artist'] as String,
    year: _int(json['year']),
    trackCount: _int(json['track_count']) ?? 0,
    coverArtPath: json['cover_art_path'] as String?,
  );
}

Iterable<Map<String, Object?>> _list(Object? value) {
  return (value as List<Object?>).cast<Map<String, Object?>>();
}

int? _int(Object? value) {
  if (value == null) {
    return null;
  }
  return (value as num).toInt();
}

double _double(Object? value) {
  return (value as num).toDouble();
}
