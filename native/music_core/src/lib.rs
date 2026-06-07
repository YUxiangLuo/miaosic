use serde::{Deserialize, Serialize};
use sha1::{Digest, Sha1};
use std::collections::{HashMap, HashSet};
use std::ffi::{CStr, CString};
use std::fs::{self, File};
use std::io::{self, Read};
use std::os::raw::c_char;
use std::path::{Path, PathBuf};
use std::time::Instant;
use walkdir::WalkDir;

const MAX_COVER_BYTES: usize = 5 * 1024 * 1024;
const PROGRESS_INTERVAL: u64 = 25;
const OTHER_TRACKS_FOLDER: &str = "OtherTracks";

type ProgressCallback =
    extern "C" fn(files_seen: u64, tracks_parsed: u64, current_path: *const c_char);

#[derive(Serialize)]
struct ScanResponse {
    ok: bool,
    error: Option<String>,
    result: Option<ScanResult>,
}

#[derive(Serialize)]
struct TrackCoverResponse {
    ok: bool,
    error: Option<String>,
    result: Option<Vec<TrackCoverResult>>,
}

#[derive(Serialize)]
struct TrackCoverResult {
    path: String,
    cover_art_path: Option<String>,
}

#[derive(Deserialize)]
struct TrackCoverRequest {
    paths: Vec<String>,
}

#[derive(Deserialize)]
struct IncrementalScanRequest {
    previous_tracks: Vec<Track>,
}

#[derive(Serialize)]
struct ScanResult {
    root_path: String,
    tracks: Vec<Track>,
    folders: Vec<FolderSummary>,
    albums: Vec<AlbumSummary>,
    elapsed_ms: u128,
    covers_cached: u64,
}

#[derive(Clone, Deserialize, Serialize)]
struct Track {
    path: String,
    folder_path: String,
    title: String,
    artist: String,
    album: String,
    album_artist: String,
    track_number: Option<i64>,
    disc_number: Option<i64>,
    year: Option<i64>,
    duration_ms: Option<i64>,
    size_bytes: i64,
    modified_ms: i64,
    cover_art_path: Option<String>,
}

#[derive(Clone, Serialize)]
struct FolderSummary {
    path: String,
    name: String,
    kind: String,
    confidence: f64,
    track_count: i64,
    album_count: i64,
    album_artist_count: i64,
    artist_count: i64,
    year_count: i64,
    cover_art_path: Option<String>,
}

#[derive(Serialize)]
struct AlbumSummary {
    folder_path: String,
    title: String,
    album_artist: String,
    year: Option<i64>,
    track_count: i64,
    cover_art_path: Option<String>,
}

struct FlacMetadata {
    tags: HashMap<String, String>,
    duration_ms: Option<i64>,
}

struct FileNameFallback {
    title: String,
    artist: String,
}

struct CoverImage {
    bytes: Vec<u8>,
    extension: &'static str,
}

struct CoverCache {
    dir: Option<PathBuf>,
    folder_cache: HashMap<PathBuf, Option<String>>,
    writes: u64,
}

struct ProgressReporter {
    callback: Option<ProgressCallback>,
    files_seen: u64,
    tracks_parsed: u64,
}

impl ProgressReporter {
    fn new(callback: Option<ProgressCallback>) -> Self {
        Self {
            callback,
            files_seen: 0,
            tracks_parsed: 0,
        }
    }

    fn seen_file(&mut self) {
        self.files_seen += 1;
    }

    fn parsed_track(&mut self) {
        self.tracks_parsed += 1;
    }

    fn should_emit(&self) -> bool {
        self.files_seen == 1 || self.files_seen % PROGRESS_INTERVAL == 0
    }

    fn emit_path(&self, current_path: &Path) {
        self.emit(current_path);
    }

    fn emit(&self, current_path: &Path) {
        let Some(callback) = self.callback else {
            return;
        };
        let path = current_path.to_string_lossy();
        let Ok(path) = CString::new(path.as_bytes()) else {
            return;
        };
        callback(self.files_seen, self.tracks_parsed, path.as_ptr());
    }
}

impl CoverCache {
    fn new(dir: Option<PathBuf>) -> Self {
        if let Some(dir) = dir.as_ref() {
            let _ = fs::create_dir_all(dir);
        }
        Self {
            dir,
            folder_cache: HashMap::new(),
            writes: 0,
        }
    }

    fn cover_for_folder(&mut self, folder: &Path, tracks: &[String]) -> Option<String> {
        if let Some(cached) = self.folder_cache.get(folder) {
            return cached.clone();
        }

        let cover = find_external_cover(folder)
            .and_then(|path| {
                let extension = cover_extension_for_path(&path)?;
                let bytes = fs::read(path).ok()?;
                Some(CoverImage { bytes, extension })
            })
            .and_then(|image| self.cache_image(&image))
            .or_else(|| {
                tracks.iter().find_map(|track| {
                    read_flac_picture(Path::new(track))
                        .ok()
                        .flatten()
                        .and_then(|image| self.cache_image(&image))
                })
            });
        self.folder_cache
            .insert(folder.to_path_buf(), cover.clone());
        cover
    }

    fn cache_image(&mut self, image: &CoverImage) -> Option<String> {
        let bytes = image.bytes.as_slice();
        if bytes.len() > MAX_COVER_BYTES {
            return None;
        }
        let dir = self.dir.as_ref()?;
        let mut hasher = Sha1::new();
        hasher.update(bytes);
        let file_name = format!("{}.{}", hex::encode(hasher.finalize()), image.extension);
        let output_path = dir.join(file_name);
        if output_path.exists() {
            return Some(output_path.to_string_lossy().to_string());
        }

        fs::write(&output_path, bytes).ok()?;
        self.writes += 1;
        Some(output_path.to_string_lossy().to_string())
    }
}

#[no_mangle]
pub extern "C" fn miaosic_scan_library(root_path: *const c_char) -> *mut c_char {
    miaosic_scan_library_with_covers(root_path, std::ptr::null())
}

#[no_mangle]
pub extern "C" fn miaosic_scan_library_with_covers(
    root_path: *const c_char,
    cover_cache_dir: *const c_char,
) -> *mut c_char {
    scan_library_response(root_path, cover_cache_dir, None)
}

#[no_mangle]
pub extern "C" fn miaosic_scan_library_with_covers_and_progress(
    root_path: *const c_char,
    cover_cache_dir: *const c_char,
    progress_callback: Option<ProgressCallback>,
) -> *mut c_char {
    scan_library_response(root_path, cover_cache_dir, progress_callback)
}

#[no_mangle]
pub extern "C" fn miaosic_scan_library_incremental_with_covers_and_progress(
    root_path: *const c_char,
    previous_tracks_json: *const c_char,
    cover_cache_dir: *const c_char,
    progress_callback: Option<ProgressCallback>,
) -> *mut c_char {
    scan_library_incremental_response(
        root_path,
        previous_tracks_json,
        cover_cache_dir,
        progress_callback,
    )
}

#[no_mangle]
pub extern "C" fn miaosic_extract_track_covers(
    paths_json: *const c_char,
    cover_cache_dir: *const c_char,
) -> *mut c_char {
    let response = match read_c_string(paths_json) {
        Ok(raw) => match serde_json::from_str::<TrackCoverRequest>(&raw)
            .map_err(|error| error.to_string())
            .and_then(|request| {
                read_optional_c_string(cover_cache_dir).map(|cache_dir| (request, cache_dir))
            })
            .map(|(request, cache_dir)| extract_track_covers(request, cache_dir.as_deref()))
        {
            Ok(result) => TrackCoverResponse {
                ok: true,
                error: None,
                result: Some(result),
            },
            Err(error) => TrackCoverResponse {
                ok: false,
                error: Some(error),
                result: None,
            },
        },
        Err(error) => TrackCoverResponse {
            ok: false,
            error: Some(error),
            result: None,
        },
    };

    let json = serde_json::to_string(&response).unwrap_or_else(|error| {
        format!(
            r#"{{"ok":false,"error":"failed to serialize track cover response: {error}","result":null}}"#
        )
    });
    CString::new(json).unwrap().into_raw()
}

fn scan_library_response(
    root_path: *const c_char,
    cover_cache_dir: *const c_char,
    progress_callback: Option<ProgressCallback>,
) -> *mut c_char {
    let response = match read_c_string(root_path) {
        Ok(root) => match read_optional_c_string(cover_cache_dir).and_then(|cache_dir| {
            scan_library(&root, cache_dir.as_deref(), progress_callback).map_err(|e| e.to_string())
        }) {
            Ok(result) => ScanResponse {
                ok: true,
                error: None,
                result: Some(result),
            },
            Err(error) => ScanResponse {
                ok: false,
                error: Some(error),
                result: None,
            },
        },
        Err(error) => ScanResponse {
            ok: false,
            error: Some(error),
            result: None,
        },
    };

    let json = serde_json::to_string(&response).unwrap_or_else(|error| {
        format!(
            r#"{{"ok":false,"error":"failed to serialize scan response: {error}","result":null}}"#
        )
    });
    CString::new(json).unwrap().into_raw()
}

fn scan_library_incremental_response(
    root_path: *const c_char,
    previous_tracks_json: *const c_char,
    cover_cache_dir: *const c_char,
    progress_callback: Option<ProgressCallback>,
) -> *mut c_char {
    let response = match read_c_string(root_path) {
        Ok(root) => {
            let result = read_c_string(previous_tracks_json)
                .and_then(|raw| {
                    serde_json::from_str::<IncrementalScanRequest>(&raw)
                        .map_err(|error| error.to_string())
                })
                .and_then(|request| {
                    read_optional_c_string(cover_cache_dir)
                        .map(|cache_dir| (request.previous_tracks, cache_dir))
                })
                .and_then(|(previous_tracks, cache_dir)| {
                    scan_library_incremental(
                        &root,
                        previous_tracks,
                        cache_dir.as_deref(),
                        progress_callback,
                    )
                    .map_err(|error| error.to_string())
                });

            match result {
                Ok(result) => ScanResponse {
                    ok: true,
                    error: None,
                    result: Some(result),
                },
                Err(error) => ScanResponse {
                    ok: false,
                    error: Some(error),
                    result: None,
                },
            }
        }
        Err(error) => ScanResponse {
            ok: false,
            error: Some(error),
            result: None,
        },
    };

    let json = serde_json::to_string(&response).unwrap_or_else(|error| {
        format!(
            r#"{{"ok":false,"error":"failed to serialize incremental scan response: {error}","result":null}}"#
        )
    });
    CString::new(json).unwrap().into_raw()
}

#[no_mangle]
pub extern "C" fn miaosic_free_string(value: *mut c_char) {
    if value.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(value));
    }
}

fn read_c_string(value: *const c_char) -> Result<String, String> {
    if value.is_null() {
        return Err("root path pointer is null".to_string());
    }
    let raw = unsafe { CStr::from_ptr(value) };
    raw.to_str()
        .map(|value| value.to_string())
        .map_err(|error| format!("root path is not valid UTF-8: {error}"))
}

fn read_optional_c_string(value: *const c_char) -> Result<Option<String>, String> {
    if value.is_null() {
        return Ok(None);
    }
    read_c_string(value).map(Some)
}

fn scan_library(
    root_path: &str,
    cover_cache_dir: Option<&str>,
    progress_callback: Option<ProgressCallback>,
) -> io::Result<ScanResult> {
    let started = Instant::now();
    let root = Path::new(root_path);
    if !root.exists() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("music root does not exist: {root_path}"),
        ));
    }
    move_root_audio_files_to_other_tracks(root)?;

    let mut tracks = Vec::new();
    let mut cover_cache = CoverCache::new(cover_cache_dir.map(PathBuf::from));
    let mut progress = ProgressReporter::new(progress_callback);
    for entry in WalkDir::new(root).follow_links(false) {
        let entry = match entry {
            Ok(entry) => entry,
            Err(_) => continue,
        };
        if !entry.file_type().is_file() || !is_audio_path(entry.path()) {
            continue;
        }
        progress.seen_file();
        if let Ok(track) = parse_track(entry.path()) {
            tracks.push(track);
            progress.parsed_track();
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
    })
}

fn scan_library_incremental(
    root_path: &str,
    previous_tracks: Vec<Track>,
    cover_cache_dir: Option<&str>,
    progress_callback: Option<ProgressCallback>,
) -> io::Result<ScanResult> {
    let started = Instant::now();
    let root = Path::new(root_path);
    if !root.exists() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("music root does not exist: {root_path}"),
        ));
    }
    move_root_audio_files_to_other_tracks(root)?;

    let previous_by_path = previous_tracks
        .into_iter()
        .map(|track| (track.path.clone(), track))
        .collect::<HashMap<_, _>>();
    let mut tracks = Vec::new();
    let mut cover_cache = CoverCache::new(cover_cache_dir.map(PathBuf::from));
    let mut progress = ProgressReporter::new(progress_callback);

    for entry in WalkDir::new(root).follow_links(false) {
        let entry = match entry {
            Ok(entry) => entry,
            Err(_) => continue,
        };
        if !entry.file_type().is_file() || !is_audio_path(entry.path()) {
            continue;
        }

        progress.seen_file();
        let path = entry.path();
        let path_string = path.to_string_lossy().to_string();
        let track = match track_file_state(path) {
            Ok((size_bytes, modified_ms)) => previous_by_path
                .get(&path_string)
                .filter(|track| track.size_bytes == size_bytes && track.modified_ms == modified_ms)
                .cloned()
                .or_else(|| parse_track(path).ok()),
            Err(_) => None,
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
    })
}

fn extract_track_covers(
    request: TrackCoverRequest,
    cover_cache_dir: Option<&str>,
) -> Vec<TrackCoverResult> {
    let mut cover_cache = CoverCache::new(cover_cache_dir.map(PathBuf::from));
    request
        .paths
        .into_iter()
        .map(|path| {
            let cover_art_path = read_flac_picture(Path::new(&path))
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

fn move_root_audio_files_to_other_tracks(root: &Path) -> io::Result<()> {
    let mut root_audio_files = Vec::new();
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        let path = entry.path();
        if entry.file_type()?.is_file() && is_audio_path(&path) {
            root_audio_files.push(path);
        }
    }

    if root_audio_files.is_empty() {
        return Ok(());
    }

    let other_tracks = root.join(OTHER_TRACKS_FOLDER);
    fs::create_dir_all(&other_tracks)?;
    for source in root_audio_files {
        let Some(file_name) = source.file_name() else {
            continue;
        };
        let target = available_move_target(&other_tracks.join(file_name));
        fs::rename(source, target)?;
    }
    Ok(())
}

fn available_move_target(target: &Path) -> PathBuf {
    if !target.exists() {
        return target.to_path_buf();
    }

    let parent = target.parent().unwrap_or_else(|| Path::new(""));
    let stem = target
        .file_stem()
        .map(|value| value.to_string_lossy())
        .unwrap_or_default();
    let extension = target.extension().map(|value| value.to_string_lossy());
    for index in 1.. {
        let file_name = match extension.as_ref() {
            Some(extension) if !extension.is_empty() => {
                format!("{stem} ({index}).{extension}")
            }
            _ => format!("{stem} ({index})"),
        };
        let candidate = parent.join(file_name);
        if !candidate.exists() {
            return candidate;
        }
    }
    unreachable!("unbounded unique file name search should always return")
}

fn parse_track(path: &Path) -> io::Result<Track> {
    let (size_bytes, modified_ms) = track_file_state(path)?;
    let flac = read_flac_metadata(path).unwrap_or_else(|_| FlacMetadata {
        tags: HashMap::new(),
        duration_ms: None,
    });
    let fallback = parse_file_name(path);

    let title = first_tag(&flac.tags, &["TITLE"]).unwrap_or(fallback.title);
    let artist = first_tag(&flac.tags, &["ARTIST"]).unwrap_or(fallback.artist);
    let album = first_tag(&flac.tags, &["ALBUM"]).unwrap_or_default();
    let album_artist =
        first_tag(&flac.tags, &["ALBUMARTIST", "ALBUM_ARTIST"]).unwrap_or_else(|| artist.clone());

    Ok(Track {
        path: path.to_string_lossy().to_string(),
        folder_path: logical_folder_for(path).to_string_lossy().to_string(),
        title,
        artist,
        album,
        album_artist,
        track_number: parse_number(first_tag_ref(&flac.tags, &["TRACKNUMBER", "TRACK"])),
        disc_number: parse_number(first_tag_ref(&flac.tags, &["DISCNUMBER", "DISC"])),
        year: parse_year(first_tag_ref(&flac.tags, &["DATE", "YEAR"])),
        duration_ms: flac.duration_ms,
        size_bytes,
        modified_ms,
        cover_art_path: None,
    })
}

fn track_file_state(path: &Path) -> io::Result<(i64, i64)> {
    let metadata = fs::metadata(path)?;
    let modified_ms = metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or(0);
    Ok((metadata.len() as i64, modified_ms))
}

fn read_flac_metadata(path: &Path) -> io::Result<FlacMetadata> {
    let mut file = File::open(path)?;
    let mut marker = [0_u8; 4];
    file.read_exact(&mut marker)?;
    if &marker != b"fLaC" {
        return Ok(FlacMetadata {
            tags: HashMap::new(),
            duration_ms: None,
        });
    }

    let mut tags = HashMap::new();
    let mut duration_ms = None;
    loop {
        let mut header = [0_u8; 4];
        if file.read_exact(&mut header).is_err() {
            break;
        }
        let is_last = (header[0] & 0x80) != 0;
        let block_type = header[0] & 0x7f;
        let length =
            ((header[1] as usize) << 16) | ((header[2] as usize) << 8) | header[3] as usize;
        let mut block = vec![0_u8; length];
        file.read_exact(&mut block)?;

        match block_type {
            0 => duration_ms = read_streaminfo_duration(&block),
            4 => tags.extend(read_vorbis_comments(&block)),
            _ => {}
        }

        if !tags.is_empty() && duration_ms.is_some() {
            break;
        }
        if is_last {
            break;
        }
    }

    Ok(FlacMetadata { tags, duration_ms })
}

fn read_flac_picture(path: &Path) -> io::Result<Option<CoverImage>> {
    let mut file = File::open(path)?;
    let mut marker = [0_u8; 4];
    file.read_exact(&mut marker)?;
    if &marker != b"fLaC" {
        return Ok(None);
    }

    loop {
        let mut header = [0_u8; 4];
        if file.read_exact(&mut header).is_err() {
            break;
        }
        let is_last = (header[0] & 0x80) != 0;
        let block_type = header[0] & 0x7f;
        let length =
            ((header[1] as usize) << 16) | ((header[2] as usize) << 8) | header[3] as usize;
        let mut block = vec![0_u8; length];
        file.read_exact(&mut block)?;
        if block_type == 6 {
            return Ok(read_picture_data(&block));
        }
        if is_last {
            break;
        }
    }
    Ok(None)
}

fn read_streaminfo_duration(block: &[u8]) -> Option<i64> {
    if block.len() < 34 {
        return None;
    }
    let mut packed = 0_u64;
    for byte in &block[10..18] {
        packed = (packed << 8) | *byte as u64;
    }
    let sample_rate = (packed >> 44) & 0xfffff;
    let total_samples = packed & 0xfffffffff;
    if sample_rate == 0 || total_samples == 0 {
        return None;
    }
    Some(((total_samples * 1000) / sample_rate) as i64)
}

fn read_vorbis_comments(block: &[u8]) -> HashMap<String, String> {
    let mut comments = HashMap::new();
    let mut offset = 0_usize;

    let Some(vendor_length) = read_u32_le(block, &mut offset) else {
        return comments;
    };
    offset += vendor_length as usize;
    if offset > block.len() {
        return comments;
    }

    let Some(comment_count) = read_u32_le(block, &mut offset) else {
        return comments;
    };

    for _ in 0..comment_count {
        let Some(length) = read_u32_le(block, &mut offset) else {
            break;
        };
        let end = offset + length as usize;
        if end > block.len() {
            break;
        }
        let raw = String::from_utf8_lossy(&block[offset..end]);
        offset = end;

        let Some((key, value)) = raw.split_once('=') else {
            continue;
        };
        let key = key.trim().to_uppercase();
        let value = value.trim();
        if !value.is_empty() {
            comments.entry(key).or_insert_with(|| value.to_string());
        }
    }

    comments
}

fn read_u32_le(block: &[u8], offset: &mut usize) -> Option<u32> {
    let end = *offset + 4;
    if end > block.len() {
        return None;
    }
    let value = u32::from_le_bytes(block[*offset..end].try_into().ok()?);
    *offset = end;
    Some(value)
}

fn read_u32_be(block: &[u8], offset: &mut usize) -> Option<u32> {
    let end = *offset + 4;
    if end > block.len() {
        return None;
    }
    let value = u32::from_be_bytes(block[*offset..end].try_into().ok()?);
    *offset = end;
    Some(value)
}

fn read_picture_data(block: &[u8]) -> Option<CoverImage> {
    let mut offset = 0_usize;
    let _picture_type = read_u32_be(block, &mut offset)?;
    let mime_len = read_u32_be(block, &mut offset)? as usize;
    let mime_end = offset + mime_len;
    if mime_end > block.len() {
        return None;
    }
    let mime = String::from_utf8_lossy(&block[offset..mime_end]).to_lowercase();
    offset = mime_end;
    let extension = if mime.contains("png") {
        "png"
    } else if mime.contains("jpeg") || mime.contains("jpg") {
        "jpg"
    } else {
        return None;
    };
    let description_len = read_u32_be(block, &mut offset)? as usize;
    offset = offset.checked_add(description_len)?;
    if offset + 16 > block.len() {
        return None;
    }
    offset += 16;
    let data_len = read_u32_be(block, &mut offset)? as usize;
    if data_len > MAX_COVER_BYTES {
        return None;
    }
    let data_end = offset + data_len;
    if data_end > block.len() {
        return None;
    }
    Some(CoverImage {
        bytes: block[offset..data_end].to_vec(),
        extension,
    })
}

fn apply_folder_covers(tracks: &mut [Track], cover_cache: &mut CoverCache) {
    let mut tracks_by_folder: HashMap<String, Vec<String>> = HashMap::new();
    for track in tracks.iter() {
        tracks_by_folder
            .entry(track.folder_path.clone())
            .or_default()
            .push(track.path.clone());
    }

    let mut covers = HashMap::new();
    for (folder, folder_tracks) in tracks_by_folder {
        let cover = cover_cache.cover_for_folder(Path::new(&folder), &folder_tracks);
        covers.insert(folder, cover);
    }

    for track in tracks {
        track.cover_art_path = covers
            .get(&track.folder_path)
            .and_then(|cover| cover.as_ref().cloned());
    }
}

fn classify_folders(tracks: &[Track]) -> Vec<FolderSummary> {
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

fn build_albums(tracks: &[Track], folders: &[FolderSummary]) -> Vec<AlbumSummary> {
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

fn detect_folder_kind(
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
    if folder_name == OTHER_TRACKS_FOLDER.to_lowercase() {
        return ("playlist".to_string(), 0.99);
    }

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
    if is_playlist_name(&folder_name) {
        playlist_score += 3;
    }
    if (track_numbers.len() as f64) < track_count as f64 * 0.55 {
        playlist_score += 1;
    }

    if playlist_score >= album_score + 2 && playlist_score >= 5 {
        return (
            "playlist".to_string(),
            confidence(playlist_score, album_score),
        );
    }
    if album_score >= playlist_score + 2 && album_score >= 6 {
        return ("album".to_string(), confidence(album_score, playlist_score));
    }
    ("mixed".to_string(), 0.5)
}

fn is_audio_path(path: &Path) -> bool {
    path.extension()
        .map(|extension| extension.to_string_lossy().eq_ignore_ascii_case("flac"))
        .unwrap_or(false)
}

fn logical_folder_for(path: &Path) -> PathBuf {
    let parent = path.parent().unwrap_or_else(|| Path::new(""));
    let parent_name = parent
        .file_name()
        .map(|value| value.to_string_lossy().to_lowercase())
        .unwrap_or_default();
    if is_disc_folder(&parent_name) {
        return parent.parent().unwrap_or(parent).to_path_buf();
    }
    parent.to_path_buf()
}

fn find_external_cover(folder: &Path) -> Option<PathBuf> {
    const NAMES: &[&str] = &[
        "cover.jpg",
        "cover.jpeg",
        "cover.png",
        "folder.jpg",
        "folder.jpeg",
        "folder.png",
        "front.jpg",
        "front.jpeg",
        "front.png",
    ];

    let entries = fs::read_dir(folder).ok()?;
    let mut by_name = HashMap::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let Some(file_name) = path.file_name() else {
            continue;
        };
        by_name
            .entry(file_name.to_string_lossy().to_lowercase())
            .or_insert(path);
    }

    for name in NAMES {
        if let Some(path) = by_name.remove(*name) {
            return Some(path);
        }
    }
    None
}

fn cover_extension_for_path(path: &Path) -> Option<&'static str> {
    let extension = path.extension()?.to_string_lossy().to_lowercase();
    match extension.as_str() {
        "jpg" | "jpeg" => Some("jpg"),
        "png" => Some("png"),
        _ => None,
    }
}

fn is_disc_folder(name: &str) -> bool {
    let normalized = name.replace(' ', "");
    if let Some(rest) = normalized.strip_prefix("disc") {
        return rest
            .chars()
            .all(|char| char.is_ascii_digit() || "ivx".contains(char));
    }
    if let Some(rest) = normalized.strip_prefix("disk") {
        return rest
            .chars()
            .all(|char| char.is_ascii_digit() || "ivx".contains(char));
    }
    if let Some(rest) = normalized.strip_prefix("cd") {
        return rest
            .chars()
            .all(|char| char.is_ascii_digit() || "ivx".contains(char));
    }
    false
}

fn first_tag(tags: &HashMap<String, String>, keys: &[&str]) -> Option<String> {
    first_tag_ref(tags, keys).map(ToString::to_string)
}

fn first_tag_ref<'a>(tags: &'a HashMap<String, String>, keys: &[&str]) -> Option<&'a str> {
    keys.iter()
        .filter_map(|key| tags.get(*key))
        .map(|value| value.trim())
        .find(|value| !value.is_empty())
}

fn parse_number(value: Option<&str>) -> Option<i64> {
    let value = value?;
    let digits = value
        .chars()
        .skip_while(|char| !char.is_ascii_digit())
        .take_while(|char| char.is_ascii_digit())
        .collect::<String>();
    digits.parse().ok()
}

fn parse_year(value: Option<&str>) -> Option<i64> {
    let value = value?;
    for index in 0..value.len().saturating_sub(3) {
        let candidate = &value[index..index + 4];
        if candidate.starts_with("19") || candidate.starts_with("20") {
            if let Ok(year) = candidate.parse::<i64>() {
                return Some(year);
            }
        }
    }
    None
}

fn parse_file_name(path: &Path) -> FileNameFallback {
    let stem = path
        .file_stem()
        .map(|value| value.to_string_lossy().to_string())
        .unwrap_or_else(|| "Unknown Track".to_string());
    let without_number = remove_number_prefix(&stem);
    if let Some((artist, title)) = without_number.split_once(" - ") {
        return FileNameFallback {
            artist: artist.trim().to_string(),
            title: title.trim().to_string(),
        };
    }
    FileNameFallback {
        title: without_number.trim().to_string(),
        artist: "Unknown Artist".to_string(),
    }
}

fn remove_number_prefix(value: &str) -> String {
    let trimmed = value.trim_start();
    let digit_count = trimmed
        .chars()
        .take_while(|char| char.is_ascii_digit())
        .count();
    if digit_count > 0 && trimmed.chars().nth(digit_count) == Some('.') {
        return trimmed[digit_count + 1..].trim_start().to_string();
    }
    trimmed.to_string()
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

fn basename(path: &str) -> String {
    Path::new(path)
        .file_name()
        .map(|value| value.to_string_lossy().to_string())
        .unwrap_or_else(|| path.to_string())
}

fn compare_tracks(a: &Track, b: &Track) -> std::cmp::Ordering {
    a.folder_path
        .to_lowercase()
        .cmp(&b.folder_path.to_lowercase())
        .then_with(|| a.disc_number.unwrap_or(0).cmp(&b.disc_number.unwrap_or(0)))
        .then_with(|| {
            a.track_number
                .unwrap_or(9999)
                .cmp(&b.track_number.unwrap_or(9999))
        })
        .then_with(|| a.path.to_lowercase().cmp(&b.path.to_lowercase()))
}

fn first_cover_path(tracks: &[Track]) -> Option<String> {
    tracks.iter().find_map(|track| track.cover_art_path.clone())
}

fn first_cover_path_refs(tracks: &[&Track]) -> Option<String> {
    tracks.iter().find_map(|track| track.cover_art_path.clone())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn extracts_flac_picture_payload() {
        let image = b"fake-jpeg-bytes";
        let block = picture_block(b"image/jpeg", image);

        let picture = read_picture_data(&block).expect("picture payload");
        assert_eq!(picture.extension, "jpg");
        assert_eq!(picture.bytes.as_slice(), image.as_slice());
    }

    #[test]
    fn rejects_invalid_streaminfo_duration_blocks() {
        assert_eq!(read_streaminfo_duration(&[0; 12]), None);
        assert_eq!(read_streaminfo_duration(&[0; 34]), None);
    }

    #[test]
    fn parses_vorbis_comments_defensively() {
        let block = vorbis_comment_block(&[
            b"TITLE=First".as_slice(),
            b"TITLE=Second".as_slice(),
            b"ARTIST=\xffName".as_slice(),
        ]);

        let comments = read_vorbis_comments(&block);

        assert_eq!(comments.get("TITLE").map(String::as_str), Some("First"));
        assert!(comments
            .get("ARTIST")
            .is_some_and(|value| value.contains('\u{fffd}')));
    }

    #[test]
    fn ignores_truncated_vorbis_comment_blocks() {
        let mut block = Vec::new();
        block.extend_from_slice(&32_u32.to_le_bytes());
        block.extend_from_slice(b"short");

        assert!(read_vorbis_comments(&block).is_empty());
    }

    #[test]
    fn rejects_unsupported_or_oversized_picture_payloads() {
        assert!(read_picture_data(&picture_block(b"image/gif", b"gif")).is_none());
        assert!(read_picture_data(&picture_block_with_len(
            b"image/jpeg",
            (MAX_COVER_BYTES + 1) as u32,
            &[],
        ))
        .is_none());
    }

    #[test]
    fn batch_track_cover_extraction_preserves_missing_results() {
        let results = extract_track_covers(
            TrackCoverRequest {
                paths: vec!["/missing/a.flac".to_string(), "/missing/b.flac".to_string()],
            },
            None,
        );

        assert_eq!(results.len(), 2);
        assert_eq!(results[0].path, "/missing/a.flac");
        assert!(results[0].cover_art_path.is_none());
        assert_eq!(results[1].path, "/missing/b.flac");
        assert!(results[1].cover_art_path.is_none());
    }

    #[test]
    fn scan_moves_root_tracks_to_other_tracks_playlist() {
        let root = temp_root("root_tracks");
        let loose_track = root.join("Loose.flac");
        fs::write(&loose_track, b"not a real flac").expect("write loose track");

        let result = scan_library(root.to_str().expect("root utf8"), None, None).expect("scan");
        let moved_track = root.join(OTHER_TRACKS_FOLDER).join("Loose.flac");

        assert!(!loose_track.exists());
        assert!(moved_track.exists());
        assert!(result
            .tracks
            .iter()
            .any(|track| track.path == moved_track.to_string_lossy()));
        let folder = result
            .folders
            .iter()
            .find(|folder| folder.name == OTHER_TRACKS_FOLDER)
            .expect("OtherTracks folder");
        assert_eq!(folder.kind, "playlist");
        assert!(result.albums.is_empty());

        fs::remove_dir_all(root).expect("cleanup temp root");
    }

    #[test]
    fn moving_root_tracks_does_not_overwrite_existing_other_tracks_files() {
        let root = temp_root("root_track_conflict");
        let other_tracks = root.join(OTHER_TRACKS_FOLDER);
        fs::create_dir_all(&other_tracks).expect("create OtherTracks");
        let existing_track = other_tracks.join("Loose.flac");
        fs::write(&existing_track, b"existing").expect("write existing track");
        fs::write(root.join("Loose.flac"), b"new").expect("write loose track");

        move_root_audio_files_to_other_tracks(&root).expect("move root tracks");

        assert_eq!(
            fs::read(&existing_track).expect("read existing track"),
            b"existing"
        );
        assert_eq!(
            fs::read(other_tracks.join("Loose (1).flac")).expect("read moved track"),
            b"new"
        );

        fs::remove_dir_all(root).expect("cleanup temp root");
    }

    #[test]
    fn external_cover_lookup_is_case_insensitive() {
        let root = temp_root("case_cover");
        let cover_path = root.join("Cover.JPG");
        fs::write(&cover_path, b"jpg").expect("write cover");

        assert_eq!(find_external_cover(&root), Some(cover_path));

        fs::remove_dir_all(root).expect("cleanup temp root");
    }

    #[test]
    fn folder_cover_uses_later_embedded_picture_when_first_track_has_none() {
        let root = temp_root("embedded_folder_cover");
        let cache = temp_root("embedded_folder_cover_cache");
        let album = root.join("Album");
        fs::create_dir_all(&album).expect("create album");
        let first = album.join("01. No Picture.flac");
        let second = album.join("02. Has Picture.flac");
        fs::write(&first, minimal_flac(None)).expect("write first track");
        fs::write(&second, minimal_flac(Some(b"cover-bytes"))).expect("write second track");

        let result = scan_library(
            root.to_str().expect("root utf8"),
            Some(cache.to_str().expect("cache utf8")),
            None,
        )
        .expect("scan");

        let folder = result
            .folders
            .iter()
            .find(|folder| folder.name == "Album")
            .expect("album folder");
        assert!(folder.cover_art_path.is_some());
        assert!(result
            .tracks
            .iter()
            .all(|track| track.cover_art_path == folder.cover_art_path));

        fs::remove_dir_all(root).expect("cleanup temp root");
        fs::remove_dir_all(cache).expect("cleanup cache root");
    }

    fn vorbis_comment_block(comments: &[&[u8]]) -> Vec<u8> {
        let mut block = Vec::new();
        block.extend_from_slice(&7_u32.to_le_bytes());
        block.extend_from_slice(b"miaosic");
        block.extend_from_slice(&(comments.len() as u32).to_le_bytes());
        for comment in comments {
            block.extend_from_slice(&(comment.len() as u32).to_le_bytes());
            block.extend_from_slice(comment);
        }
        block
    }

    fn picture_block(mime: &[u8], data: &[u8]) -> Vec<u8> {
        picture_block_with_len(mime, data.len() as u32, data)
    }

    fn minimal_flac(picture: Option<&[u8]>) -> Vec<u8> {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"fLaC");
        bytes.extend_from_slice(&metadata_block_header(0, 34, picture.is_none()));
        bytes.extend_from_slice(&[0; 34]);
        if let Some(picture) = picture {
            let block = picture_block(b"image/jpeg", picture);
            bytes.extend_from_slice(&metadata_block_header(6, block.len(), true));
            bytes.extend_from_slice(&block);
        }
        bytes
    }

    fn metadata_block_header(block_type: u8, length: usize, is_last: bool) -> [u8; 4] {
        [
            if is_last {
                0x80 | block_type
            } else {
                block_type
            },
            ((length >> 16) & 0xff) as u8,
            ((length >> 8) & 0xff) as u8,
            (length & 0xff) as u8,
        ]
    }

    fn picture_block_with_len(mime: &[u8], data_len: u32, data: &[u8]) -> Vec<u8> {
        let mut block = Vec::new();
        block.extend_from_slice(&3_u32.to_be_bytes());
        block.extend_from_slice(&(mime.len() as u32).to_be_bytes());
        block.extend_from_slice(mime);
        block.extend_from_slice(&0_u32.to_be_bytes());
        block.extend_from_slice(&0_u32.to_be_bytes());
        block.extend_from_slice(&0_u32.to_be_bytes());
        block.extend_from_slice(&0_u32.to_be_bytes());
        block.extend_from_slice(&0_u32.to_be_bytes());
        block.extend_from_slice(&data_len.to_be_bytes());
        block.extend_from_slice(data);
        block
    }

    fn temp_root(label: &str) -> PathBuf {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time")
            .as_nanos();
        let root = std::env::temp_dir().join(format!("miaosic_{label}_{unique}"));
        fs::create_dir_all(&root).expect("create temp root");
        root
    }
}
