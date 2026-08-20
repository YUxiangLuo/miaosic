use crate::cover::MAX_COVER_BYTES;
use crate::models::{CoverImage, FlacMetadata, Track};
use crate::util::{
    first_tag, first_tag_ref, logical_folder_for, parse_file_name, parse_number, parse_year,
    path_to_utf8,
};
use std::collections::HashMap;
use std::fs::{self, File};
use std::io::{self, Read};
use std::path::Path;

pub(crate) fn parse_track(path: &Path) -> io::Result<Track> {
    let path_string =
        path_to_utf8(path).map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?;
    let folder_path = path_to_utf8(&logical_folder_for(path))
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?;
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
        path: path_string,
        folder_path,
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

pub(crate) fn track_file_state(path: &Path) -> io::Result<(i64, i64)> {
    let metadata = fs::metadata(path)?;
    let modified_ms = metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or(0);
    Ok((metadata.len() as i64, modified_ms))
}

pub(crate) fn read_flac_metadata(path: &Path) -> io::Result<FlacMetadata> {
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

pub(crate) fn read_flac_picture(path: &Path) -> io::Result<Option<CoverImage>> {
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

pub(crate) fn read_streaminfo_duration(block: &[u8]) -> Option<i64> {
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

pub(crate) fn read_vorbis_comments(block: &[u8]) -> HashMap<String, String> {
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

pub(crate) fn read_picture_data(block: &[u8]) -> Option<CoverImage> {
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
