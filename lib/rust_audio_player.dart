import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'rust_library.dart';

typedef _PlaybackOpenNative =
    Pointer<Utf8> Function(Pointer<Utf8> path, Bool play);
typedef _PlaybackOpenDart =
    Pointer<Utf8> Function(Pointer<Utf8> path, bool play);
typedef _PlaybackSeekNative = Pointer<Utf8> Function(Int64 positionMs);
typedef _PlaybackSeekDart = Pointer<Utf8> Function(int positionMs);
typedef _PlaybackCommandNative = Pointer<Utf8> Function();
typedef _PlaybackCommandDart = Pointer<Utf8> Function();
typedef _FreeStringNative = Void Function(Pointer<Utf8> value);
typedef _FreeStringDart = void Function(Pointer<Utf8> value);

class RustAudioPlayer {
  RustAudioPlayer._(DynamicLibrary library)
    : _open = library.lookupFunction<_PlaybackOpenNative, _PlaybackOpenDart>(
        'miaosic_playback_open',
      ),
      _play = library
          .lookupFunction<_PlaybackCommandNative, _PlaybackCommandDart>(
            'miaosic_playback_play',
          ),
      _pause = library
          .lookupFunction<_PlaybackCommandNative, _PlaybackCommandDart>(
            'miaosic_playback_pause',
          ),
      _stop = library
          .lookupFunction<_PlaybackCommandNative, _PlaybackCommandDart>(
            'miaosic_playback_stop',
          ),
      _seek = library.lookupFunction<_PlaybackSeekNative, _PlaybackSeekDart>(
        'miaosic_playback_seek',
      ),
      _state = library
          .lookupFunction<_PlaybackCommandNative, _PlaybackCommandDart>(
            'miaosic_playback_state',
          ),
      _freeString = library.lookupFunction<_FreeStringNative, _FreeStringDart>(
        'miaosic_free_string',
      );

  final _PlaybackOpenDart _open;
  final _PlaybackCommandDart _play;
  final _PlaybackCommandDart _pause;
  final _PlaybackCommandDart _stop;
  final _PlaybackSeekDart _seek;
  final _PlaybackCommandDart _state;
  final _FreeStringDart _freeString;

  static RustAudioPlayer? tryLoad() {
    for (final candidate in musicCoreLibraryCandidates()) {
      try {
        return RustAudioPlayer._(DynamicLibrary.open(candidate));
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  void open(String path, {required bool play}) {
    final pathPointer = path.toNativeUtf8();
    try {
      _decodeResponse(_open(pathPointer, play), 'open audio file');
    } finally {
      calloc.free(pathPointer);
    }
  }

  void play() {
    _decodeResponse(_play(), 'start playback');
  }

  void pause() {
    _decodeResponse(_pause(), 'pause playback');
  }

  void stop() {
    _decodeResponse(_stop(), 'stop playback');
  }

  void seek(Duration position) {
    final positionMs = position.inMilliseconds < 0
        ? 0
        : position.inMilliseconds;
    _decodeResponse(_seek(positionMs), 'seek playback');
  }

  RustPlaybackState state() {
    final result = _decodeResponse(_state(), 'read playback state');
    final json = result as Map<String, Object?>?;
    if (json == null) {
      throw const FormatException('Rust playback state response was empty');
    }
    return RustPlaybackState.fromJson(json);
  }

  Object? _decodeResponse(Pointer<Utf8> responsePointer, String operation) {
    try {
      if (responsePointer == nullptr) {
        throw FormatException(
          'Rust playback returned null while trying to $operation',
        );
      }
      final raw = responsePointer.toDartString();
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      if (decoded['ok'] != true) {
        throw StateError(
          decoded['error'] as String? ??
              'Rust playback failed during $operation',
        );
      }
      return decoded['result'];
    } finally {
      if (responsePointer != nullptr) {
        _freeString(responsePointer);
      }
    }
  }
}

class RustPlaybackState {
  const RustPlaybackState({
    required this.playing,
    required this.position,
    required this.duration,
    required this.completedSeq,
    required this.loaded,
  });

  final bool playing;
  final Duration position;
  final Duration duration;
  final int completedSeq;
  final bool loaded;

  static RustPlaybackState fromJson(Map<String, Object?> json) {
    return RustPlaybackState(
      playing: json['playing'] as bool? ?? false,
      position: Duration(milliseconds: _int(json['position_ms']) ?? 0),
      duration: Duration(milliseconds: _int(json['duration_ms']) ?? 0),
      completedSeq: _int(json['completed_seq']) ?? 0,
      loaded: json['loaded'] as bool? ?? false,
    );
  }
}

int? _int(Object? value) {
  if (value == null) {
    return null;
  }
  return (value as num).toInt();
}
