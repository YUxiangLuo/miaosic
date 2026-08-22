use crate::cover::{first_cover_path, first_cover_path_refs};
use crate::models::{AlbumSummary, FolderSummary, Track};
use crate::util::basename;
use std::collections::{HashMap, HashSet};

pub(crate) fn classify_folders(tracks: &[Track]) -> Vec<FolderSummary> {
    let mut grouped: HashMap<String, Vec<Track>> = HashMap::new();
    for track in tracks {
        grouped
            .entry(track.folder_path.clone())
            .or_default()
            .push(track.clone());
    }

    let mut folders = Vec::new();
    for (path, folder_tracks) in grouped {
        let album_count = non_empty_count(folder_tracks.iter().map(|track| track.album.as_str()));
        let album_artist_count = non_empty_count(
            folder_tracks
                .iter()
                .map(|track| track.album_artist.as_str()),
        );
        let artist_count = non_empty_count(folder_tracks.iter().map(|track| track.artist.as_str()));
        let year_count = folder_tracks
            .iter()
            .filter_map(|track| track.year)
            .collect::<HashSet<i64>>()
            .len();
        let (kind, confidence) = detect_folder_kind(
            &path,
            &folder_tracks,
            album_count,
            album_artist_count,
            artist_count,
            year_count,
        );

        folders.push(FolderSummary {
            name: basename(&path),
            path,
            kind,
            confidence,
            track_count: folder_tracks.len() as i64,
            album_count: album_count as i64,
            album_artist_count: album_artist_count as i64,
            artist_count: artist_count as i64,
            year_count: year_count as i64,
            cover_art_path: first_cover_path(&folder_tracks),
        });
    }

    folders.sort_by(|a, b| {
        a.kind
            .cmp(&b.kind)
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    folders
}

pub(crate) fn build_albums(tracks: &[Track], folders: &[FolderSummary]) -> Vec<AlbumSummary> {
    let album_folders = folders
        .iter()
        .filter(|folder| folder.kind == "album")
        .map(|folder| folder.path.as_str())
        .collect::<HashSet<_>>();
    let mut grouped: HashMap<String, Vec<&Track>> = HashMap::new();
    for track in tracks {
        if album_folders.contains(track.folder_path.as_str()) {
            grouped
                .entry(track.folder_path.clone())
                .or_default()
                .push(track);
        }
    }

    let mut albums = Vec::new();
    for (folder_path, folder_tracks) in grouped {
        let title = dominant(folder_tracks.iter().map(|track| track.album.as_str()))
            .unwrap_or_else(|| basename(&folder_path));
        let album_artist = dominant(
            folder_tracks
                .iter()
                .map(|track| track.album_artist.as_str()),
        )
        .or_else(|| dominant(folder_tracks.iter().map(|track| track.artist.as_str())))
        .unwrap_or_else(|| "Unknown Artist".to_string());
        let year = dominant_i64(folder_tracks.iter().filter_map(|track| track.year));

        albums.push(AlbumSummary {
            folder_path,
            title,
            album_artist,
            year,
            track_count: folder_tracks.len() as i64,
            cover_art_path: first_cover_path_refs(&folder_tracks),
        });
    }

    albums.sort_by(|a, b| {
        a.album_artist
            .to_lowercase()
            .cmp(&b.album_artist.to_lowercase())
            .then_with(|| a.title.to_lowercase().cmp(&b.title.to_lowercase()))
    });
    albums
}

pub(crate) fn detect_folder_kind(
    path: &str,
    tracks: &[Track],
    album_count: usize,
    album_artist_count: usize,
    artist_count: usize,
    year_count: usize,
) -> (String, f64) {
    let track_count = tracks.len();
    let mut album_score = 0_i32;
    let mut playlist_score = 0_i32;
    let folder_name = basename(path).to_lowercase();
    let has_playlist_name = is_playlist_name(&folder_name);
    let has_playlist_name_with_source_diversity = has_playlist_name
        && (album_count >= 3 || album_artist_count >= 3 || artist_count >= 3 || year_count >= 3);
    let dominant_album_ratio = dominant_ratio(tracks.iter().map(|track| track.album.as_str()));
    let dominant_album_artist_ratio =
        dominant_ratio(tracks.iter().map(|track| track.album_artist.as_str()));
    let track_numbers = tracks
        .iter()
        .filter_map(|track| track.track_number)
        .collect::<Vec<_>>();
    let has_mostly_ordered_tracks = track_numbers.len() as f64 >= track_count as f64 * 0.75
        && is_mostly_sequential(&track_numbers);

    if track_count <= 45 {
        album_score += 2;
    }
    if dominant_album_ratio >= 0.85 {
        album_score += 4;
    }
    if dominant_album_artist_ratio >= 0.85 || album_artist_count <= 2 {
        album_score += 3;
    }
    if year_count <= 2 {
        album_score += 1;
    }
    if has_mostly_ordered_tracks {
        album_score += 2;
    }
    if has_year_suffix(&folder_name) {
        album_score += 1;
    }

    if track_count >= 40 {
        playlist_score += 3;
    }
    if album_count >= 10 || album_count as f64 >= track_count as f64 * 0.45 {
        playlist_score += 4;
    }
    if album_artist_count >= 8 || artist_count >= 10 {
        playlist_score += 3;
    }
    if year_count >= 5 {
        playlist_score += 1;
    }
    if has_playlist_name {
        playlist_score += 3;
    }
    if has_playlist_name_with_source_diversity {
        playlist_score += 2;
    }
    if (track_numbers.len() as f64) < track_count as f64 * 0.55 {
        playlist_score += 1;
    }

    if album_score >= playlist_score + 2 && album_score >= 6 {
        return ("album".to_string(), confidence(album_score, playlist_score));
    }
    (
        "playlist".to_string(),
        confidence(playlist_score, album_score),
    )
}

fn non_empty_count<'a>(values: impl Iterator<Item = &'a str>) -> usize {
    values
        .map(|value| value.trim().to_lowercase())
        .filter(|value| !value.is_empty())
        .collect::<HashSet<_>>()
        .len()
}

fn dominant_ratio<'a>(values: impl Iterator<Item = &'a str>) -> f64 {
    let mut counts: HashMap<String, usize> = HashMap::new();
    let mut total = 0_usize;
    for value in values {
        let normalized = value.trim().to_lowercase();
        if normalized.is_empty() {
            continue;
        }
        *counts.entry(normalized).or_default() += 1;
        total += 1;
    }
    if total == 0 {
        return 0.0;
    }
    let max = counts.values().copied().max().unwrap_or(0);
    max as f64 / total as f64
}

fn dominant<'a>(values: impl Iterator<Item = &'a str>) -> Option<String> {
    let mut counts: HashMap<String, usize> = HashMap::new();
    let mut originals: HashMap<String, String> = HashMap::new();
    for value in values {
        let trimmed = value.trim();
        if trimmed.is_empty() {
            continue;
        }
        let normalized = trimmed.to_lowercase();
        *counts.entry(normalized.clone()).or_default() += 1;
        originals
            .entry(normalized)
            .or_insert_with(|| trimmed.to_string());
    }
    let key = counts
        .iter()
        .max_by_key(|(_, count)| *count)
        .map(|(key, _)| key.clone())?;
    originals.remove(&key)
}

fn dominant_i64(values: impl Iterator<Item = i64>) -> Option<i64> {
    let mut counts: HashMap<i64, usize> = HashMap::new();
    for value in values {
        *counts.entry(value).or_default() += 1;
    }
    counts
        .iter()
        .max_by_key(|(_, count)| *count)
        .map(|(value, _)| *value)
}

fn is_mostly_sequential(values: &[i64]) -> bool {
    if values.is_empty() {
        return false;
    }
    let mut unique = values
        .iter()
        .copied()
        .collect::<HashSet<_>>()
        .into_iter()
        .collect::<Vec<_>>();
    unique.sort_unstable();
    if unique.len() <= 1 {
        return false;
    }
    let adjacent = unique
        .windows(2)
        .filter(|pair| pair[1] - pair[0] == 1)
        .count();
    adjacent as f64 >= unique.len() as f64 * 0.7
}

fn has_year_suffix(value: &str) -> bool {
    let trimmed = value.trim_end();
    if trimmed.len() < 6 || !trimmed.ends_with(')') {
        return false;
    }
    let Some(open) = trimmed.rfind('(') else {
        return false;
    };
    let year = &trimmed[open + 1..trimmed.len() - 1];
    year.len() == 4 && year.chars().all(|char| char.is_ascii_digit())
}

fn is_playlist_name(value: &str) -> bool {
    [
        "hits",
        "best",
        "essentials",
        "classic",
        "focus",
        "road",
        "trip",
        "pop",
        "rap",
        "rock",
        "r&b",
        "k-pop",
        "playlist",
        "精选",
        "歌单",
    ]
    .iter()
    .any(|needle| value.contains(needle))
}

fn confidence(winner: i32, loser: i32) -> f64 {
    (0.5 + ((winner - loser).clamp(0, 8) as f64 / 16.0)).clamp(0.5, 0.99)
}
