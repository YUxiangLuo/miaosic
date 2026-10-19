import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:miaosic/audio_output_settings.dart';
import 'package:miaosic/models.dart' as music;
import 'package:miaosic/playback_controller.dart';
import 'package:miaosic/playback_session.dart';

import 'support/fake_platform_player.dart';

void main() {
  test(
    'playback controls do not create a session when none is selected',
    () async {
      final platform = FakePlatformPlayer();
      final controller = PlaybackController(
        player: Player(platformPlayer: platform),
      );
      addTearDown(controller.dispose);

      await controller.togglePlayPause();
      await controller.skip(1);
      await controller.skip(-1);

      expect(controller.session, isNull);
      expect(controller.playing, isFalse);
      expect(platform.openCount, 0);
      expect(platform.state.playing, isFalse);
    },
  );

  test(
    'completion follows the shuffled session and ends at the queue boundary',
    () async {
      final platform = FakePlatformPlayer();
      final controller = PlaybackController(
        player: Player(platformPlayer: platform),
      );
      addTearDown(controller.dispose);
      final first = _track('/music/first.flac');
      final second = _track('/music/second.flac');
      await controller.playSession(
        PlaybackSession.start(
          kind: music.LastPlaybackKind.favorites,
          tracks: [first, second],
          queue: [second, first],
          shuffled: true,
        ),
      );

      await controller.skip(-1);
      expect(platform.openCount, 1);
      platform.emitCompleted();
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentTrack?.path, first.path);
      expect(controller.session?.kind, music.LastPlaybackKind.favorites);
      expect(controller.session?.index, 1);
      expect(controller.session?.shuffled, isTrue);
      expect(platform.openCount, 2);

      platform.emitCompleted();
      await Future<void>.delayed(Duration.zero);
      expect(controller.currentTrack?.path, first.path);
      expect(platform.openCount, 2);

      await controller.skip(-1);
      expect(controller.currentTrack?.path, second.path);
      expect(controller.session?.index, 0);
    },
  );

  for (final playing in [true, false]) {
    test(
      'removing queued tracks preserves playback (playing: $playing)',
      () async {
        final platform = FakePlatformPlayer();
        final controller = PlaybackController(
          player: Player(platformPlayer: platform),
        );
        addTearDown(controller.dispose);
        final tracks = [
          _track('/music/third.flac'),
          _track('/music/first.flac'),
          _track('/music/fourth.flac'),
          _track('/music/second.flac'),
        ];
        final current = tracks[1];
        await controller.playSession(
          _albumSession(tracks, startTrack: current),
          play: playing,
        );
        platform.emitPlaybackState(
          playing: playing,
          position: const Duration(seconds: 30),
          duration: const Duration(minutes: 2),
        );
        await Future<void>.delayed(Duration.zero);

        await controller.reconcileLibrary(
          trackPaths: {current.path, tracks.last.path},
          favoritePaths: const {},
        );

        expect(controller.currentTrack, current);
        expect(controller.queue.map((track) => track.path), [
          current.path,
          tracks.last.path,
        ]);
        expect(controller.playing, playing);
        expect(controller.position, const Duration(seconds: 30));
        expect(controller.duration, const Duration(minutes: 2));
        expect(platform.openCount, 1);
        expect(platform.stopCount, 0);

        await controller.skip(1);
        expect(controller.currentTrack, tracks.last);
        await controller.skip(-1);
        expect(controller.currentTrack, current);
      },
    );
  }

  test(
    'removing the current track stops playback and clears the queue',
    () async {
      final platform = FakePlatformPlayer();
      final controller = PlaybackController(
        player: Player(platformPlayer: platform),
      );
      addTearDown(controller.dispose);
      final first = _track('/music/first.flac');
      final second = _track('/music/second.flac');
      await controller.playSession(_albumSession([first, second]));

      await controller.reconcileLibrary(
        trackPaths: {second.path},
        favoritePaths: const {},
      );
      await controller.skip(1);

      expect(controller.currentTrack, isNull);
      expect(controller.position, Duration.zero);
      expect(controller.duration, Duration.zero);
      expect(platform.openCount, 1);
      expect(platform.stopCount, 1);
    },
  );

  for (final removedIndex in [0, 1, 2]) {
    test(
      'a failed pending open cannot restore removed track $removedIndex',
      () async {
        final platform = FakePlatformPlayer();
        final controller = PlaybackController(
          player: Player(platformPlayer: platform),
        );
        addTearDown(controller.dispose);
        final tracks = [
          _track('/music/first.flac'),
          _track('/music/second.flac'),
          _track('/music/third.flac'),
        ];
        await controller.playSession(_albumSession(tracks));
        final blocker = Completer<void>();
        platform.blockNextOpen = blocker;
        platform.failBlockedOpen = true;
        final opening = controller.skip(2);
        await Future<void>.delayed(Duration.zero);

        await controller.reconcileLibrary(
          trackPaths: {
            for (final track in tracks)
              if (track.path != tracks[removedIndex].path) track.path,
          },
          favoritePaths: const {},
        );
        blocker.complete();
        await opening;

        if (removedIndex == 1) {
          expect(controller.currentTrack, tracks.first);
          expect(controller.queue.map((track) => track.path), [
            tracks.first.path,
            tracks.last.path,
          ]);
          expect(controller.playbackError, contains('open failed'));
        } else {
          expect(controller.currentTrack, isNull);
          expect(platform.stopCount, 1);
          await controller.skip(1);
          expect(platform.openCount, 2);
        }
      },
    );
  }

  for (final removeCurrent in [false, true]) {
    test(
      'failed album open preserves favorites changes (current: $removeCurrent)',
      () async {
        final platform = FakePlatformPlayer();
        final controller = PlaybackController(
          player: Player(platformPlayer: platform),
        );
        addTearDown(controller.dispose);
        final first = _track('/music/first.flac');
        final second = _track('/music/second.flac');
        final tracks = [first, second];
        await controller.playSession(
          PlaybackSession.start(
            kind: music.LastPlaybackKind.favorites,
            tracks: tracks,
          ),
        );
        final blocker = Completer<void>();
        platform.blockNextOpen = blocker;
        platform.failBlockedOpen = true;
        final opening = controller.playSession(
          PlaybackSession.start(
            kind: music.LastPlaybackKind.album,
            folderPath: '/music',
            tracks: tracks,
          ),
        );
        await controller.reconcileLibrary(
          trackPaths: tracks.map((track) => track.path).toSet(),
          favoritePaths: {removeCurrent ? second.path : first.path},
        );
        // The live album keeps both tracks; only the rollback favorites are pruned.
        expect(controller.queue.length, 2);
        expect(controller.session?.kind, music.LastPlaybackKind.album);
        blocker.complete();
        await opening;
        if (removeCurrent) {
          expect(controller.session, isNull);
          expect(platform.stopCount, 1);
        } else {
          expect(controller.session?.kind, music.LastPlaybackKind.favorites);
          expect(controller.queue.map((track) => track.path), [first.path]);
          expect(controller.currentTrack?.path, first.path);
        }
      },
    );
  }

  test(
    'restores the preferred device if it appears while applying settings',
    () async {
      final platform = FakePlatformPlayer();
      final controller = PlaybackController(
        player: Player(platformPlayer: platform),
      );
      addTearDown(controller.dispose);

      final blocker = Completer<void>();
      platform.blockNextDeviceSwitch = blocker;

      final apply = controller.applyAudioOutputSettings(
        const AudioOutputSettings(
          deviceName: 'pipewire/dac',
          deviceDescription: 'USB DAC',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(platform.selectedDevices.single.name, 'auto');

      platform.emitDevices(const [
        AudioDevice('auto', ''),
        AudioDevice('pipewire/dac', 'USB DAC'),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.preferredAudioOutputSettings.deviceName,
        'pipewire/dac',
      );

      blocker.complete();
      await apply;
      await platform.waitForDeviceSwitches();

      expect(platform.selectedDevices.first.name, 'auto');
      expect(platform.selectedDevices.last.name, 'pipewire/dac');
      expect(controller.audioOutputWarning, isNull);
      expect(controller.audioOutputError, isNull);
    },
  );

  test('applies an available preferred audio device', () async {
    final platform = FakePlatformPlayer(
      devices: const [
        AudioDevice('auto', ''),
        AudioDevice('pipewire/dac', 'USB DAC'),
      ],
    );
    final controller = PlaybackController(
      player: Player(platformPlayer: platform),
    );
    addTearDown(controller.dispose);

    await controller.applyAudioOutputSettings(
      const AudioOutputSettings(
        deviceName: 'pipewire/dac',
        deviceDescription: 'USB DAC',
      ),
    );

    expect(platform.selectedDevices.last.name, 'pipewire/dac');
    expect(controller.preferredAudioOutputSettings.deviceName, 'pipewire/dac');
    expect(controller.audioOutputWarning, isNull);
    expect(controller.audioOutputError, isNull);
  });

  test(
    'falls back to system default when preferred device is missing',
    () async {
      final platform = FakePlatformPlayer();
      final controller = PlaybackController(
        player: Player(platformPlayer: platform),
      );
      addTearDown(controller.dispose);

      await controller.applyAudioOutputSettings(
        const AudioOutputSettings(
          deviceName: 'pipewire/dac',
          deviceDescription: 'USB DAC',
        ),
      );

      expect(platform.selectedDevices.last.name, 'auto');
      expect(
        controller.preferredAudioOutputSettings.deviceName,
        'pipewire/dac',
      );
      expect(
        controller.audioOutputWarning,
        contains('not currently available'),
      );

      platform.emitDevices(const [
        AudioDevice('auto', ''),
        AudioDevice('pipewire/dac', 'USB DAC'),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(platform.selectedDevices.last.name, 'pipewire/dac');
      expect(controller.audioOutputWarning, isNull);
    },
  );

  test('clears restore errors after a later successful restore', () async {
    final platform = FakePlatformPlayer();
    final controller = PlaybackController(
      player: Player(platformPlayer: platform),
    );
    addTearDown(controller.dispose);

    await controller.applyAudioOutputSettings(
      const AudioOutputSettings(
        deviceName: 'pipewire/dac',
        deviceDescription: 'USB DAC',
      ),
    );
    expect(controller.audioOutputWarning, contains('not currently available'));

    platform.failNextDeviceSwitch = true;
    platform.emitDevices(const [
      AudioDevice('auto', ''),
      AudioDevice('pipewire/dac', 'USB DAC'),
    ]);
    await Future<void>.delayed(Duration.zero);
    await platform.waitForDeviceSwitches();
    await Future<void>.delayed(Duration.zero);

    expect(controller.audioOutputError, contains('switch failed'));

    platform.emitDevices(const [AudioDevice('auto', '')]);
    await Future<void>.delayed(Duration.zero);
    platform.emitDevices(const [
      AudioDevice('auto', ''),
      AudioDevice('pipewire/dac', 'USB DAC'),
    ]);
    await Future<void>.delayed(Duration.zero);
    await platform.waitForDeviceSwitches();
    await Future<void>.delayed(Duration.zero);

    expect(platform.selectedDevices.last.name, 'pipewire/dac');
    expect(controller.audioOutputWarning, isNull);
    expect(controller.audioOutputError, isNull);
  });

  test('keeps previous preferred device when switching fails', () async {
    final platform = FakePlatformPlayer(
      devices: const [
        AudioDevice('auto', ''),
        AudioDevice('pipewire/dac', 'USB DAC'),
      ],
    );
    final controller = PlaybackController(
      player: Player(platformPlayer: platform),
    );
    addTearDown(controller.dispose);

    platform.failNextDeviceSwitch = true;

    await expectLater(
      controller.applyAudioOutputSettings(
        const AudioOutputSettings(
          deviceName: 'pipewire/dac',
          deviceDescription: 'USB DAC',
        ),
      ),
      throwsStateError,
    );

    expect(
      controller.preferredAudioOutputSettings.deviceName,
      AudioOutputSettings.autoDeviceName,
    );
    expect(controller.audioOutputError, contains('switch failed'));
  });

  test(
    'rolls back the queue and exposes an error when opening fails',
    () async {
      final platform = FakePlatformPlayer();
      final controller = PlaybackController(
        player: Player(platformPlayer: platform),
      );
      addTearDown(controller.dispose);
      final first = _track('/music/first.flac');
      final second = _track('/music/second.flac');

      await controller.playSession(_albumSession([first]));
      platform.failNextOpen = true;
      await controller.playSession(_albumSession([second]));

      expect(controller.currentTrack?.path, first.path);
      expect(controller.queue.map((track) => track.path), [first.path]);
      expect(controller.playbackError, contains('second.flac'));
      expect(controller.playbackError, contains('open failed'));

      controller.clearPlaybackError();
      expect(controller.playbackError, isNull);
    },
  );

  test('ignores a late failure from a superseded open request', () async {
    final platform = FakePlatformPlayer();
    final controller = PlaybackController(
      player: Player(platformPlayer: platform),
    );
    addTearDown(controller.dispose);
    final first = _track('/music/first.flac');
    final second = _track('/music/second.flac');
    final third = _track('/music/third.flac');

    await controller.playSession(_albumSession([first]));

    final blockedOpen = Completer<void>();
    platform.blockNextOpen = blockedOpen;
    platform.failBlockedOpen = true;
    final supersededRequest = controller.playSession(_albumSession([second]));
    await Future<void>.delayed(Duration.zero);

    await controller.playSession(_albumSession([third]));
    blockedOpen.complete();
    await supersededRequest;

    expect(controller.currentTrack?.path, third.path);
    expect(controller.queue.map((track) => track.path), [third.path]);
    expect(controller.playbackError, isNull);
  });

  test('assigns a new revision to repeated playback failures', () async {
    final platform = FakePlatformPlayer();
    final controller = PlaybackController(
      player: Player(platformPlayer: platform),
    );
    addTearDown(controller.dispose);
    final track = _track('/music/first.flac');
    await controller.playSession(_albumSession([track]), play: false);
    platform.playFailuresRemaining = 2;

    await controller.togglePlayPause();
    final firstRevision = controller.playbackErrorRevision;
    final firstError = controller.playbackError;

    await controller.togglePlayPause();

    expect(controller.playbackError, firstError);
    expect(controller.playbackErrorRevision, firstRevision + 1);
  });

  test('surfaces asynchronous backend playback errors', () async {
    final platform = FakePlatformPlayer();
    final controller = PlaybackController(
      player: Player(platformPlayer: platform),
    );
    addTearDown(controller.dispose);

    platform.emitError('decoder failed');
    await Future<void>.delayed(Duration.zero);

    expect(controller.playbackError, 'Playback error: decoder failed');
  });
}

PlaybackSession _albumSession(
  List<music.Track> tracks, {
  music.Track? startTrack,
}) => PlaybackSession.start(
  kind: music.LastPlaybackKind.album,
  folderPath: tracks.first.folderPath,
  tracks: tracks,
  startTrack: startTrack,
);

music.Track _track(String path) {
  return music.Track(
    path: path,
    folderPath: '/music',
    title: path.split('/').last,
    artist: 'Artist',
    album: 'Album',
    albumArtist: 'Artist',
    trackNumber: 1,
    discNumber: null,
    year: 2026,
    durationMs: 120000,
    sizeBytes: 42,
    modifiedMs: 99,
    coverArtPath: null,
  );
}
