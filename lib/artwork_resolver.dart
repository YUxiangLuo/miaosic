import 'library_diff.dart';
import 'models.dart';

String? resolveTrackArtwork(Track track, Map<String, String?> trackCoverCache) {
  return trackCoverCache[track.path] ?? track.coverArtPath;
}

String? resolveChangeArtwork(
  TrackChange change,
  Map<String, String?> trackCoverCache,
) {
  final newTrack = change.newTrack;
  final oldTrack = change.oldTrack;
  final track = newTrack ?? oldTrack;
  if (track == null) {
    return null;
  }
  return trackCoverCache[track.path] ??
      newTrack?.coverArtPath ??
      oldTrack?.coverArtPath;
}
