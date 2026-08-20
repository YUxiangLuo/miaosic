use crate::classify::{build_albums, classify_folders};
use crate::cover::{apply_folder_covers, CoverCache};
use crate::flac::{parse_track, track_file_state};
use crate::models::{ScanIssues, ScanResult, Track, TrackCoverRequest, TrackCoverResult};
use crate::util::{compare_tracks, is_audio_path, path_to_utf8};
use std::collections::HashMap;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::time::Instant;
use walkdir::WalkDir;

pub(crate) const PROGRESS_INTERVAL: u64 = 25;
pub(crate) type ProgressCallback =
    extern "C" fn(files_seen: u64, tracks_parsed: u64, current_path: *const std::os::raw::c_char);

pub(crate) struct ProgressReporter {
    callback: Option<ProgressCallback>,
    files_seen: u64,
    tracks_parsed: u64,
}

impl ProgressReporter {
    pub(crate) fn new(callback: Option<ProgressCallback>) -> Self {
        Self {
            callback,
            files_seen: 0,
            tracks_parsed: 0,
        }
    }

    pub(crate) fn seen_file(&mut self) {
        self.files_seen += 1;
    }

    pub(crate) fn parsed_track(&mut self) {
        self.tracks_parsed += 1;
    }

    pub(crate) fn should_emit(&self) -> bool {
        self.files_seen == 1 || self.files_seen % PROGRESS_INTERVAL == 0
    }

    pub(crate) fn emit_path(&self, current_path: &Path) {
        self.emit(current_path);
    }

    fn emit(&self, current_path: &Path) {
        let Some(callback) = self.callback else {
            return;
        };
        let path = current_path.to_string_lossy();
        let Ok(path) = std::ffi::CString::new(path.as_bytes()) else {
            return;
        };
        callback(self.files_seen, self.tracks_parsed, path.as_ptr());
    }
}

pub(crate) fn scan_library(
    root_path: &str,
    cover_cache_dir: Option<&str>,
    progress_callback: Option<ProgressCallback>,
) -> io::Result<ScanResult> {
    let started = Instant::now();
    let root = Path::new(root_path);
    validate_scan_root(root, root_path)?;
    let mut tracks = Vec::new();
    let mut issues = ScanIssues::default();
    let mut cover_cache = CoverCache::new(cover_cache_dir.map(PathBuf::from));
    let mut progress = ProgressReporter::new(progress_callback);
    for entry in WalkDir::new(root).follow_links(false) {
        let entry = match entry {
            Ok(entry) => entry,
            Err(error) => {
                issues.note(error.to_string());
                continue;
            }
        };
        if !entry.file_type().is_file() || !is_audio_path(entry.path()) {
            continue;
        }
        progress.seen_file();
        match parse_track(entry.path()) {
            Ok(track) => {
                tracks.push(track);
                progress.parsed_track();
            }
            Err(error) => issues.skip_file(format!("{}: {error}", entry.path().display())),
        }
        if progress.should_emit() {
            progress.emit_path(entry.path());
        }
    }
    progress.emit_path(root);

    tracks.sort_by(compare_tracks);
    apply_folder_covers(&mut tracks, &mut cover_cache);
    let folders = classify_folders(&tracks);
    let albums = build_albums(&tracks, &folders);

    Ok(ScanResult {
        root_path: root_path.to_string(),
        tracks,
        folders,
        albums,
        elapsed_ms: started.elapsed().as_millis(),
        covers_cached: cover_cache.writes,
        skipped_files: issues.skipped_files,
        error_samples: issues.error_samples,
    })
}

pub(crate) fn scan_library_incremental(
    root_path: &str,
    previous_tracks: Vec<Track>,
    cover_cache_dir: Option<&str>,
    progress_callback: Option<ProgressCallback>,
) -> io::Result<ScanResult> {
    let started = Instant::now();
    let root = Path::new(root_path);
    validate_scan_root(root, root_path)?;
    let previous_by_path = previous_tracks
        .into_iter()
        .map(|track| (track.path.clone(), track))
        .collect::<HashMap<_, _>>();
    let mut tracks = Vec::new();
    let mut issues = ScanIssues::default();
    let mut cover_cache = CoverCache::new(cover_cache_dir.map(PathBuf::from));
    let mut progress = ProgressReporter::new(progress_callback);

    for entry in WalkDir::new(root).follow_links(false) {
        let entry = match entry {
            Ok(entry) => entry,
            Err(error) => {
                issues.note(error.to_string());
                continue;
            }
        };
        if !entry.file_type().is_file() || !is_audio_path(entry.path()) {
            continue;
        }

        progress.seen_file();
        let path = entry.path();
        let path_string = match path_to_utf8(path) {
            Ok(value) => value,
            Err(error) => {
                issues.skip_file(error);
                continue;
            }
        };
        let track = match track_file_state(path) {
            Ok((size_bytes, modified_ms)) => previous_by_path
                .get(&path_string)
                .filter(|track| track.size_bytes == size_bytes && track.modified_ms == modified_ms)
                .cloned()
                .or_else(|| match parse_track(path) {
                    Ok(track) => Some(track),
                    Err(error) => {
                        issues.skip_file(format!("{path_string}: {error}"));
                        None
                    }
                }),
            Err(error) => {
                issues.skip_file(format!("{path_string}: {error}"));
                None
            }
        };

        if let Some(track) = track {
            tracks.push(track);
            progress.parsed_track();
        }
        if progress.should_emit() {
            progress.emit_path(path);
        }
    }
    progress.emit_path(root);

    tracks.sort_by(compare_tracks);
    apply_folder_covers(&mut tracks, &mut cover_cache);
    let folders = classify_folders(&tracks);
    let albums = build_albums(&tracks, &folders);

    Ok(ScanResult {
        root_path: root_path.to_string(),
        tracks,
        folders,
        albums,
        elapsed_ms: started.elapsed().as_millis(),
        covers_cached: cover_cache.writes,
        skipped_files: issues.skipped_files,
        error_samples: issues.error_samples,
    })
}

pub(crate) fn extract_track_covers(
    request: TrackCoverRequest,
    cover_cache_dir: Option<&str>,
) -> Vec<TrackCoverResult> {
    let mut cover_cache = CoverCache::new(cover_cache_dir.map(PathBuf::from));
    request
        .paths
        .into_iter()
        .map(|path| {
            let cover_art_path = crate::flac::read_flac_picture(Path::new(&path))
                .ok()
                .flatten()
                .and_then(|image| cover_cache.cache_image(&image));
            TrackCoverResult {
                path,
                cover_art_path,
            }
        })
        .collect()
}

pub(crate) fn validate_scan_root(root: &Path, root_path: &str) -> io::Result<()> {
    if !root.exists() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("music root does not exist: {root_path}"),
        ));
    }
    fs::read_dir(root).map(|_| ()).map_err(|error| {
        io::Error::new(
            error.kind(),
            format!("music root cannot be opened: {root_path}: {error}"),
        )
    })
}
