import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:miaosic/album_playback_view.dart';
import 'package:miaosic/album_views.dart';
import 'package:miaosic/favorite_views.dart';
import 'package:miaosic/favorites_playback_view.dart';
import 'package:miaosic/library_controller.dart';
import 'package:miaosic/library_screen.dart';
import 'package:miaosic/library_sidebar.dart';
import 'package:miaosic/models.dart';
import 'package:miaosic/playback_controller.dart';
import 'package:miaosic/playback_session.dart';
import 'package:miaosic/playlist_playback_view.dart';
import 'package:miaosic/playlist_views.dart';

import 'support/fake_platform_player.dart';
import 'support/library_test_store.dart';

void main() {
  testWidgets(
    'browse tabs retain scroll, restore focus, and show library updates',
    (tester) async {
      final albums = [
        for (var i = 0; i < 24; i++)
          _albumSummary('/music/album-$i', 'Album $i'),
      ];
      final folders = [
        for (var i = 0; i < 8; i++) _playlistFolder('/music/mix-$i', 'Mix $i'),
      ];
      final tracks = [
        for (final album in albums)
          _track(
            '${album.folderPath}/song.flac',
            folderPath: album.folderPath,
            title: album.title,
            album: album.title,
            artist: 'Artist',
          ),
        for (final folder in folders)
          _track(
            '${folder.path}/song.flac',
            folderPath: folder.path,
            title: folder.name,
            album: folder.name,
            artist: 'Artist',
          ),
      ];
      final library = _InjectedLibraryController(
        albums: albums,
        folders: folders,
        tracks: tracks,
        favoriteTracks: tracks,
      );
      final playback = _InjectedPlaybackController();
      await _pumpLibraryScreen(
        tester,
        library: library,
        playback: playback,
        now: DateTime.now,
      );
      await tester.pumpAndSettle();
      final albumScroll = tester
          .widget<AlbumGrid>(find.byType(AlbumGrid))
          .scrollController;
      albumScroll.jumpTo(180);
      await tester.pump();

      await tester.tap(find.widgetWithText(InkWell, 'Playlists'));
      await tester.pumpAndSettle();
      final playlistScroll = tester
          .widget<PlaylistList>(find.byType(PlaylistList))
          .scrollController;
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      final playlistOffset = playlistScroll.offset;
      expect(playlistOffset, greaterThan(0));
      expect(albumScroll.offset, closeTo(180, 0.1));

      await tester.tap(find.widgetWithText(InkWell, 'Favorites'));
      await tester.pumpAndSettle();
      final favoritesScroll = tester
          .widget<FavoriteBrowseList>(find.byType(FavoriteBrowseList))
          .scrollController!;
      favoritesScroll.jumpTo(120);
      await tester.pump();

      await tester.tap(find.widgetWithText(InkWell, 'Albums'));
      await tester.pumpAndSettle();
      expect(albumScroll.offset, closeTo(180, 0.1));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(albumScroll.offset, greaterThan(180));
      expect(playlistScroll.offset, closeTo(playlistOffset, 0.1));
      final albumOffset = albumScroll.offset;

      // Update favorites while their browse page is hidden.
      await library.toggleFavoriteTrack(tracks.first);
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, 'Favorites'));
      await tester.pumpAndSettle();
      expect(favoritesScroll.offset, closeTo(120, 0.1));
      expect(find.text('31 favorite tracks'), findsOneWidget);

      await tester.tap(find.widgetWithText(InkWell, 'Playlists'));
      await tester.pumpAndSettle();
      expect(playlistScroll.offset, closeTo(playlistOffset, 0.1));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(playlistScroll.offset, greaterThan(playlistOffset));
      expect(albumScroll.offset, closeTo(albumOffset, 0.1));
      expect(playback.session, isNull);
      await _disposeLibraryScreen(tester, library, playback);
    },
  );

  for (final sameQueue in [false, true]) {
    testWidgets(
      'pending unfavorite cannot alter a new album (same queue: $sameQueue)',
      (tester) async {
        final fixture = _LibraryFixture.album();
        final favorites = sameQueue ? fixture.tracks : _favoriteTracks(2);
        final library = _InjectedLibraryController(
          tracks: sameQueue
              ? fixture.tracks
              : [...fixture.tracks, ...favorites],
          albums: [fixture.album],
          favoriteTracks: favorites,
          lastPlaybackState: LastPlaybackState(
            kind: LastPlaybackKind.favorites,
            folderPath: '',
            trackPath: favorites.first.path,
            playing: true,
            shuffled: false,
          ),
          canRestorePlayback: true,
        );
        final playback = _InjectedPlaybackController();
        await _pumpLibraryScreen(
          tester,
          library: library,
          playback: playback,
          now: DateTime.now,
        );
        await tester.pump();
        final blocker = Completer<void>();
        library.favoriteBlocker = blocker;
        tester
            .widget<FavoritesPlaybackView>(find.byType(FavoritesPlaybackView))
            .onToggleFavorite(favorites.last);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.tap(find.widgetWithText(InkWell, 'Albums'));
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: find.byType(AlbumGrid),
            matching: find.byType(InkWell),
          ),
        );
        await tester.pump();
        await tester.tap(find.byTooltip('Play'));
        await tester.pump();
        expect(playback.currentTrack?.path, fixture.tracks.first.path);

        blocker.complete();
        await tester.pump();
        expect(playback.currentTrack?.path, fixture.tracks.first.path);
        expect(playback.playing, isTrue);
        expect(
          playback.queue.map((track) => track.path),
          fixture.tracks.map((track) => track.path),
        );
        expect(playback.stopIfCurrentRemovedCount, 0);
        expect(
          library.favoriteTrackPaths,
          isNot(contains(favorites.last.path)),
        );
        await _disposeLibraryScreen(tester, library, playback);
      },
    );
  }

  testWidgets('pending unfavorite preserves concurrent rescan removals', (
    tester,
  ) async {
    final tracks = _favoriteTracks(3);
    final library = _InjectedLibraryController(
      tracks: tracks,
      favoriteTracks: tracks,
      lastPlaybackState: LastPlaybackState(
        kind: LastPlaybackKind.favorites,
        folderPath: '',
        trackPath: tracks.first.path,
        playing: true,
        shuffled: false,
      ),
      canRestorePlayback: true,
    );
    final playback = _InjectedPlaybackController();
    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: DateTime.now,
    );
    await tester.pump();
    final blocker = Completer<void>();
    library.favoriteBlocker = blocker;
    tester
        .widget<FavoritesPlaybackView>(find.byType(FavoritesPlaybackView))
        .onToggleFavorite(tracks[1]);
    await tester.pump();
    await library.prepareRescan(tracks.take(2).toList());
    await library.applyPendingDiff(confirmLargeDeletion: (_) async => true);
    blocker.complete();
    await tester.pump();
    expect(playback.currentQueueForTest.map((track) => track.path), [
      tracks.first.path,
    ]);
    expect(playback.currentTrack?.path, tracks.first.path);
    expect(playback.playing, isTrue);
    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets(
    'favorite write failure is visible and does not block the next change',
    (tester) async {
      final fixture = _LibraryFixture.album();
      final library = _InjectedLibraryController(
        tracks: fixture.tracks,
        albums: [fixture.album],
      );
      final playback = _InjectedPlaybackController();
      await _pumpLibraryScreen(
        tester,
        library: library,
        playback: playback,
        now: DateTime.now,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlbumGrid),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pump();
      library.favoriteError = StateError('disk full');
      await tester.tap(find.byTooltip('Add to favorites'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Could not update favorite:'), findsOneWidget);
      expect(library.favoriteTrackPaths, isEmpty);
      library.favoriteError = null;
      await tester.tap(find.byTooltip('Add to favorites'));
      await tester.pump();
      expect(library.favoriteTrackPaths, contains(fixture.tracks.first.path));
      await _disposeLibraryScreen(tester, library, playback);
    },
  );

  testWidgets('failed playback save can retry the same state', (tester) async {
    final fixture = _LibraryFixture.album();
    final library = _InjectedLibraryController(
      tracks: fixture.tracks,
      albums: [fixture.album],
    );
    final playback = _InjectedPlaybackController();
    var attempts = 0;
    LastPlaybackState? saved;
    var failSave = true;
    library.onSaveLastPlayback = (state) async {
      attempts += 1;
      if (failSave) {
        throw StateError('disk full');
      }
      saved = state;
    };
    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: DateTime.now,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlbumGrid),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pump();
    tester
        .widget<AlbumPlaybackView>(find.byType(AlbumPlaybackView))
        .onPlayTrack(fixture.tracks.first);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Could not save playback:'), findsOneWidget);
    expect(saved, isNull);

    final failedAttempts = attempts;
    failSave = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(attempts, failedAttempts + 1);
    expect(saved?.trackPath, fixture.tracks.first.path);
    tester
        .widget<AlbumPlaybackView>(find.byType(AlbumPlaybackView))
        .onPlayTrack(fixture.tracks.first);
    await tester.pump();
    expect(attempts, failedAttempts + 1);
    await _disposeLibraryScreen(tester, library, playback);
  });

  for (final returnToFirst in [false, true]) {
    testWidgets(
      'playback saves retain the latest pending state (return: $returnToFirst)',
      (tester) async {
        final tracks = _favoriteTracks(2);
        final album = _albumSummary(tracks.first.folderPath, 'Favorites');
        final library = _InjectedLibraryController(
          tracks: tracks,
          albums: [album],
        );
        final playback = _InjectedPlaybackController();
        final blocker = Completer<void>();
        final saved = <LastPlaybackState>[];
        var attempts = 0;
        library.onSaveLastPlayback = (state) async {
          attempts += 1;
          if (attempts == 1) {
            await blocker.future;
          }
          saved.add(state);
        };
        await _pumpLibraryScreen(
          tester,
          library: library,
          playback: playback,
          now: DateTime.now,
        );
        await tester.tap(
          find.descendant(
            of: find.byType(AlbumGrid),
            matching: find.byType(InkWell),
          ),
        );
        await tester.pump();
        void play(Track track) => tester
            .widget<AlbumPlaybackView>(find.byType(AlbumPlaybackView))
            .onPlayTrack(track);
        play(tracks.first);
        await tester.pump();
        play(tracks.last);
        await tester.pump();
        if (returnToFirst) {
          play(tracks.first);
          await tester.pump();
        }
        expect(attempts, 1);
        blocker.complete();
        await tester.pump();
        expect(saved.map((state) => state.trackPath), [
          tracks.first.path,
          returnToFirst ? tracks.first.path : tracks.last.path,
        ]);
        // Opening first publishes the queue, then the backend playing event.
        // Coalescing must preserve that final state even when the track repeats.
        expect(saved.first.playing, isFalse);
        expect(saved.last.playing, isTrue);
        await _disposeLibraryScreen(tester, library, playback);
      },
    );
  }

  for (final kind in LastPlaybackKind.values) {
    testWidgets('applying a rescan prunes the active ${kind.name} queue', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tracks = _favoriteTracks(4);
      final folderPath = tracks.first.folderPath;
      final album = _albumSummary(folderPath, 'Favorites');
      final folder = _playlistFolder(folderPath, 'Favorites');
      final current = tracks[1];
      var now = DateTime(2026);
      final library = _InjectedLibraryController(
        tracks: tracks,
        albums: kind == LastPlaybackKind.album ? [album] : [],
        folders: kind == LastPlaybackKind.playlist ? [folder] : [],
        favoriteTracks: kind == LastPlaybackKind.favorites ? tracks : [],
        lastPlaybackState: LastPlaybackState(
          kind: kind,
          folderPath: kind == LastPlaybackKind.favorites ? '' : folderPath,
          trackPath: current.path,
          playing: true,
          shuffled: kind != LastPlaybackKind.album,
        ),
        canRestorePlayback: true,
      );
      final playback = _InjectedPlaybackController();
      await _pumpLibraryScreen(
        tester,
        library: library,
        playback: playback,
        now: () => now,
      );
      await tester.pump();
      final originalQueue = List<Track>.of(playback.currentQueueForTest);
      final removed = originalQueue.lastWhere(
        (track) => track.path != current.path,
      );
      final remaining = tracks
          .where((track) => track.path != removed.path)
          .toList();
      await library.prepareRescan(remaining);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.tap(find.byTooltip('Library settings'));
      await _pumpDialogTransition(tester);
      await tester.tap(find.text('Apply'));
      await _pumpDialogTransition(tester);
      if (kind == LastPlaybackKind.favorites) {
        await tester.tap(find.text('Cancel'));
        await _pumpDialogTransition(tester);
        expect(playback.currentQueueForTest, originalQueue);
        await tester.tap(find.text('Apply'));
        await _pumpDialogTransition(tester);
      }
      await tester.tap(find.text('Apply anyway'));
      await _pumpDialogTransition(tester);

      expect(playback.currentTrack?.path, current.path);
      expect(playback.playing, isTrue);
      expect(playback.platform.openCount, 1);
      expect(playback.stopIfCurrentRemovedCount, 0);
      expect(
        playback.currentQueueForTest,
        originalQueue.where((track) => track.path != removed.path).toList(),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      now = now.add(const Duration(seconds: 31));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      final view = switch (kind) {
        LastPlaybackKind.album => find.byType(AlbumPlaybackView),
        LastPlaybackKind.playlist => find.byType(PlaylistPlaybackView),
        LastPlaybackKind.favorites => find.byType(FavoritesPlaybackView),
      };
      expect(view, findsOneWidget);
      expect(find.byTooltip('Pause'), findsWidgets);
      expect(find.text(removed.title), findsNothing);

      await _disposeLibraryScreen(tester, library, playback);
    });
  }

  testWidgets('injected controllers are not disposed by LibraryScreen', (
    tester,
  ) async {
    final library = _InjectedLibraryController();
    final playback = _InjectedPlaybackController();
    ThemeMode? requestedThemeMode;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          themeMode: ThemeMode.light,
          onThemeModeChanged: (mode) => requestedThemeMode = mode,
          libraryController: library,
          playbackController: playback,
        ),
      ),
    );
    await tester.pump();

    expect(library.opened, isTrue);
    await tester.tap(find.byTooltip('Switch to dark mode'));
    await tester.pump();

    expect(requestedThemeMode, ThemeMode.dark);
    expect(library.savedThemeMode, 'dark');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(library.disposedByScreen, isFalse);
    expect(playback.disposedByScreen, isFalse);

    playback.disposeForTest();
    library.disposeForTest();
  });

  testWidgets('rolls theme back when saving the preference fails', (
    tester,
  ) async {
    final library = _InjectedLibraryController(themeSaveError: 'disk full');
    final playback = _InjectedPlaybackController();
    var themeMode = ThemeMode.light;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return LibraryScreen(
              themeMode: themeMode,
              onThemeModeChanged: (mode) => setState(() => themeMode = mode),
              libraryController: library,
              playbackController: playback,
            );
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Switch to dark mode'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(themeMode, ThemeMode.light);
    expect(find.textContaining('Could not save theme'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    playback.disposeForTest();
    library.disposeForTest();
  });

  testWidgets(
    'music root dialog keeps its text controller alive until submit',
    (tester) async {
      final library = _InjectedLibraryController(canEditMusicRoot: true);
      final playback = _InjectedPlaybackController();

      await tester.pumpWidget(
        MaterialApp(
          home: LibraryScreen(
            themeMode: ThemeMode.light,
            onThemeModeChanged: (_) {},
            libraryController: library,
            playbackController: playback,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Library settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Change music folder'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, '/music');

      await tester.enterText(find.byType(TextField), '/next/music');
      await tester.tap(find.text('Save and rescan'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(library.changedMusicRoot, '/next/music');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      playback.disposeForTest();
      library.disposeForTest();
    },
  );

  testWidgets('does not auto-open now playing before thirty seconds', (
    tester,
  ) async {
    final fixture = _LibraryFixture.album();
    var now = DateTime(2026);
    final library = _InjectedLibraryController(
      tracks: fixture.tracks,
      albums: [fixture.album],
    );
    final playback = _InjectedPlaybackController(
      currentTrack: fixture.tracks.first,
      playing: true,
      currentQueue: fixture.tracks,
    );

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: () => now,
    );

    expect(find.byType(AlbumPlaybackView), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now = now.add(const Duration(seconds: 29));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.byType(AlbumPlaybackView), findsNothing);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets('auto-opens album now playing after thirty seconds away', (
    tester,
  ) async {
    final fixture = _LibraryFixture.album();
    var now = DateTime(2026);
    final library = _InjectedLibraryController(
      tracks: fixture.tracks,
      albums: [fixture.album],
    );
    final playback = _InjectedPlaybackController(
      currentTrack: fixture.tracks.first,
      playing: true,
      currentQueue: fixture.tracks,
    );

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: () => now,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now = now.add(const Duration(seconds: 31));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.byType(AlbumPlaybackView), findsOneWidget);

    final hiddenSidebar = find.byType(LibrarySidebar, skipOffstage: false);
    expect(hiddenSidebar, findsOneWidget);
    expect(find.byType(LibrarySidebar), findsNothing);
    expect(TickerMode.valuesOf(tester.element(hiddenSidebar)).enabled, isFalse);
    expect(
      TickerMode.valuesOf(
        tester.element(find.byType(AlbumPlaybackView)),
      ).enabled,
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(LibrarySidebar), findsOneWidget);
    expect(TickerMode.valuesOf(tester.element(hiddenSidebar)).enabled, isTrue);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets('auto-opens playlist now playing after thirty seconds away', (
    tester,
  ) async {
    final folder = FolderSummary(
      path: '/music/mix',
      name: 'Road Mix',
      kind: FolderKind.playlist,
      confidence: 0.8,
      trackCount: 1,
      albumCount: 2,
      albumArtistCount: 2,
      artistCount: 2,
      yearCount: 2,
      coverArtPath: null,
    );
    final tracks = [
      _track(
        '/music/mix/01.flac',
        folderPath: folder.path,
        title: 'Mix Track',
        album: 'Other',
        artist: 'Artist',
      ),
    ];
    var now = DateTime(2026);
    final library = _InjectedLibraryController(
      tracks: tracks,
      folders: [folder],
    );
    final playback = _InjectedPlaybackController();

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: () => now,
    );

    await tester.tap(find.widgetWithText(InkWell, 'Playlists'));
    await tester.pump();
    await tester.tap(find.text('Road Mix'));
    await tester.pump();
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(PlaylistPlaybackView), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now = now.add(const Duration(seconds: 31));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.byType(PlaylistPlaybackView), findsOneWidget);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets('playlist overlay switches to the neighboring playlist', (
    tester,
  ) async {
    final first = _playlistFolder('/music/mix-a', 'Road Mix');
    final second = _playlistFolder('/music/mix-b', 'Night Mix');
    final firstTracks = [
      _track(
        '/music/mix-a/01.flac',
        folderPath: first.path,
        title: 'Road Track',
        album: 'A',
        artist: 'Artist',
      ),
    ];
    final secondTracks = [
      _track(
        '/music/mix-b/01.flac',
        folderPath: second.path,
        title: 'Night Track',
        album: 'B',
        artist: 'Artist',
      ),
    ];
    final library = _InjectedLibraryController(
      tracks: [...firstTracks, ...secondTracks],
      folders: [first, second],
    );
    final playback = _InjectedPlaybackController();

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: DateTime.now,
    );

    await tester.tap(find.widgetWithText(InkWell, 'Playlists'));
    await tester.pump();
    await tester.tap(find.text('Road Mix'));
    await tester.pump();
    expect(
      tester
          .widget<PlaylistPlaybackView>(find.byType(PlaylistPlaybackView))
          .folder
          .path,
      first.path,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(
      tester
          .widget<PlaylistPlaybackView>(find.byType(PlaylistPlaybackView))
          .folder
          .path,
      second.path,
    );
    expect(find.text('Night Mix'), findsWidgets);
    expect(playback.currentTrack, isNull);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets(
    'thirty seconds away returns from favorites overlay to album overlay',
    (tester) async {
      final fixture = _LibraryFixture.album();
      final favorites = _favoriteTracks(1);
      var now = DateTime(2026);
      final library = _InjectedLibraryController(
        tracks: [...fixture.tracks, ...favorites],
        albums: [fixture.album],
        favoriteTracks: favorites,
      );
      final playback = _InjectedPlaybackController(
        currentTrack: fixture.tracks.first,
        playing: true,
        currentQueue: fixture.tracks,
      );

      await _pumpLibraryScreen(
        tester,
        library: library,
        playback: playback,
        now: () => now,
      );

      await tester.tap(find.widgetWithText(InkWell, 'Favorites'));
      await tester.pump();
      expect(find.byType(FavoriteBrowseList), findsOneWidget);
      expect(find.byType(FavoritesPlaybackView), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      now = now.add(const Duration(seconds: 31));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.byType(AlbumPlaybackView), findsOneWidget);
      expect(find.byType(FavoritesPlaybackView), findsNothing);

      await _disposeLibraryScreen(tester, library, playback);
    },
  );

  testWidgets('does not auto-open now playing while playback is paused', (
    tester,
  ) async {
    final fixture = _LibraryFixture.album();
    var now = DateTime(2026);
    final library = _InjectedLibraryController(
      tracks: fixture.tracks,
      albums: [fixture.album],
    );
    final playback = _InjectedPlaybackController(
      currentTrack: fixture.tracks.first,
      playing: false,
      currentQueue: fixture.tracks,
    );

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: () => now,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now = now.add(const Duration(seconds: 31));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.byType(AlbumPlaybackView), findsNothing);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets('skips auto-open now playing while settings dialog is open', (
    tester,
  ) async {
    final fixture = _LibraryFixture.album();
    var now = DateTime(2026);
    final library = _InjectedLibraryController(
      tracks: fixture.tracks,
      albums: [fixture.album],
    );
    final playback = _InjectedPlaybackController(
      currentTrack: fixture.tracks.first,
      playing: true,
      currentQueue: fixture.tracks,
    );

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: () => now,
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now = now.add(const Duration(seconds: 31));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(AlbumPlaybackView), findsNothing);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets('favorites now playing returns to Favorites and space pauses', (
    tester,
  ) async {
    final fixture = _LibraryFixture.album();
    var now = DateTime(2026);
    final library = _InjectedLibraryController(
      tracks: fixture.tracks,
      favoriteTracks: fixture.tracks,
    );
    final playback = _InjectedPlaybackController(
      kind: LastPlaybackKind.favorites,
      currentTrack: fixture.tracks.first,
      playing: true,
      currentQueue: fixture.tracks,
    );

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: () => now,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now = now.add(const Duration(seconds: 31));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.byType(FavoritesPlaybackView), findsOneWidget);
    expect(find.text('1 favorite track'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(playback.toggleCount, 1);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets('favorites now playing preserves shuffled queue when returning', (
    tester,
  ) async {
    final favoriteTracks = _favoriteTracks(8);
    var now = DateTime(2026);
    final library = _InjectedLibraryController(
      tracks: favoriteTracks,
      favoriteTracks: favoriteTracks,
    );
    final playback = _InjectedPlaybackController();

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: () => now,
    );

    await tester.tap(find.widgetWithText(InkWell, 'Favorites'));
    await tester.pump();
    expect(find.byType(FavoriteBrowseList), findsOneWidget);
    expect(find.text('Favorite 1'), findsOneWidget);
    await tester.tap(
      find.byKey(Key('favorite-play-${favoriteTracks.first.path}')),
    );
    await tester.pump();
    expect(find.byType(FavoritesPlaybackView), findsOneWidget);
    for (var attempt = 0; attempt < 20; attempt += 1) {
      await tester.tap(find.byTooltip('Shuffle favorites'));
      await tester.pump();
      if (!_sameTrackOrder(playback.currentQueueForTest, favoriteTracks)) {
        break;
      }
    }
    expect(playback.currentQueueForTest, isNotEmpty);
    expect(
      _sameTrackOrder(playback.currentQueueForTest, favoriteTracks),
      false,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(FavoritesPlaybackView), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now = now.add(const Duration(seconds: 31));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.byType(FavoritesPlaybackView), findsOneWidget);
    expect(find.text('${favoriteTracks.length} favorite tracks'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(playback.toggleCount, 1);
    expect(
      _sameTrackOrder(playback.currentQueueForTest, favoriteTracks),
      isFalse,
    );

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets('restores persisted favorites playback', (tester) async {
    final favoriteTracks = _favoriteTracks(3);
    final library = _InjectedLibraryController(
      tracks: favoriteTracks,
      favoriteTracks: favoriteTracks,
      lastPlaybackState: LastPlaybackState(
        kind: LastPlaybackKind.favorites,
        folderPath: '',
        trackPath: favoriteTracks[1].path,
        playing: false,
        shuffled: false,
      ),
      canRestorePlayback: true,
    );
    final playback = _InjectedPlaybackController();

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: DateTime.now,
    );
    await tester.pump();

    expect(playback.platform.openCount, 1);
    expect(playback.currentTrack?.path, favoriteTracks[1].path);
    expect(
      playback.currentQueueForTest.map((track) => track.path),
      favoriteTracks.map((track) => track.path),
    );
    // The saved state was paused, but Miaosic always plays on launch.
    expect(playback.playing, isTrue);
    expect(find.byType(FavoritesPlaybackView), findsOneWidget);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets('plays a saved album on launch even when it was paused', (
    tester,
  ) async {
    final album = _albumSummary('/music/A/Album A', 'Album A');
    final track = _track(
      '${album.folderPath}/01.flac',
      folderPath: album.folderPath,
      title: album.title,
      album: album.title,
      artist: album.albumArtist,
    );
    final library = _InjectedLibraryController(
      tracks: [track],
      albums: [album],
      lastPlaybackState: LastPlaybackState(
        kind: LastPlaybackKind.album,
        folderPath: album.folderPath,
        trackPath: track.path,
        playing: false,
        shuffled: false,
      ),
      canRestorePlayback: true,
    );
    final playback = _InjectedPlaybackController();

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: DateTime.now,
    );
    await tester.pump();

    expect(playback.platform.openCount, 1);
    expect(playback.currentTrack?.path, track.path);
    expect(playback.playing, isTrue);
    expect(find.byType(AlbumPlaybackView), findsOneWidget);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets('does not play when there is no saved playback state', (
    tester,
  ) async {
    final album = _albumSummary('/music/A/Album A', 'Album A');
    final track = _track(
      '${album.folderPath}/01.flac',
      folderPath: album.folderPath,
      title: album.title,
      album: album.title,
      artist: album.albumArtist,
    );
    final library = _InjectedLibraryController(
      tracks: [track],
      albums: [album],
      canRestorePlayback: true,
    );
    final playback = _InjectedPlaybackController();

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: DateTime.now,
    );
    await tester.pump();

    expect(playback.currentTrack, isNull);
    expect(playback.playing, isFalse);
    expect(find.byType(AlbumPlaybackView), findsNothing);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets(
    'favorites sidebar hydrates same-queue now playing without restarting',
    (tester) async {
      final favoriteTracks = _favoriteTracks(3);
      final library = _InjectedLibraryController(
        tracks: favoriteTracks,
        favoriteTracks: favoriteTracks,
      );
      final playback = _InjectedPlaybackController(
        kind: LastPlaybackKind.favorites,
        currentTrack: favoriteTracks[1],
        playing: true,
        currentQueue: favoriteTracks,
      );

      await _pumpLibraryScreen(
        tester,
        library: library,
        playback: playback,
        now: DateTime.now,
      );

      await tester.tap(find.widgetWithText(InkWell, 'Favorites'));
      await tester.pump();
      expect(find.byType(FavoritesPlaybackView), findsNothing);
      expect(find.byType(FavoriteBrowseList), findsOneWidget);

      expect(find.text('Favorite 2'), findsOneWidget);
      await tester.tap(
        find.byKey(Key('favorite-play-${favoriteTracks[1].path}')),
      );
      await tester.pump();

      expect(find.byType(FavoritesPlaybackView), findsOneWidget);
      expect(find.byTooltip('Pause'), findsWidgets);
      expect(playback.currentTrack?.path, favoriteTracks[1].path);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(playback.toggleCount, 1);
      expect(playback.playing, isFalse);
      expect(playback.currentTrack?.path, favoriteTracks[1].path);
      expect(
        playback.currentQueueForTest.map((track) => track.path),
        favoriteTracks.map((track) => track.path),
      );

      await _disposeLibraryScreen(tester, library, playback);
    },
  );

  testWidgets('thirty seconds hydrates an inactive favorites overlay', (
    tester,
  ) async {
    final favoriteTracks = _favoriteTracks(3);
    var now = DateTime(2026);
    final library = _InjectedLibraryController(
      tracks: favoriteTracks,
      favoriteTracks: favoriteTracks,
    );
    final playback = _InjectedPlaybackController();

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: () => now,
    );

    await tester.tap(find.widgetWithText(InkWell, 'Favorites'));
    await tester.pump();
    expect(find.byType(FavoriteBrowseList), findsOneWidget);
    expect(find.byType(FavoritesPlaybackView), findsNothing);
    expect(playback.currentTrack, isNull);

    await playback.playSession(
      PlaybackSession.start(
        kind: LastPlaybackKind.favorites,
        tracks: favoriteTracks,
        startTrack: favoriteTracks[1],
      ),
    );
    await tester.pump();
    expect(find.byTooltip('Pause'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now = now.add(const Duration(seconds: 31));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.byType(FavoritesPlaybackView), findsOneWidget);
    expect(find.byTooltip('Pause'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(playback.toggleCount, 1);
    expect(playback.currentTrack?.path, favoriteTracks[1].path);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets('favorites sidebar opens the browse list without playing', (
    tester,
  ) async {
    final favoriteTracks = _favoriteTracks(2);
    final library = _InjectedLibraryController(
      tracks: favoriteTracks,
      favoriteTracks: favoriteTracks,
    );
    final playback = _InjectedPlaybackController();

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: DateTime.now,
    );

    await tester.tap(find.widgetWithText(InkWell, 'Favorites'));
    await tester.pump();

    expect(find.byType(FavoriteBrowseList), findsOneWidget);
    expect(find.byType(FavoritesPlaybackView), findsNothing);
    expect(find.byTooltip('Play favorite'), findsNWidgets(2));
    expect(find.byTooltip('Shuffle favorites'), findsNothing);
    expect(playback.currentTrack, isNull);
    expect(playback.playing, isFalse);

    await tester.tap(find.text('Favorite 2'));
    await tester.pump(kDoubleTapTimeout);
    expect(find.byType(FavoritesPlaybackView), findsNothing);
    expect(playback.currentTrack, isNull);

    await tester.tap(
      find.byKey(Key('favorite-play-${favoriteTracks[1].path}')),
    );
    await tester.pump();
    expect(find.byType(FavoritesPlaybackView), findsOneWidget);
    expect(playback.currentTrack?.path, favoriteTracks[1].path);
    expect(playback.playing, isTrue);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets(
    'closing a fully favorited album still returns to the album overlay',
    (tester) async {
      final fixture = _LibraryFixture.album();
      var now = DateTime(2026);
      final library = _InjectedLibraryController(
        tracks: fixture.tracks,
        albums: [fixture.album],
        favoriteTracks: fixture.tracks,
      );
      final playback = _InjectedPlaybackController();

      await _pumpLibraryScreen(
        tester,
        library: library,
        playback: playback,
        now: () => now,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(AlbumGrid),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Play'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(AlbumPlaybackView), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      now = now.add(const Duration(seconds: 31));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.byType(AlbumPlaybackView), findsOneWidget);
      expect(find.byType(FavoritesPlaybackView), findsNothing);

      await _disposeLibraryScreen(tester, library, playback);
    },
  );

  testWidgets('album overlay can jump back to a playing playlist', (
    tester,
  ) async {
    final fixture = _LibraryFixture.album();
    final folder = _playlistFolder('/music/mix', 'Road Mix');
    final playlistTracks = [
      _track(
        '/music/mix/01.flac',
        folderPath: folder.path,
        title: 'Mix Track',
        album: 'Other',
        artist: 'Artist',
      ),
    ];
    final library = _InjectedLibraryController(
      tracks: [...fixture.tracks, ...playlistTracks],
      albums: [fixture.album],
      folders: [folder],
    );
    final playback = _InjectedPlaybackController();

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: DateTime.now,
    );

    await tester.tap(find.widgetWithText(InkWell, 'Playlists'));
    await tester.pump();
    await tester.tap(find.text('Road Mix'));
    await tester.pump();
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    await tester.tap(find.widgetWithText(InkWell, 'Albums'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(AlbumGrid),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pump();

    expect(find.byType(AlbumPlaybackView), findsOneWidget);
    expect(find.byTooltip('Back to now playing'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to now playing'));
    await tester.pump();

    expect(find.byType(PlaylistPlaybackView), findsOneWidget);
    expect(playback.currentTrack?.path, playlistTracks.first.path);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets('unfavoriting the current track stops playback', (tester) async {
    final favoriteTracks = _favoriteTracks(2);
    final library = _InjectedLibraryController(
      tracks: favoriteTracks,
      favoriteTracks: favoriteTracks,
    );
    final playback = _InjectedPlaybackController(
      kind: LastPlaybackKind.favorites,
      currentTrack: favoriteTracks.first,
      playing: true,
      currentQueue: favoriteTracks,
    );

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: DateTime.now,
    );

    await tester.tap(find.widgetWithText(InkWell, 'Favorites'));
    await tester.pump();
    await tester.tap(
      find.byKey(Key('favorite-play-${favoriteTracks.first.path}')),
    );
    await tester.pump();
    await tester.tap(
      find
          .descendant(
            of: find.byType(FavoritesPlaybackView),
            matching: find.byTooltip('Remove from favorites'),
          )
          .first,
    );
    await tester.pump();

    expect(playback.stopIfCurrentRemovedCount, 1);
    expect(playback.currentTrack, isNull);
    expect(playback.playing, isFalse);
    expect(find.byType(FavoritesPlaybackView), findsOneWidget);
    expect(find.text('1 favorite track'), findsWidgets);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets('unfavoriting the last favorite stops playback', (tester) async {
    final favoriteTracks = _favoriteTracks(1);
    final library = _InjectedLibraryController(
      tracks: favoriteTracks,
      favoriteTracks: favoriteTracks,
    );
    final playback = _InjectedPlaybackController(
      kind: LastPlaybackKind.favorites,
      currentTrack: favoriteTracks.single,
      playing: true,
      currentQueue: favoriteTracks,
    );

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: DateTime.now,
    );

    await tester.tap(find.widgetWithText(InkWell, 'Favorites'));
    await tester.pump();
    await tester.tap(
      find.byKey(Key('favorite-play-${favoriteTracks.single.path}')),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(FavoritesPlaybackView),
        matching: find.byTooltip('Remove from favorites'),
      ),
    );
    await tester.pump();

    expect(playback.stopIfCurrentRemovedCount, 1);
    expect(playback.currentTrack, isNull);
    expect(find.byType(FavoritesPlaybackView), findsOneWidget);
    expect(find.text('No favorite tracks yet'), findsWidgets);

    await _disposeLibraryScreen(tester, library, playback);
  });

  testWidgets(
    'unfavoriting a playing album track does not stop album playback',
    (tester) async {
      final fixture = _LibraryFixture.album();
      final library = _InjectedLibraryController(
        tracks: fixture.tracks,
        albums: [fixture.album],
        favoriteTracks: fixture.tracks,
      );
      final playback = _InjectedPlaybackController(
        currentTrack: fixture.tracks.first,
        playing: true,
        currentQueue: fixture.tracks,
      );

      await _pumpLibraryScreen(
        tester,
        library: library,
        playback: playback,
        now: DateTime.now,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(AlbumGrid),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Remove from favorites'));
      await tester.pump();

      expect(playback.stopIfCurrentRemovedCount, 0);
      expect(playback.currentTrack?.path, fixture.tracks.first.path);
      expect(playback.playing, isTrue);
      expect(find.byType(AlbumPlaybackView), findsOneWidget);

      await _disposeLibraryScreen(tester, library, playback);
    },
  );

  testWidgets('shows repeated playback failures as separate events', (
    tester,
  ) async {
    final library = _InjectedLibraryController();
    final playback = _InjectedPlaybackController();

    await _pumpLibraryScreen(
      tester,
      library: library,
      playback: playback,
      now: DateTime.now,
    );

    playback.emitPlaybackErrorForTest('test failure');
    tester.binding.scheduleFrame();
    await tester.pumpAndSettle();
    expect(find.text('Playback error: test failure'), findsOneWidget);

    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold)),
    ).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(find.text('Playback error: test failure'), findsNothing);

    playback.emitPlaybackErrorForTest('test failure');
    tester.binding.scheduleFrame();
    await tester.pumpAndSettle();
    expect(find.text('Playback error: test failure'), findsOneWidget);

    await _disposeLibraryScreen(tester, library, playback);
  });
}

class _LibraryFixture {
  _LibraryFixture.album()
    : album = const AlbumSummary(
        folderPath: '/music/Artist/Album',
        title: 'Album',
        albumArtist: 'Artist',
        year: 2026,
        trackCount: 1,
        coverArtPath: null,
      ),
      tracks = [
        _track(
          '/music/Artist/Album/01 Opening.flac',
          folderPath: '/music/Artist/Album',
          title: 'Opening',
          album: 'Album',
          artist: 'Artist',
        ),
      ];

  final AlbumSummary album;
  final List<Track> tracks;
}

AlbumSummary _albumSummary(String folderPath, String title) {
  return AlbumSummary(
    folderPath: folderPath,
    title: title,
    albumArtist: 'Artist',
    year: 2026,
    trackCount: 1,
    coverArtPath: null,
  );
}

Future<void> _pumpDialogTransition(WidgetTester tester) async {
  // Playback keeps animating, so pumpAndSettle cannot finish here.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pumpLibraryScreen(
  WidgetTester tester, {
  required _InjectedLibraryController library,
  required _InjectedPlaybackController playback,
  required LibraryScreenClock now,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: LibraryScreen(
        themeMode: ThemeMode.light,
        onThemeModeChanged: (_) {},
        libraryController: library,
        playbackController: playback,
        now: now,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _disposeLibraryScreen(
  WidgetTester tester,
  _InjectedLibraryController library,
  _InjectedPlaybackController playback,
) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  playback.disposeForTest();
  library.disposeForTest();
}

FolderSummary _playlistFolder(String path, String name) {
  return FolderSummary(
    path: path,
    name: name,
    kind: FolderKind.playlist,
    confidence: 0.8,
    trackCount: 1,
    albumCount: 1,
    albumArtistCount: 1,
    artistCount: 1,
    yearCount: 1,
    coverArtPath: null,
  );
}

Track _track(
  String path, {
  required String folderPath,
  required String title,
  required String album,
  required String artist,
}) {
  return Track(
    path: path,
    folderPath: folderPath,
    title: title,
    artist: artist,
    album: album,
    albumArtist: artist,
    trackNumber: 1,
    discNumber: null,
    year: 2026,
    durationMs: 180000,
    sizeBytes: 42,
    modifiedMs: 1,
    coverArtPath: null,
  );
}

List<Track> _favoriteTracks(int count) {
  return [
    for (var index = 0; index < count; index += 1)
      _track(
        '/music/Favorites/${index + 1}.flac',
        folderPath: '/music/Favorites',
        title: 'Favorite ${index + 1}',
        album: 'Favorites',
        artist: 'Artist $index',
      ),
  ];
}

bool _sameTrackOrder(List<Track> left, List<Track> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index].path != right[index].path) {
      return false;
    }
  }
  return true;
}

// Spies on UI commands; mutations and derived state use the production code.
class _InjectedLibraryController extends LibraryController {
  factory _InjectedLibraryController({
    bool canEditMusicRoot = false,
    List<Track> tracks = const [],
    List<FolderSummary> folders = const [],
    List<AlbumSummary> albums = const [],
    List<Track> favoriteTracks = const [],
    LastPlaybackState? lastPlaybackState,
    bool canRestorePlayback = false,
    String? themeSaveError,
  }) => _InjectedLibraryController._(
    LibraryTestStore(
      tracks: tracks,
      folders: folders,
      albums: albums,
      favoriteTracks: favoriteTracks,
      lastPlayback: lastPlaybackState,
    ),
    canEditMusicRoot: canEditMusicRoot,
    canRestorePlayback: canRestorePlayback,
    themeSaveError: themeSaveError,
  );

  _InjectedLibraryController._(
    this.store, {
    required this.canEditMusicRoot,
    required this.canRestorePlayback,
    this.themeSaveError,
  }) : super(
         openDatabase: store.open,
         scanner: store.scanner,
         coverIndexer: NoopTrackCoverIndexer(),
         migrateCoverCache: (_) async {},
       );

  final LibraryTestStore store;
  final bool canEditMusicRoot;
  final bool canRestorePlayback;
  final String? themeSaveError;
  bool opened = false;
  bool disposedByScreen = false;
  Completer<void>? favoriteBlocker;
  Object? favoriteError;
  Future<void> Function(LastPlaybackState)? onSaveLastPlayback;
  Future<void>? _opening;
  String? savedThemeMode;
  String? changedMusicRoot;

  Future<void> prepareRescan(List<Track> nextTracks) async {
    store.setScanTracks(nextTracks);
    await startRescanDiff();
  }

  @override
  Future<void> open() {
    opened = true;
    return _opening ??= super.open();
  }

  @override
  Future<void> saveThemeMode(String value) async {
    if (themeSaveError != null) throw StateError(themeSaveError!);
    await super.saveThemeMode(value);
    savedThemeMode = value;
  }

  @override
  Future<bool> changeMusicRoot(String nextRoot) async {
    changedMusicRoot = nextRoot;
    return true;
  }

  @override
  Future<void> saveLastPlayback(LastPlaybackState state) async {
    await onSaveLastPlayback?.call(state);
    await super.saveLastPlayback(state);
  }

  @override
  Future<void> toggleFavoriteTrack(Track track) async {
    await favoriteBlocker?.future;
    final error = favoriteError;
    if (error != null) throw error;
    await super.toggleFavoriteTrack(track);
  }

  @override
  bool get canChangeMusicRoot => canEditMusicRoot && super.canChangeMusicRoot;

  @override
  bool get canRestoreLastPlayback =>
      canRestorePlayback && super.canRestoreLastPlayback;

  @override
  void dispose() {
    disposedByScreen = true;
    super.dispose();
  }

  void disposeForTest() => super.dispose();
}

// Records UI commands while exercising the real queue and playback logic.
class _InjectedPlaybackController extends PlaybackController {
  factory _InjectedPlaybackController({
    LastPlaybackKind kind = LastPlaybackKind.album,
    Track? currentTrack,
    bool playing = false,
    List<Track> currentQueue = const [],
  }) {
    final controller = _InjectedPlaybackController._(FakePlatformPlayer());
    if (currentTrack != null) {
      unawaited(
        controller.playSession(
          PlaybackSession.start(
            kind: kind,
            folderPath: kind == LastPlaybackKind.favorites
                ? ''
                : currentTrack.folderPath,
            tracks: currentQueue,
            startTrack: currentTrack,
          ),
          play: playing,
        ),
      );
    }
    return controller;
  }

  _InjectedPlaybackController._(this.platform)
    : super(player: Player(platformPlayer: platform));

  final FakePlatformPlayer platform;
  bool disposedByScreen = false;
  int toggleCount = 0;

  int get stopIfCurrentRemovedCount => platform.stopCount;
  List<Track> get currentQueueForTest => queue;

  void emitPlaybackErrorForTest(String message) => platform.emitError(message);

  @override
  Future<void> togglePlayPause() {
    toggleCount += 1;
    return super.togglePlayPause();
  }

  @override
  void dispose() {
    disposedByScreen = true;
    super.dispose();
  }

  void disposeForTest() => super.dispose();
}
