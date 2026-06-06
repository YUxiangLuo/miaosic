import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/models.dart';

void main() {
  test('recognizes FLAC files as supported audio', () {
    expect(isAudioPath('/music/A/01. Track.flac'), isTrue);
    expect(isAudioPath('/music/A/cover.jpg'), isFalse);
  });

  test('collapses disc folders into the parent album folder', () {
    final file = File('/music/Artist - Album (2001)/Disc 1/01. Song.flac');

    expect(logicalFolderFor(file), '/music/Artist - Album (2001)');
  });
}
