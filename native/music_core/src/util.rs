use crate::models::{FileNameFallback, Track};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

pub(crate) fn path_to_utf8(path: &Path) -> Result<String, String> {
    path.to_str()
        .map(ToString::to_string)
        .ok_or_else(|| format!("{}: path is not valid UTF-8", path.display()))
}

pub(crate) fn is_audio_path(path: &Path) -> bool {
    path.extension()
        .map(|extension| extension.to_string_lossy().eq_ignore_ascii_case("flac"))
        .unwrap_or(false)
}

pub(crate) fn logical_folder_for(path: &Path) -> PathBuf {
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

pub(crate) fn is_disc_folder(name: &str) -> bool {
    let normalized = name.to_lowercase().replace(' ', "");
    for prefix in ["disc", "disk", "cd"] {
        if let Some(rest) = normalized.strip_prefix(prefix) {
            return !rest.is_empty()
                && rest
                    .chars()
                    .all(|char| char.is_ascii_digit() || "ivx".contains(char));
        }
    }
    false
}

pub(crate) fn first_tag(tags: &HashMap<String, String>, keys: &[&str]) -> Option<String> {
    first_tag_ref(tags, keys).map(ToString::to_string)
}

pub(crate) fn first_tag_ref<'a>(
    tags: &'a HashMap<String, String>,
    keys: &[&str],
) -> Option<&'a str> {
    keys.iter()
        .filter_map(|key| tags.get(*key))
        .map(|value| value.trim())
        .find(|value| !value.is_empty())
}

pub(crate) fn parse_number(value: Option<&str>) -> Option<i64> {
    let value = value?;
    let digits = value
        .chars()
        .skip_while(|char| !char.is_ascii_digit())
        .take_while(|char| char.is_ascii_digit())
        .collect::<String>();
    digits.parse().ok()
}

pub(crate) fn parse_year(value: Option<&str>) -> Option<i64> {
    let value = value?;
    for index in 0..=value.len().saturating_sub(4) {
        if !value.is_char_boundary(index) || !value.is_char_boundary(index + 4) {
            continue;
        }
        let candidate = &value[index..index + 4];
        if candidate.starts_with("19") || candidate.starts_with("20") {
            if let Ok(year) = candidate.parse::<i64>() {
                return Some(year);
            }
        }
    }
    None
}

pub(crate) fn parse_file_name(path: &Path) -> FileNameFallback {
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

pub(crate) fn basename(path: &str) -> String {
    Path::new(path)
        .file_name()
        .map(|value| value.to_string_lossy().to_string())
        .unwrap_or_else(|| path.to_string())
}

pub(crate) fn compare_tracks(a: &Track, b: &Track) -> std::cmp::Ordering {
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
