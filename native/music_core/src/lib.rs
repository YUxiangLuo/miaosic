mod classify;
mod cover;
mod ffi;
mod flac;
mod models;
mod scan;
mod util;

// Re-export the public C ABI and the items referenced by tests below.
pub use ffi::{
    miaosic_extract_track_covers, miaosic_free_string, miaosic_scan_library,
    miaosic_scan_library_incremental_with_covers_and_progress, miaosic_scan_library_with_covers,
    miaosic_scan_library_with_covers_and_progress,
};

#[cfg(test)]
mod tests {
    use crate::classify::detect_folder_kind;
    use crate::cover::find_external_cover;
    use crate::cover::MAX_COVER_BYTES;
    use crate::ffi::{catch_native, read_c_string, respond_json};
    use crate::flac::{read_picture_data, read_streaminfo_duration, read_vorbis_comments};
    use crate::models::{IncrementalScanRequest, ScanIssues, Track, TrackCoverRequest};
    use crate::scan::{extract_track_covers, scan_library, scan_library_incremental};
    use crate::util::is_disc_folder;
    use std::ffi::{CStr, CString};
    use std::fs;
    use std::path::PathBuf;
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
    fn detects_named_multi_source_essentials_folder_as_playlist() {
        let path = "/music/Maroon 5 Essentials";
        let tracks = (0..8)
            .map(|index| {
                test_track(
                    path,
                    &format!("Track {index}"),
                    &format!("Artist {}", index % 4),
                    &format!("Album {}", index % 4),
                    &format!("Album Artist {}", index % 4),
                    Some((index + 1) as i64),
                    Some(2010 + index as i64),
                )
            })
            .collect::<Vec<_>>();

        assert_eq!(detect_folder_kind(path, &tracks, 4, 4, 4, 8).0, "playlist");
    }

    #[test]
    fn keeps_named_single_source_essentials_folder_as_album() {
        let path = "/music/The Essentials";
        let tracks = (0..10)
            .map(|index| {
                test_track(
                    path,
                    &format!("Track {index}"),
                    "Artist",
                    "The Essentials",
                    "Artist",
                    Some((index + 1) as i64),
                    Some(2010),
                )
            })
            .collect::<Vec<_>>();

        assert_eq!(detect_folder_kind(path, &tracks, 1, 1, 1, 1).0, "album");
    }

    #[test]
    fn treats_non_album_folders_as_playlists() {
        let path = "/music/Unsorted";
        let tracks = (0..4)
            .map(|index| {
                test_track(
                    path,
                    &format!("Track {index}"),
                    &format!("Artist {index}"),
                    &format!("Album {index}"),
                    &format!("Album Artist {index}"),
                    None,
                    Some(2010 + index as i64),
                )
            })
            .collect::<Vec<_>>();

        assert_eq!(detect_folder_kind(path, &tracks, 4, 4, 4, 4).0, "playlist");
    }

    #[test]
    fn scan_keeps_root_tracks_in_place() {
        let root = temp_root("root_tracks");
        let loose_track = root.join("Loose.flac");
        fs::write(&loose_track, b"not a real flac").expect("write loose track");

        let result = scan_library(root.to_str().expect("root utf8"), None, None).expect("scan");

        assert!(loose_track.exists());
        assert!(result
            .tracks
            .iter()
            .any(|track| track.path == loose_track.to_string_lossy()));

        fs::remove_dir_all(root).expect("cleanup temp root");
    }

    #[test]
    fn scan_rejects_existing_non_directory_root() {
        let root = temp_root("file_root");
        let file_root = root.join("not_a_directory");
        fs::write(&file_root, b"not a directory").expect("write file root");
        let file_root = file_root.to_str().expect("file root utf8");

        let full_error = match scan_library(file_root, None, None) {
            Ok(_) => panic!("full scan should reject non-directory root"),
            Err(error) => error,
        };
        assert!(full_error
            .to_string()
            .contains("music root cannot be opened"));

        let incremental_error = match scan_library_incremental(file_root, Vec::new(), None, None) {
            Ok(_) => panic!("incremental scan should reject non-directory root"),
            Err(error) => error,
        };
        assert!(incremental_error
            .to_string()
            .contains("music root cannot be opened"));

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
    fn respond_json_strips_interior_nuls() {
        let pointer =
            respond_json("{\"ok\":false,\"error\":\"bad\0value\",\"result\":null}".to_string());
        let raw = unsafe { CStr::from_ptr(pointer) };
        let text = raw.to_str().expect("utf8");
        assert!(!text.as_bytes().contains(&0));
        assert!(text.contains("badvalue"));
        unsafe {
            drop(CString::from_raw(pointer));
        }
    }

    #[test]
    fn catch_native_turns_panics_into_json_errors() {
        let pointer = catch_native(|| panic!("boom"));
        let raw = unsafe { CStr::from_ptr(pointer) };
        let text = raw.to_str().expect("utf8");
        assert!(text.contains("native panic"));
        unsafe {
            drop(CString::from_raw(pointer));
        }
    }

    #[test]
    fn walk_notes_do_not_count_as_skipped_files() {
        let mut issues = ScanIssues::default();
        issues.note("dir: permission denied");
        issues.skip_file("/music/a.flac: not found");
        assert_eq!(issues.skipped_files, 1);
        assert_eq!(issues.error_samples.len(), 2);
    }

    #[test]
    fn disc_folder_requires_a_number_or_roman_suffix() {
        assert!(is_disc_folder("disc 1"));
        assert!(is_disc_folder("CD2"));
        assert!(is_disc_folder("Disk IV"));
        assert!(!is_disc_folder("disc"));
        assert!(!is_disc_folder("CD"));
        assert!(!is_disc_folder("Disk"));
        assert!(!is_disc_folder("discussion"));
    }

    #[test]
    fn incremental_previous_tracks_can_omit_cover_art_path() {
        let raw = r#"{"previous_tracks":[{"path":"/a.flac","folder_path":"/","title":"A","artist":"B","album":"C","album_artist":"B","track_number":1,"disc_number":1,"year":2020,"duration_ms":1000,"size_bytes":1,"modified_ms":2}]}"#;
        let request: IncrementalScanRequest = serde_json::from_str(raw).expect("parse");
        assert_eq!(request.previous_tracks[0].cover_art_path, None);
    }

    #[test]
    fn read_c_string_names_the_pointer() {
        let error = read_c_string(std::ptr::null(), "previous tracks json").unwrap_err();
        assert!(error.contains("previous tracks json"));
        assert!(!error.contains("root path pointer"));
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

    fn test_track(
        folder_path: &str,
        title: &str,
        artist: &str,
        album: &str,
        album_artist: &str,
        track_number: Option<i64>,
        year: Option<i64>,
    ) -> Track {
        Track {
            path: format!("{folder_path}/{title}.flac"),
            folder_path: folder_path.to_string(),
            title: title.to_string(),
            artist: artist.to_string(),
            album: album.to_string(),
            album_artist: album_artist.to_string(),
            track_number,
            disc_number: Some(1),
            year,
            duration_ms: Some(120000),
            size_bytes: 42,
            modified_ms: 99,
            cover_art_path: None,
        }
    }
}
