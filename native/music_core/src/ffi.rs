use crate::models::{IncrementalScanRequest, ScanResponse, TrackCoverRequest, TrackCoverResponse};
use crate::scan::{extract_track_covers, scan_library, scan_library_incremental, ProgressCallback};
use serde::Serialize;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic::{self, AssertUnwindSafe};

#[no_mangle]
pub extern "C" fn miaosic_scan_library(root_path: *const c_char) -> *mut c_char {
    catch_native(|| miaosic_scan_library_with_covers(root_path, std::ptr::null()))
}

#[no_mangle]
pub extern "C" fn miaosic_scan_library_with_covers(
    root_path: *const c_char,
    cover_cache_dir: *const c_char,
) -> *mut c_char {
    catch_native(|| scan_library_response(root_path, cover_cache_dir, None))
}

#[no_mangle]
pub extern "C" fn miaosic_scan_library_with_covers_and_progress(
    root_path: *const c_char,
    cover_cache_dir: *const c_char,
    progress_callback: Option<ProgressCallback>,
) -> *mut c_char {
    catch_native(|| scan_library_response(root_path, cover_cache_dir, progress_callback))
}

#[no_mangle]
pub extern "C" fn miaosic_scan_library_incremental_with_covers_and_progress(
    root_path: *const c_char,
    previous_tracks_json: *const c_char,
    cover_cache_dir: *const c_char,
    progress_callback: Option<ProgressCallback>,
) -> *mut c_char {
    catch_native(|| {
        scan_library_incremental_response(
            root_path,
            previous_tracks_json,
            cover_cache_dir,
            progress_callback,
        )
    })
}

#[no_mangle]
pub extern "C" fn miaosic_extract_track_covers(
    paths_json: *const c_char,
    cover_cache_dir: *const c_char,
) -> *mut c_char {
    catch_native(|| {
        let response = match read_c_string(paths_json, "paths json") {
            Ok(raw) => match serde_json::from_str::<TrackCoverRequest>(&raw)
                .map_err(|error| error.to_string())
                .and_then(|request| {
                    read_optional_c_string(cover_cache_dir, "cover cache dir")
                        .map(|cache_dir| (request, cache_dir))
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
        respond_json(serialize_response(
            &response,
            "failed to serialize track cover response",
        ))
    })
}

fn scan_library_response(
    root_path: *const c_char,
    cover_cache_dir: *const c_char,
    progress_callback: Option<ProgressCallback>,
) -> *mut c_char {
    let response = match read_c_string(root_path, "root path") {
        Ok(root) => {
            match read_optional_c_string(cover_cache_dir, "cover cache dir").and_then(|cache_dir| {
                scan_library(&root, cache_dir.as_deref(), progress_callback)
                    .map_err(|error| error.to_string())
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
            }
        }
        Err(error) => ScanResponse {
            ok: false,
            error: Some(error),
            result: None,
        },
    };
    respond_json(serialize_response(
        &response,
        "failed to serialize scan response",
    ))
}

fn scan_library_incremental_response(
    root_path: *const c_char,
    previous_tracks_json: *const c_char,
    cover_cache_dir: *const c_char,
    progress_callback: Option<ProgressCallback>,
) -> *mut c_char {
    let response = match read_c_string(root_path, "root path") {
        Ok(root) => {
            let result = read_c_string(previous_tracks_json, "previous tracks json")
                .and_then(|raw| {
                    serde_json::from_str::<IncrementalScanRequest>(&raw)
                        .map_err(|error| error.to_string())
                })
                .and_then(|request| {
                    read_optional_c_string(cover_cache_dir, "cover cache dir")
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
    respond_json(serialize_response(
        &response,
        "failed to serialize incremental scan response",
    ))
}

pub(crate) fn catch_native<F>(work: F) -> *mut c_char
where
    F: FnOnce() -> *mut c_char,
{
    match panic::catch_unwind(AssertUnwindSafe(work)) {
        Ok(pointer) => pointer,
        Err(_) => respond_json(
            r#"{"ok":false,"error":"native panic: music_core aborted the request","result":null}"#
                .to_string(),
        ),
    }
}

pub(crate) fn serialize_response<T: Serialize>(value: &T, context: &str) -> String {
    serde_json::to_string(value).unwrap_or_else(|error| {
        format!(r#"{{"ok":false,"error":"{context}: {error}","result":null}}"#)
    })
}

pub(crate) fn respond_json(json: String) -> *mut c_char {
    let sanitized: String = json
        .chars()
        .filter(|character| *character != '\0')
        .collect();
    match CString::new(sanitized) {
        Ok(value) => value.into_raw(),
        Err(_) => {
            CString::new(r#"{"ok":false,"error":"failed to encode native response","result":null}"#)
                .expect("fallback response has no interior NUL")
                .into_raw()
        }
    }
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

pub(crate) fn read_c_string(value: *const c_char, name: &str) -> Result<String, String> {
    if value.is_null() {
        return Err(format!("{name} pointer is null"));
    }
    let raw = unsafe { CStr::from_ptr(value) };
    raw.to_str()
        .map(|value| value.to_string())
        .map_err(|error| format!("{name} is not valid UTF-8: {error}"))
}

pub(crate) fn read_optional_c_string(
    value: *const c_char,
    name: &str,
) -> Result<Option<String>, String> {
    if value.is_null() {
        return Ok(None);
    }
    read_c_string(value, name).map(Some)
}
