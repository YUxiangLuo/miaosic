use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{SampleFormat, Stream, StreamConfig};
use serde::Serialize;
use std::ffi::{CStr, CString};
use std::fs::File;
use std::io;
use std::os::raw::{c_char, c_longlong};
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::thread;
use symphonia::core::audio::GenericAudioBufferRef;
use symphonia::core::codecs::audio::{
    AudioCodecParameters, AudioDecoderOptions, CODEC_ID_NULL_AUDIO,
};
use symphonia::core::errors::Error as SymphoniaError;
use symphonia::core::formats::{probe::Hint, FormatOptions, Track};
use symphonia::core::io::{MediaSourceStream, MediaSourceStreamOptions};
use symphonia::core::meta::MetadataOptions;
use symphonia::core::units::Timestamp;

#[derive(Serialize)]
struct PlaybackResponse<T: Serialize> {
    ok: bool,
    error: Option<String>,
    result: Option<T>,
}

#[derive(Default, Serialize)]
struct PlaybackState {
    playing: bool,
    position_ms: u64,
    duration_ms: u64,
    completed_seq: u64,
    loaded: bool,
}

#[cfg(test)]
struct DecodedAudio {
    samples: Vec<f32>,
    duration_ms: u64,
}

#[derive(Default)]
struct SharedPlayback {
    samples: Vec<f32>,
    position_samples: usize,
    duration_ms: u64,
    playing: bool,
    completed: bool,
    completed_seq: u64,
    generation: u64,
    decoding: bool,
    opened: bool,
}

struct AudioPlayer {
    shared: Arc<Mutex<SharedPlayback>>,
    _stream: Stream,
    output_sample_rate: u32,
    output_channels: usize,
}

impl AudioPlayer {
    fn new() -> Result<Self, String> {
        let host = cpal::default_host();
        let device = host
            .default_output_device()
            .ok_or_else(|| "no default output device is available".to_string())?;
        let supported_config = device
            .default_output_config()
            .map_err(|error| format!("failed to get default output config: {error}"))?;
        let sample_format = supported_config.sample_format();
        let output_sample_rate = supported_config.sample_rate();
        let output_channels = supported_config.channels() as usize;
        let config = supported_config.config();
        let shared = Arc::new(Mutex::new(SharedPlayback::default()));
        let err_fn = |error| eprintln!("Miaosic Rust playback stream error: {error}");
        let stream = match sample_format {
            SampleFormat::F32 => {
                build_output_stream_f32(&device, config.clone(), shared.clone(), err_fn)
            }
            SampleFormat::F64 => {
                build_output_stream_f64(&device, config.clone(), shared.clone(), err_fn)
            }
            SampleFormat::I8 => {
                build_output_stream_i8(&device, config.clone(), shared.clone(), err_fn)
            }
            SampleFormat::I16 => {
                build_output_stream_i16(&device, config.clone(), shared.clone(), err_fn)
            }
            SampleFormat::I32 => {
                build_output_stream_i32(&device, config.clone(), shared.clone(), err_fn)
            }
            SampleFormat::U8 => {
                build_output_stream_u8(&device, config.clone(), shared.clone(), err_fn)
            }
            SampleFormat::U16 => {
                build_output_stream_u16(&device, config.clone(), shared.clone(), err_fn)
            }
            SampleFormat::U32 => build_output_stream_u32(&device, config, shared.clone(), err_fn),
            other => Err(format!("unsupported output sample format: {other:?}")),
        }?;
        stream
            .play()
            .map_err(|error| format!("failed to start output stream: {error}"))?;
        Ok(Self {
            shared,
            _stream: stream,
            output_sample_rate,
            output_channels,
        })
    }

    fn open(&self, path: &str, play: bool) -> Result<(), String> {
        let generation = {
            let mut shared = self.shared.lock().map_err(lock_error)?;
            shared.begin_open(play)
        };
        let file = match File::open(path) {
            Ok(file) => file,
            Err(error) => {
                self.finish_open_error(generation)?;
                return Err(format!("failed to open audio file: {error}"));
            }
        };
        let path = path.to_string();
        let log_path = path.clone();
        let shared = self.shared.clone();
        let output_sample_rate = self.output_sample_rate;
        let output_channels = self.output_channels;
        thread::spawn(move || {
            if let Err(error) = decode_audio_file_streaming(
                path,
                file,
                output_sample_rate,
                output_channels,
                shared.clone(),
                generation,
            ) {
                if finish_decode_error(&shared, generation).unwrap_or(false) {
                    eprintln!("Miaosic Rust playback decode failed for {log_path}: {error}");
                }
            }
        });
        Ok(())
    }

    fn play(&self) -> Result<(), String> {
        let mut shared = self.shared.lock().map_err(lock_error)?;
        if shared.opened && (shared.decoding || shared.position_samples < shared.samples.len()) {
            shared.playing = true;
            shared.completed = false;
        }
        Ok(())
    }

    fn pause(&self) -> Result<(), String> {
        let mut shared = self.shared.lock().map_err(lock_error)?;
        shared.playing = false;
        Ok(())
    }

    fn stop(&self) -> Result<(), String> {
        let mut shared = self.shared.lock().map_err(lock_error)?;
        shared.cancel_current();
        Ok(())
    }

    fn seek(&self, position_ms: u64) -> Result<(), String> {
        let mut shared = self.shared.lock().map_err(lock_error)?;
        let frame = position_ms.saturating_mul(self.output_sample_rate as u64) / 1000;
        let position_samples = frame as usize * self.output_channels;
        shared.position_samples = position_samples.min(shared.samples.len());
        shared.completed = false;
        Ok(())
    }

    fn state(&self) -> Result<PlaybackState, String> {
        let shared = self.shared.lock().map_err(lock_error)?;
        Ok(PlaybackState {
            playing: shared.playing,
            position_ms: position_ms(
                shared.position_samples,
                self.output_sample_rate,
                self.output_channels,
            ),
            duration_ms: shared.duration_ms,
            completed_seq: shared.completed_seq,
            loaded: shared.opened,
        })
    }

    fn finish_open_error(&self, generation: u64) -> Result<(), String> {
        let mut shared = self.shared.lock().map_err(lock_error)?;
        if shared.generation == generation {
            shared.clear_loaded_audio();
        }
        Ok(())
    }
}

impl SharedPlayback {
    fn begin_open(&mut self, play: bool) -> u64 {
        self.generation = self.generation.wrapping_add(1);
        self.samples.clear();
        self.position_samples = 0;
        self.duration_ms = 0;
        self.playing = play;
        self.completed = false;
        self.decoding = true;
        self.opened = true;
        self.generation
    }

    fn cancel_current(&mut self) {
        self.generation = self.generation.wrapping_add(1);
        self.clear_loaded_audio();
    }

    fn clear_loaded_audio(&mut self) {
        self.samples.clear();
        self.position_samples = 0;
        self.duration_ms = 0;
        self.playing = false;
        self.completed = false;
        self.decoding = false;
        self.opened = false;
    }
}

static PLAYER: Mutex<Option<&'static AudioPlayer>> = Mutex::new(None);

#[no_mangle]
pub extern "C" fn miaosic_playback_open(path: *const c_char, play: bool) -> *mut c_char {
    let result = read_c_string(path).and_then(|path| player()?.open(&path, play));
    response(result.map(|_| ()))
}

#[no_mangle]
pub extern "C" fn miaosic_playback_play() -> *mut c_char {
    response(optional_player_command(AudioPlayer::play))
}

#[no_mangle]
pub extern "C" fn miaosic_playback_pause() -> *mut c_char {
    response(optional_player_command(AudioPlayer::pause))
}

#[no_mangle]
pub extern "C" fn miaosic_playback_stop() -> *mut c_char {
    response(optional_player_command(AudioPlayer::stop))
}

#[no_mangle]
pub extern "C" fn miaosic_playback_seek(position_ms: c_longlong) -> *mut c_char {
    let position_ms = u64::try_from(position_ms).unwrap_or(0);
    response(optional_player_command(|player| player.seek(position_ms)))
}

#[no_mangle]
pub extern "C" fn miaosic_playback_state() -> *mut c_char {
    response(playback_state())
}

fn player() -> Result<&'static AudioPlayer, String> {
    let mut player = PLAYER.lock().map_err(lock_error)?;
    if let Some(player) = *player {
        return Ok(player);
    }
    let new_player = Box::leak(Box::new(AudioPlayer::new()?));
    *player = Some(new_player);
    Ok(new_player)
}

fn existing_player() -> Result<Option<&'static AudioPlayer>, String> {
    let player = PLAYER.lock().map_err(lock_error)?;
    Ok(*player)
}

fn optional_player_command(
    command: impl FnOnce(&AudioPlayer) -> Result<(), String>,
) -> Result<(), String> {
    if let Some(player) = existing_player()? {
        command(player)?;
    }
    Ok(())
}

fn playback_state() -> Result<PlaybackState, String> {
    match existing_player()? {
        Some(player) => player.state(),
        None => Ok(PlaybackState::default()),
    }
}

fn build_output_stream_f32(
    device: &cpal::Device,
    config: StreamConfig,
    shared: Arc<Mutex<SharedPlayback>>,
    err_fn: impl FnMut(cpal::Error) + Send + 'static,
) -> Result<Stream, String> {
    device
        .build_output_stream(
            config,
            move |data: &mut [f32], _| fill_output(data, &shared, |sample| sample),
            err_fn,
            None,
        )
        .map_err(|error| format!("failed to build f32 output stream: {error}"))
}

fn build_output_stream_f64(
    device: &cpal::Device,
    config: StreamConfig,
    shared: Arc<Mutex<SharedPlayback>>,
    err_fn: impl FnMut(cpal::Error) + Send + 'static,
) -> Result<Stream, String> {
    device
        .build_output_stream(
            config,
            move |data: &mut [f64], _| fill_output(data, &shared, |sample| sample as f64),
            err_fn,
            None,
        )
        .map_err(|error| format!("failed to build f64 output stream: {error}"))
}

fn build_output_stream_i8(
    device: &cpal::Device,
    config: StreamConfig,
    shared: Arc<Mutex<SharedPlayback>>,
    err_fn: impl FnMut(cpal::Error) + Send + 'static,
) -> Result<Stream, String> {
    device
        .build_output_stream(
            config,
            move |data: &mut [i8], _| fill_output(data, &shared, sample_to_i8),
            err_fn,
            None,
        )
        .map_err(|error| format!("failed to build i8 output stream: {error}"))
}

fn build_output_stream_i16(
    device: &cpal::Device,
    config: StreamConfig,
    shared: Arc<Mutex<SharedPlayback>>,
    err_fn: impl FnMut(cpal::Error) + Send + 'static,
) -> Result<Stream, String> {
    device
        .build_output_stream(
            config,
            move |data: &mut [i16], _| fill_output(data, &shared, sample_to_i16),
            err_fn,
            None,
        )
        .map_err(|error| format!("failed to build i16 output stream: {error}"))
}

fn build_output_stream_i32(
    device: &cpal::Device,
    config: StreamConfig,
    shared: Arc<Mutex<SharedPlayback>>,
    err_fn: impl FnMut(cpal::Error) + Send + 'static,
) -> Result<Stream, String> {
    device
        .build_output_stream(
            config,
            move |data: &mut [i32], _| fill_output(data, &shared, sample_to_i32),
            err_fn,
            None,
        )
        .map_err(|error| format!("failed to build i32 output stream: {error}"))
}

fn build_output_stream_u8(
    device: &cpal::Device,
    config: StreamConfig,
    shared: Arc<Mutex<SharedPlayback>>,
    err_fn: impl FnMut(cpal::Error) + Send + 'static,
) -> Result<Stream, String> {
    device
        .build_output_stream(
            config,
            move |data: &mut [u8], _| fill_output(data, &shared, sample_to_u8),
            err_fn,
            None,
        )
        .map_err(|error| format!("failed to build u8 output stream: {error}"))
}

fn build_output_stream_u16(
    device: &cpal::Device,
    config: StreamConfig,
    shared: Arc<Mutex<SharedPlayback>>,
    err_fn: impl FnMut(cpal::Error) + Send + 'static,
) -> Result<Stream, String> {
    device
        .build_output_stream(
            config,
            move |data: &mut [u16], _| fill_output(data, &shared, sample_to_u16),
            err_fn,
            None,
        )
        .map_err(|error| format!("failed to build u16 output stream: {error}"))
}

fn build_output_stream_u32(
    device: &cpal::Device,
    config: StreamConfig,
    shared: Arc<Mutex<SharedPlayback>>,
    err_fn: impl FnMut(cpal::Error) + Send + 'static,
) -> Result<Stream, String> {
    device
        .build_output_stream(
            config,
            move |data: &mut [u32], _| fill_output(data, &shared, sample_to_u32),
            err_fn,
            None,
        )
        .map_err(|error| format!("failed to build u32 output stream: {error}"))
}

fn fill_output<T>(data: &mut [T], shared: &Arc<Mutex<SharedPlayback>>, convert: fn(f32) -> T)
where
    T: Copy + Default,
{
    let Ok(mut shared) = shared.lock() else {
        data.fill(T::default());
        return;
    };
    for sample in data {
        let next = if shared.playing && shared.position_samples < shared.samples.len() {
            let value = shared.samples[shared.position_samples];
            shared.position_samples += 1;
            value
        } else {
            if shared.playing && shared.position_samples >= shared.samples.len() && !shared.decoding
            {
                shared.playing = false;
                if !shared.completed {
                    shared.completed = true;
                    shared.completed_seq = shared.completed_seq.saturating_add(1);
                }
            }
            0.0
        };
        *sample = convert(next);
    }
}

fn decode_audio_file_streaming(
    path: String,
    file: File,
    target_sample_rate: u32,
    target_channels: usize,
    shared: Arc<Mutex<SharedPlayback>>,
    generation: u64,
) -> Result<(), String> {
    let source = MediaSourceStream::new(Box::new(file), MediaSourceStreamOptions::default());
    let mut hint = Hint::new();
    if let Some(extension) = Path::new(&path)
        .extension()
        .and_then(|value| value.to_str())
    {
        hint.with_extension(extension);
    }
    let mut format = symphonia::default::get_probe()
        .probe(
            &hint,
            source,
            FormatOptions::default(),
            MetadataOptions::default(),
        )
        .map_err(|error| format!("failed to probe audio file: {error}"))?;
    let (track_id, codec_params, metadata_duration_ms) = select_audio_track(format.tracks())?;
    if let Some(duration_ms) = metadata_duration_ms {
        if !update_stream_duration(&shared, generation, duration_ms)? {
            return Ok(());
        }
    }
    let mut decoder = symphonia::default::get_codecs()
        .make_audio_decoder(&codec_params, &AudioDecoderOptions::default())
        .map_err(|error| format!("failed to create decoder: {error}"))?;
    let mut source_samples = Vec::new();
    let mut converted_frames = 0usize;
    let mut source_sample_rate = codec_params.sample_rate.unwrap_or(0);
    let mut source_channels = codec_params
        .channels
        .map(|channels| channels.count())
        .unwrap_or(0);

    loop {
        let packet = match format.next_packet() {
            Ok(Some(packet)) => packet,
            Ok(None) => break,
            Err(SymphoniaError::IoError(error)) if error.kind() == io::ErrorKind::UnexpectedEof => {
                break
            }
            Err(error) => return Err(format!("failed to read audio packet: {error}")),
        };
        if packet.track_id != track_id {
            continue;
        }
        let decoded = match decoder.decode(&packet) {
            Ok(decoded) => decoded,
            Err(SymphoniaError::DecodeError(_)) => continue,
            Err(error) => return Err(format!("failed to decode audio packet: {error}")),
        };
        source_sample_rate = decoded.spec().rate();
        source_channels = decoded.spec().channels().count();
        append_interleaved(&decoded, &mut source_samples);
        let converted = convert_available_samples(
            &source_samples,
            source_sample_rate,
            source_channels,
            target_sample_rate,
            target_channels,
            &mut converted_frames,
        );
        if !converted.is_empty()
            && !append_streamed_samples(
                &shared,
                generation,
                &converted,
                metadata_duration_ms,
                target_sample_rate,
                target_channels,
            )?
        {
            return Ok(());
        }
    }

    if source_samples.is_empty() || source_sample_rate == 0 || source_channels == 0 {
        return Err("audio file did not decode to PCM samples".to_string());
    }
    finish_decode_success(
        &shared,
        generation,
        metadata_duration_ms.unwrap_or_else(|| {
            position_ms(
                converted_frames * target_channels,
                target_sample_rate,
                target_channels,
            )
        }),
    )?;
    Ok(())
}

#[cfg(test)]
fn decode_audio_file(
    path: &str,
    target_sample_rate: u32,
    target_channels: usize,
) -> Result<DecodedAudio, String> {
    let file = File::open(path).map_err(|error| format!("failed to open audio file: {error}"))?;
    let source = MediaSourceStream::new(Box::new(file), MediaSourceStreamOptions::default());
    let mut hint = Hint::new();
    if let Some(extension) = Path::new(path).extension().and_then(|value| value.to_str()) {
        hint.with_extension(extension);
    }
    let mut format = symphonia::default::get_probe()
        .probe(
            &hint,
            source,
            FormatOptions::default(),
            MetadataOptions::default(),
        )
        .map_err(|error| format!("failed to probe audio file: {error}"))?;
    let (track_id, codec_params, _) = select_audio_track(format.tracks())?;
    let mut decoder = symphonia::default::get_codecs()
        .make_audio_decoder(&codec_params, &AudioDecoderOptions::default())
        .map_err(|error| format!("failed to create decoder: {error}"))?;
    let mut samples = Vec::new();
    let mut source_sample_rate = codec_params.sample_rate.unwrap_or(0);
    let mut source_channels = codec_params
        .channels
        .map(|channels| channels.count())
        .unwrap_or(0);

    loop {
        let packet = match format.next_packet() {
            Ok(Some(packet)) => packet,
            Ok(None) => break,
            Err(SymphoniaError::IoError(error)) if error.kind() == io::ErrorKind::UnexpectedEof => {
                break
            }
            Err(error) => return Err(format!("failed to read audio packet: {error}")),
        };
        if packet.track_id != track_id {
            continue;
        }
        let decoded = match decoder.decode(&packet) {
            Ok(decoded) => decoded,
            Err(SymphoniaError::DecodeError(_)) => continue,
            Err(error) => return Err(format!("failed to decode audio packet: {error}")),
        };
        source_sample_rate = decoded.spec().rate();
        source_channels = decoded.spec().channels().count();
        append_interleaved(&decoded, &mut samples);
    }

    if samples.is_empty() || source_sample_rate == 0 || source_channels == 0 {
        return Err("audio file did not decode to PCM samples".to_string());
    }
    let converted = convert_samples(
        &samples,
        source_sample_rate,
        source_channels,
        target_sample_rate,
        target_channels,
    );
    let duration_ms = position_ms(converted.len(), target_sample_rate, target_channels);
    Ok(DecodedAudio {
        samples: converted,
        duration_ms,
    })
}

fn select_audio_track(
    tracks: &[Track],
) -> Result<(u32, AudioCodecParameters, Option<u64>), String> {
    tracks
        .iter()
        .find_map(|track| {
            let codec_params = track.codec_params.as_ref()?.audio()?;
            if codec_params.codec == CODEC_ID_NULL_AUDIO {
                return None;
            }
            Some((
                track.id,
                codec_params.clone(),
                track_duration_ms(track, codec_params),
            ))
        })
        .ok_or_else(|| "audio file does not contain a supported audio track".to_string())
}

fn track_duration_ms(track: &Track, codec_params: &AudioCodecParameters) -> Option<u64> {
    if let (Some(duration), Some(time_base)) = (track.duration, track.time_base) {
        let ticks = i64::try_from(duration.get()).ok()?;
        let time = time_base.calc_time(Timestamp::new(ticks))?;
        let (seconds, nanos) = time.parts();
        if seconds >= 0 {
            let millis = seconds as u128 * 1000 + nanos as u128 / 1_000_000;
            return u64::try_from(millis).ok();
        }
    }
    let sample_rate = codec_params.sample_rate?;
    let frames = track.num_frames?;
    Some(frames.saturating_mul(1000) / sample_rate as u64)
}

fn update_stream_duration(
    shared: &Arc<Mutex<SharedPlayback>>,
    generation: u64,
    duration_ms: u64,
) -> Result<bool, String> {
    let mut shared = shared.lock().map_err(lock_error)?;
    if shared.generation != generation {
        return Ok(false);
    }
    shared.duration_ms = duration_ms;
    Ok(true)
}

fn append_streamed_samples(
    shared: &Arc<Mutex<SharedPlayback>>,
    generation: u64,
    samples: &[f32],
    metadata_duration_ms: Option<u64>,
    target_sample_rate: u32,
    target_channels: usize,
) -> Result<bool, String> {
    let mut shared = shared.lock().map_err(lock_error)?;
    if shared.generation != generation {
        return Ok(false);
    }
    shared.samples.extend_from_slice(samples);
    shared.duration_ms = metadata_duration_ms
        .unwrap_or_else(|| position_ms(shared.samples.len(), target_sample_rate, target_channels));
    Ok(true)
}

fn finish_decode_success(
    shared: &Arc<Mutex<SharedPlayback>>,
    generation: u64,
    duration_ms: u64,
) -> Result<(), String> {
    let mut shared = shared.lock().map_err(lock_error)?;
    if shared.generation != generation {
        return Ok(());
    }
    shared.decoding = false;
    shared.duration_ms = duration_ms;
    if shared.samples.is_empty() {
        shared.opened = false;
        shared.playing = false;
    }
    Ok(())
}

fn finish_decode_error(
    shared: &Arc<Mutex<SharedPlayback>>,
    generation: u64,
) -> Result<bool, String> {
    let mut shared = shared.lock().map_err(lock_error)?;
    if shared.generation != generation {
        return Ok(false);
    }
    shared.decoding = false;
    if shared.samples.is_empty() {
        let should_report_completion = shared.playing;
        shared.opened = false;
        shared.playing = false;
        shared.duration_ms = 0;
        if should_report_completion && !shared.completed {
            shared.completed = true;
            shared.completed_seq = shared.completed_seq.saturating_add(1);
        }
    }
    Ok(true)
}

fn append_interleaved(decoded: &GenericAudioBufferRef<'_>, samples: &mut Vec<f32>) {
    let mut packet_samples =
        Vec::with_capacity(decoded.frames() * decoded.spec().channels().count());
    decoded.copy_to_vec_interleaved(&mut packet_samples);
    samples.extend_from_slice(&packet_samples);
}

#[cfg(test)]
fn convert_samples(
    samples: &[f32],
    source_sample_rate: u32,
    source_channels: usize,
    target_sample_rate: u32,
    target_channels: usize,
) -> Vec<f32> {
    let mut converted_frames = 0;
    convert_available_samples(
        samples,
        source_sample_rate,
        source_channels,
        target_sample_rate,
        target_channels,
        &mut converted_frames,
    )
}

fn convert_available_samples(
    samples: &[f32],
    source_sample_rate: u32,
    source_channels: usize,
    target_sample_rate: u32,
    target_channels: usize,
    converted_frames: &mut usize,
) -> Vec<f32> {
    if source_channels == 0
        || source_sample_rate == 0
        || target_sample_rate == 0
        || target_channels == 0
    {
        return Vec::new();
    }
    let source_frames = samples.len() / source_channels;
    if source_frames == 0 {
        return Vec::new();
    }
    let target_frames = ((source_frames as u128 * target_sample_rate as u128)
        / source_sample_rate as u128) as usize;
    if target_frames <= *converted_frames {
        return Vec::new();
    }
    let mut converted = Vec::with_capacity((target_frames - *converted_frames) * target_channels);
    for target_frame in *converted_frames..target_frames {
        let source_position =
            target_frame as f64 * source_sample_rate as f64 / target_sample_rate as f64;
        let base_frame = source_position.floor() as usize;
        let next_frame = (base_frame + 1).min(source_frames - 1);
        let fraction = (source_position - base_frame as f64) as f32;
        for target_channel in 0..target_channels {
            converted.push(interpolated_channel(
                samples,
                source_channels,
                target_channel,
                target_channels,
                base_frame,
                next_frame,
                fraction,
            ));
        }
    }
    *converted_frames = target_frames;
    converted
}

fn interpolated_channel(
    samples: &[f32],
    source_channels: usize,
    target_channel: usize,
    target_channels: usize,
    base_frame: usize,
    next_frame: usize,
    fraction: f32,
) -> f32 {
    let base = mapped_channel_sample(
        samples,
        source_channels,
        target_channel,
        target_channels,
        base_frame,
    );
    let next = mapped_channel_sample(
        samples,
        source_channels,
        target_channel,
        target_channels,
        next_frame,
    );
    base + (next - base) * fraction
}

fn mapped_channel_sample(
    samples: &[f32],
    source_channels: usize,
    target_channel: usize,
    target_channels: usize,
    frame: usize,
) -> f32 {
    if source_channels == target_channels {
        return samples[frame * source_channels + target_channel];
    }
    if source_channels == 1 {
        return samples[frame * source_channels];
    }
    if target_channels == 1 {
        let start = frame * source_channels;
        return samples[start..start + source_channels].iter().sum::<f32>()
            / source_channels as f32;
    }
    let source_channel = target_channel.min(source_channels - 1);
    samples[frame * source_channels + source_channel]
}

fn position_ms(position_samples: usize, sample_rate: u32, channels: usize) -> u64 {
    if sample_rate == 0 || channels == 0 {
        return 0;
    }
    let frames = position_samples / channels;
    frames as u64 * 1000 / sample_rate as u64
}

fn read_c_string(value: *const c_char) -> Result<String, String> {
    if value.is_null() {
        return Err("audio path pointer is null".to_string());
    }
    let raw = unsafe { CStr::from_ptr(value) };
    raw.to_str()
        .map(|value| value.to_string())
        .map_err(|error| format!("audio path is not valid UTF-8: {error}"))
}

fn response<T: Serialize>(result: Result<T, String>) -> *mut c_char {
    let response = match result {
        Ok(result) => PlaybackResponse {
            ok: true,
            error: None,
            result: Some(result),
        },
        Err(error) => PlaybackResponse {
            ok: false,
            error: Some(error),
            result: None,
        },
    };
    let json = serde_json::to_string(&response).unwrap_or_else(|error| {
        format!(r#"{{"ok":false,"error":"failed to serialize playback response: {error}","result":null}}"#)
    });
    CString::new(json).unwrap().into_raw()
}

fn lock_error<T>(error: std::sync::PoisonError<T>) -> String {
    format!("playback state lock failed: {error}")
}

fn sample_to_i8(sample: f32) -> i8 {
    (sample.clamp(-1.0, 1.0) * i8::MAX as f32) as i8
}

fn sample_to_i16(sample: f32) -> i16 {
    (sample.clamp(-1.0, 1.0) * i16::MAX as f32) as i16
}

fn sample_to_i32(sample: f32) -> i32 {
    (sample.clamp(-1.0, 1.0) * i32::MAX as f32) as i32
}

fn sample_to_u8(sample: f32) -> u8 {
    ((sample.clamp(-1.0, 1.0) * 0.5 + 0.5) * u8::MAX as f32) as u8
}

fn sample_to_u16(sample: f32) -> u16 {
    ((sample.clamp(-1.0, 1.0) * 0.5 + 0.5) * u16::MAX as f32) as u16
}

fn sample_to_u32(sample: f32) -> u32 {
    ((sample.clamp(-1.0, 1.0) * 0.5 + 0.5) * u32::MAX as f32) as u32
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use symphonia::core::audio::{AudioBuffer, AudioSpec, Channels};

    #[test]
    fn converts_mono_to_stereo_without_resampling() {
        let converted = convert_samples(&[0.25, -0.5], 44100, 1, 44100, 2);

        assert_eq!(converted, vec![0.25, 0.25, -0.5, -0.5]);
    }

    #[test]
    fn maps_stereo_to_mono_by_averaging_channels() {
        let converted = convert_samples(&[0.25, 0.75, -0.5, 0.25], 44100, 2, 44100, 1);

        assert_eq!(converted, vec![0.5, -0.125]);
    }

    #[test]
    fn appends_interleaved_packets_without_overwriting_previous_packet() {
        let spec = AudioSpec::new(44100, Channels::Discrete(1));
        let mut first = AudioBuffer::<f32>::new(spec.clone(), 2);
        first.render(Some(2), &[0.25]);
        let mut second = AudioBuffer::<f32>::new(spec, 1);
        second.render(Some(1), &[-0.5]);

        let mut samples = Vec::new();
        append_interleaved(&GenericAudioBufferRef::F32(&first), &mut samples);
        append_interleaved(&GenericAudioBufferRef::F32(&second), &mut samples);

        assert_eq!(samples, vec![0.25, 0.25, -0.5]);
    }

    #[test]
    fn incremental_conversion_matches_full_conversion_across_chunks() {
        let first = [0.0, 0.25, 0.5, 0.75];
        let second = [1.0, 0.5, 0.25, 0.0];
        let mut source_samples = Vec::new();
        let mut converted_frames = 0;
        source_samples.extend_from_slice(&first);
        let mut chunked =
            convert_available_samples(&source_samples, 44100, 2, 48000, 2, &mut converted_frames);
        source_samples.extend_from_slice(&second);
        chunked.extend(convert_available_samples(
            &source_samples,
            44100,
            2,
            48000,
            2,
            &mut converted_frames,
        ));

        assert_eq!(
            chunked,
            convert_samples(&source_samples, 44100, 2, 48000, 2)
        );
    }

    #[test]
    fn output_waits_when_decoder_has_not_filled_buffer_yet() {
        let shared = Arc::new(Mutex::new(SharedPlayback {
            playing: true,
            decoding: true,
            opened: true,
            ..SharedPlayback::default()
        }));
        let mut output = [1.0f32; 4];

        fill_output(&mut output, &shared, |sample| sample);

        assert_eq!(output, [0.0; 4]);
        let shared = shared.lock().expect("lock shared playback");
        assert!(shared.playing);
        assert!(!shared.completed);
        assert_eq!(shared.completed_seq, 0);
    }

    #[test]
    fn state_poll_without_player_returns_default_without_initializing_audio() {
        if existing_player().expect("read existing player").is_some() {
            return;
        }

        let state = playback_state().expect("read default playback state");

        assert!(!state.playing);
        assert_eq!(state.position_ms, 0);
        assert_eq!(state.duration_ms, 0);
        assert_eq!(state.completed_seq, 0);
        assert!(!state.loaded);
        assert!(existing_player().expect("read existing player").is_none());
    }

    #[test]
    fn decode_error_before_samples_reports_completion_when_playing() {
        let shared = Arc::new(Mutex::new(SharedPlayback {
            generation: 7,
            playing: true,
            decoding: true,
            opened: true,
            ..SharedPlayback::default()
        }));

        assert!(finish_decode_error(&shared, 7).expect("finish decode error"));

        let shared = shared.lock().expect("lock shared playback");
        assert!(!shared.playing);
        assert!(!shared.decoding);
        assert!(!shared.opened);
        assert!(shared.completed);
        assert_eq!(shared.completed_seq, 1);
    }

    #[test]
    fn decodes_pcm_wav_and_converts_to_target_channels() {
        let path =
            std::env::temp_dir().join(format!("miaosic-playback-test-{}.wav", std::process::id()));
        fs::write(&path, test_wav_bytes()).expect("write test wav");

        let decoded = decode_audio_file(path.to_str().expect("utf-8 path"), 1000, 2)
            .expect("decode wav through symphonia");

        fs::remove_file(path).ok();
        assert_eq!(decoded.samples.len(), 4);
        assert_eq!(decoded.duration_ms, 2);
        assert_eq!(decoded.samples[0], 0.0);
        assert_eq!(decoded.samples[1], 0.0);
        assert!(decoded.samples[2] > 0.99);
        assert!(decoded.samples[3] > 0.99);
    }

    fn test_wav_bytes() -> Vec<u8> {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"RIFF");
        bytes.extend_from_slice(&40u32.to_le_bytes());
        bytes.extend_from_slice(b"WAVE");
        bytes.extend_from_slice(b"fmt ");
        bytes.extend_from_slice(&16u32.to_le_bytes());
        bytes.extend_from_slice(&1u16.to_le_bytes());
        bytes.extend_from_slice(&1u16.to_le_bytes());
        bytes.extend_from_slice(&1000u32.to_le_bytes());
        bytes.extend_from_slice(&2000u32.to_le_bytes());
        bytes.extend_from_slice(&2u16.to_le_bytes());
        bytes.extend_from_slice(&16u16.to_le_bytes());
        bytes.extend_from_slice(b"data");
        bytes.extend_from_slice(&4u32.to_le_bytes());
        bytes.extend_from_slice(&0i16.to_le_bytes());
        bytes.extend_from_slice(&i16::MAX.to_le_bytes());
        bytes
    }
}
