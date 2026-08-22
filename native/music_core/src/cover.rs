use crate::flac::read_flac_picture;
use crate::models::{CoverImage, Track};
use crate::util::path_to_utf8;
use sha1::{Digest, Sha1};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

pub(crate) const MAX_COVER_BYTES: usize = 5 * 1024 * 1024;

pub(crate) struct CoverCache {
    dir: Option<PathBuf>,
    folder_cache: HashMap<PathBuf, Option<String>>,
    pub writes: u64,
}

impl CoverCache {
    pub(crate) fn new(dir: Option<PathBuf>) -> Self {
        if let Some(dir) = dir.as_ref() {
            let _ = fs::create_dir_all(dir);
        }
        Self {
            dir,
            folder_cache: HashMap::new(),
            writes: 0,
        }
    }

    pub(crate) fn cover_for_folder(&mut self, folder: &Path, tracks: &[String]) -> Option<String> {
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

    pub(crate) fn cache_image(&mut self, image: &CoverImage) -> Option<String> {
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
            return path_to_utf8(&output_path).ok();
        }

        fs::write(&output_path, bytes).ok()?;
        self.writes += 1;
        path_to_utf8(&output_path).ok()
    }
}

pub(crate) fn apply_folder_covers(tracks: &mut [Track], cover_cache: &mut CoverCache) {
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

pub(crate) fn find_external_cover(folder: &Path) -> Option<PathBuf> {
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

pub(crate) fn first_cover_path(tracks: &[Track]) -> Option<String> {
    tracks.iter().find_map(|track| track.cover_art_path.clone())
}

pub(crate) fn first_cover_path_refs(tracks: &[&Track]) -> Option<String> {
    tracks.iter().find_map(|track| track.cover_art_path.clone())
}
