use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Serialize)]
pub(crate) struct ScanResponse {
    pub ok: bool,
    pub error: Option<String>,
    pub result: Option<ScanResult>,
}

#[derive(Serialize)]
pub(crate) struct TrackCoverResponse {
    pub ok: bool,
    pub error: Option<String>,
    pub result: Option<Vec<TrackCoverResult>>,
}

#[derive(Serialize)]
pub(crate) struct TrackCoverResult {
    pub path: String,
    pub cover_art_path: Option<String>,
}

#[derive(Deserialize)]
pub(crate) struct TrackCoverRequest {
    pub paths: Vec<String>,
}

#[derive(Deserialize)]
pub(crate) struct IncrementalScanRequest {
    pub previous_tracks: Vec<Track>,
}

#[derive(Serialize)]
pub(crate) struct ScanResult {
    pub root_path: String,
    pub tracks: Vec<Track>,
    pub folders: Vec<FolderSummary>,
    pub albums: Vec<AlbumSummary>,
    pub elapsed_ms: u128,
    pub covers_cached: u64,
    pub skipped_files: u64,
    pub error_samples: Vec<String>,
}

#[derive(Clone, Deserialize, Serialize)]
pub(crate) struct Track {
    pub path: String,
    pub folder_path: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub album_artist: String,
    pub track_number: Option<i64>,
    pub disc_number: Option<i64>,
    pub year: Option<i64>,
    pub duration_ms: Option<i64>,
    pub size_bytes: i64,
    pub modified_ms: i64,
    #[serde(default)]
    pub cover_art_path: Option<String>,
}

#[derive(Default)]
pub(crate) struct ScanIssues {
    pub skipped_files: u64,
    pub error_samples: Vec<String>,
}

impl ScanIssues {
    pub(crate) fn skip_file(&mut self, sample: impl Into<String>) {
        self.skipped_files += 1;
        self.note(sample);
    }

    pub(crate) fn note(&mut self, sample: impl Into<String>) {
        if self.error_samples.len() < 8 {
            self.error_samples.push(sample.into());
        }
    }
}

#[derive(Clone, Serialize)]
pub(crate) struct FolderSummary {
    pub path: String,
    pub name: String,
    pub kind: String,
    pub confidence: f64,
    pub track_count: i64,
    pub album_count: i64,
    pub album_artist_count: i64,
    pub artist_count: i64,
    pub year_count: i64,
    pub cover_art_path: Option<String>,
}

#[derive(Serialize)]
pub(crate) struct AlbumSummary {
    pub folder_path: String,
    pub title: String,
    pub album_artist: String,
    pub year: Option<i64>,
    pub track_count: i64,
    pub cover_art_path: Option<String>,
}

pub(crate) struct FlacMetadata {
    pub tags: HashMap<String, String>,
    pub duration_ms: Option<i64>,
}

pub(crate) struct FileNameFallback {
    pub title: String,
    pub artist: String,
}

pub(crate) struct CoverImage {
    pub bytes: Vec<u8>,
    pub extension: &'static str,
}
