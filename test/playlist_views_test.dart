import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/models.dart';
import 'package:miaosic/playlist_views.dart';

void main() {
  testWidgets('playlist list restores scroll position after remount', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final folders = _folders(24);
    final tracksByFolder = {
      for (final folder in folders)
        folder.path: [_track(folderPath: folder.path)],
    };
    var showList = true;
    late StateSetter updateState;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          updateState = setState;
          return MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 900,
                height: 360,
                child: showList
                    ? PlaylistList(
                        folders: folders,
                        tracksByFolder: tracksByFolder,
                        trackCoverCache: const {},
                        scrollController: scrollController,
                        keyboardShortcutsEnabled: true,
                        onOpen: (_) {},
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          );
        },
      ),
    );
    await tester.pump();

    scrollController.jumpTo(180);
    await tester.pump();
    updateState(() => showList = false);
    await tester.pump();
    updateState(() => showList = true);
    await tester.pump();

    expect(scrollController.offset, closeTo(180, 0.1));
  });

  testWidgets('playlist row opens playback overlay entry', (tester) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final folders = _folders(2);
    final tracksByFolder = {
      for (final folder in folders)
        folder.path: [
          _track(folderPath: folder.path, title: 'Track One'),
          _track(folderPath: folder.path, title: 'Track Two'),
        ],
    };
    FolderSummary? opened;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 420,
            child: PlaylistList(
              folders: folders,
              tracksByFolder: tracksByFolder,
              trackCoverCache: const {},
              scrollController: scrollController,
              keyboardShortcutsEnabled: true,
              onOpen: (folder) => opened = folder,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Playlist 0'), findsOneWidget);
    expect(find.text('PLAYLIST'), findsWidgets);
    expect(find.text('Track One'), findsWidgets);
    expect(find.byType(ListView), findsOneWidget);

    await tester.tap(find.text('Playlist 0'));
    await tester.pump();

    expect(opened?.path, folders.first.path);
  });

  testWidgets('playlist list resumes space paging after focus token changes', (
    tester,
  ) async {
    final scrollController = ScrollController();
    final otherFocusNode = FocusNode();
    addTearDown(scrollController.dispose);
    addTearDown(otherFocusNode.dispose);
    final folders = _folders(24);
    final tracksByFolder = {
      for (final folder in folders)
        folder.path: [_track(folderPath: folder.path)],
    };
    var focusRequestToken = 0;
    late StateSetter updateState;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          updateState = setState;
          return MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    width: 900,
                    height: 360,
                    child: PlaylistList(
                      folders: folders,
                      tracksByFolder: tracksByFolder,
                      trackCoverCache: const {},
                      scrollController: scrollController,
                      keyboardShortcutsEnabled: true,
                      focusRequestToken: focusRequestToken,
                      onOpen: (_) {},
                    ),
                  ),
                  Focus(
                    focusNode: otherFocusNode,
                    child: const SizedBox(width: 1, height: 1),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    await tester.pump();
    otherFocusNode.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(scrollController.offset, 0);

    updateState(() => focusRequestToken += 1);
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(scrollController.offset, greaterThan(0));
  });

  testWidgets('playlist row fits in a narrow layout', (tester) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final folders = _folders(1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 260,
            child: PlaylistList(
              folders: folders,
              tracksByFolder: {
                folders.single.path: [
                  _track(
                    folderPath: folders.single.path,
                    title: 'A Very Long Playlist Track Title',
                  ),
                ],
              },
              trackCoverCache: const {},
              scrollController: scrollController,
              keyboardShortcutsEnabled: true,
              onOpen: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('mouse wheel scrolls the playlist list horizontally', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final folders = _folders(24);
    final tracksByFolder = {
      for (final folder in folders)
        folder.path: [_track(folderPath: folder.path)],
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 360,
            child: PlaylistList(
              folders: folders,
              tracksByFolder: tracksByFolder,
              trackCoverCache: const {},
              scrollController: scrollController,
              keyboardShortcutsEnabled: true,
              onOpen: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(scrollController.offset, 0);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(PlaylistList)),
        scrollDelta: const Offset(0, 160),
      ),
    );
    await tester.pump();

    expect(scrollController.offset, greaterThan(0));
  });

  testWidgets('playlist indicator jumps to a selected playlist', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final folders = _folders(12);
    final tracksByFolder = {
      for (final folder in folders)
        folder.path: [_track(folderPath: folder.path)],
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 420,
            child: PlaylistList(
              folders: folders,
              tracksByFolder: tracksByFolder,
              trackCoverCache: const {},
              scrollController: scrollController,
              keyboardShortcutsEnabled: true,
              onOpen: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(scrollController.offset, 0);
    final indicatorFinder = find.byKey(
      const ValueKey<String>('playlist-indicator-5'),
    );
    expect(indicatorFinder, findsOneWidget);
    final indicatorSize = tester.getSize(indicatorFinder);
    expect(indicatorSize.width, greaterThanOrEqualTo(40));
    expect(indicatorSize.height, greaterThanOrEqualTo(40));

    await tester.tap(indicatorFinder);
    await tester.pumpAndSettle();

    expect(scrollController.offset, greaterThan(0));
  });

  testWidgets('space and shift space page through the playlist list', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final folders = _folders(24);
    final tracksByFolder = {
      for (final folder in folders)
        folder.path: [_track(folderPath: folder.path)],
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 360,
            child: PlaylistList(
              folders: folders,
              tracksByFolder: tracksByFolder,
              trackCoverCache: const {},
              scrollController: scrollController,
              keyboardShortcutsEnabled: true,
              onOpen: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(scrollController.offset, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    final pageDownOffset = scrollController.offset;
    expect(pageDownOffset, greaterThan(0));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(scrollController.offset, lessThan(pageDownOffset));
  });
}

List<FolderSummary> _folders(int count) {
  return [
    for (var index = 0; index < count; index += 1)
      FolderSummary(
        path: '/music/playlists/playlist_$index',
        name: 'Playlist $index',
        kind: FolderKind.playlist,
        confidence: 0.9,
        trackCount: 1,
        albumCount: 1,
        albumArtistCount: 1,
        artistCount: 1,
        yearCount: 1,
        coverArtPath: null,
      ),
  ];
}

Track _track({required String folderPath, String title = 'Track One'}) {
  return Track(
    path: '$folderPath/01.flac',
    folderPath: folderPath,
    title: title,
    artist: 'Artist',
    album: 'Album One',
    albumArtist: 'Artist',
    trackNumber: 1,
    discNumber: 1,
    year: 2026,
    durationMs: 120000,
    sizeBytes: 42,
    modifiedMs: 99,
    coverArtPath: null,
  );
}
