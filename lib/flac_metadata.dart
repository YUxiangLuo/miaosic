import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class FlacMetadata {
  const FlacMetadata({required this.tags, required this.durationMs});

  final Map<String, String> tags;
  final int? durationMs;
}

Future<FlacMetadata> readFlacMetadata(File file) async {
  final reader = await file.open();
  try {
    final marker = await reader.read(4);
    if (marker.length != 4 ||
        ascii.decode(marker, allowInvalid: true) != 'fLaC') {
      return const FlacMetadata(tags: {}, durationMs: null);
    }

    int? durationMs;
    final tags = <String, String>{};
    var isLast = false;

    while (!isLast) {
      final header = await reader.read(4);
      if (header.length != 4) {
        break;
      }

      isLast = (header[0] & 0x80) != 0;
      final blockType = header[0] & 0x7f;
      final length = (header[1] << 16) | (header[2] << 8) | header[3];
      final block = await reader.read(length);
      if (block.length != length) {
        break;
      }

      if (blockType == 0 && block.length >= 34) {
        durationMs = _readStreamInfoDuration(block);
      } else if (blockType == 4) {
        tags.addAll(_readVorbisComments(block));
      }

      if (tags.isNotEmpty && durationMs != null) {
        break;
      }
    }

    return FlacMetadata(tags: tags, durationMs: durationMs);
  } finally {
    await reader.close();
  }
}

int? _readStreamInfoDuration(Uint8List block) {
  final packed = block
      .sublist(10, 18)
      .fold<int>(0, (value, byte) => (value << 8) | byte);
  final sampleRate = (packed >> 44) & 0xfffff;
  final totalSamples = packed & 0xfffffffff;
  if (sampleRate <= 0 || totalSamples <= 0) {
    return null;
  }
  return (totalSamples * 1000 / sampleRate).round();
}

Map<String, String> _readVorbisComments(Uint8List block) {
  final data = ByteData.sublistView(block);
  var offset = 0;

  int? readInt32() {
    if (offset + 4 > block.length) {
      return null;
    }
    final value = data.getUint32(offset, Endian.little);
    offset += 4;
    return value;
  }

  final vendorLength = readInt32();
  if (vendorLength == null || offset + vendorLength > block.length) {
    return {};
  }
  offset += vendorLength;

  final commentCount = readInt32();
  if (commentCount == null) {
    return {};
  }

  final comments = <String, String>{};
  for (var i = 0; i < commentCount; i++) {
    final length = readInt32();
    if (length == null || offset + length > block.length) {
      break;
    }
    final raw = utf8.decode(
      block.sublist(offset, offset + length),
      allowMalformed: true,
    );
    offset += length;

    final separator = raw.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    final key = raw.substring(0, separator).trim().toUpperCase();
    final value = raw.substring(separator + 1).trim();
    if (value.isNotEmpty && !comments.containsKey(key)) {
      comments[key] = value;
    }
  }

  return comments;
}
