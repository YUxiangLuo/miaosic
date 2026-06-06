import 'models.dart';

class LibrarySnapshot {
  const LibrarySnapshot({
    required this.tracks,
    required this.folders,
    required this.albums,
    required this.scanState,
  });

  final List<Track> tracks;
  final List<FolderSummary> folders;
  final List<AlbumSummary> albums;
  final Map<String, Object?>? scanState;
}

class LibraryDiff {
  const LibraryDiff({
    required this.added,
    required this.removed,
    required this.modified,
    required this.unchangedCount,
    required this.result,
  });

  final List<TrackChange> added;
  final List<TrackChange> removed;
  final List<TrackChange> modified;
  final int unchangedCount;
  final ScanResult result;

  int get totalChanges => added.length + removed.length + modified.length;
  bool get hasChanges => totalChanges > 0;

  DeletionRisk deletionRisk({
    int absoluteThreshold = 100,
    double ratioThreshold = 0.1,
  }) {
    final oldTotal = unchangedCount + removed.length + modified.length;
    final ratio = oldTotal == 0 ? 0.0 : removed.length / oldTotal;
    return DeletionRisk(
      isLargeDeletion:
          removed.length >= absoluteThreshold || ratio >= ratioThreshold,
      removedCount: removed.length,
      removedRatio: ratio,
    );
  }
}

class TrackChange {
  const TrackChange({
    required this.path,
    required this.oldTrack,
    required this.newTrack,
    required this.reason,
  });

  final String path;
  final Track? oldTrack;
  final Track? newTrack;
  final TrackChangeReason reason;
}

enum TrackChangeReason { added, removed, fileChanged }

class DeletionRisk {
  const DeletionRisk({
    required this.isLargeDeletion,
    required this.removedCount,
    required this.removedRatio,
  });

  final bool isLargeDeletion;
  final int removedCount;
  final double removedRatio;
}

LibraryDiff diffLibrary(LibrarySnapshot oldSnapshot, ScanResult newResult) {
  final oldByPath = {for (final track in oldSnapshot.tracks) track.path: track};
  final newByPath = {for (final track in newResult.tracks) track.path: track};

  final added = <TrackChange>[];
  final removed = <TrackChange>[];
  final modified = <TrackChange>[];
  var unchangedCount = 0;

  for (final entry in newByPath.entries) {
    final oldTrack = oldByPath[entry.key];
    final newTrack = entry.value;
    if (oldTrack == null) {
      added.add(
        TrackChange(
          path: entry.key,
          oldTrack: null,
          newTrack: newTrack,
          reason: TrackChangeReason.added,
        ),
      );
      continue;
    }
    if (oldTrack.sizeBytes != newTrack.sizeBytes ||
        oldTrack.modifiedMs != newTrack.modifiedMs) {
      modified.add(
        TrackChange(
          path: entry.key,
          oldTrack: oldTrack,
          newTrack: newTrack,
          reason: TrackChangeReason.fileChanged,
        ),
      );
    } else {
      unchangedCount++;
    }
  }

  for (final entry in oldByPath.entries) {
    if (!newByPath.containsKey(entry.key)) {
      removed.add(
        TrackChange(
          path: entry.key,
          oldTrack: entry.value,
          newTrack: null,
          reason: TrackChangeReason.removed,
        ),
      );
    }
  }

  int compareChange(TrackChange a, TrackChange b) => a.path.compareTo(b.path);
  added.sort(compareChange);
  removed.sort(compareChange);
  modified.sort(compareChange);

  return LibraryDiff(
    added: added,
    removed: removed,
    modified: modified,
    unchangedCount: unchangedCount,
    result: newResult,
  );
}
