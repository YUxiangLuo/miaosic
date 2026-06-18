import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/album_views.dart';
import 'package:miaosic/models.dart';

void main() {
  testWidgets('single tap opens album without playing it', (tester) async {
    final album = _album();
    final tracks = [_track()];
    var openCount = 0;

    await tester.pumpWidget(
      _albumGrid(
        album: album,
        tracks: tracks,
        onOpen: (_, _) => openCount += 1,
      ),
    );

    expect(find.text(album.title), findsNothing);
    expect(
      tester.widget<InkWell>(find.byType(InkWell)).mouseCursor,
      SystemMouseCursors.click,
    );

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(openCount, 1);
  });

  testWidgets('empty album does not open', (tester) async {
    final album = _album(trackCount: 0);
    var openCount = 0;

    await tester.pumpWidget(
      _albumGrid(
        album: album,
        tracks: const [],
        onOpen: (_, _) => openCount += 1,
      ),
    );

    expect(find.text(album.title), findsNothing);
    expect(
      tester.widget<InkWell>(find.byType(InkWell)).mouseCursor,
      SystemMouseCursors.basic,
    );

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(openCount, 0);
  });

  testWidgets('floating jump buttons follow album grid scroll position', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final albums = _albums(24);
    final tracksByFolder = {
      for (final album in albums)
        album.folderPath: [_track(folderPath: album.folderPath)],
    };

    await tester.pumpWidget(
      _albumGrid(
        albums: albums,
        tracksByFolder: tracksByFolder,
        scrollController: scrollController,
        onOpen: (_, _) {},
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Back to top'), findsNothing);
    expect(find.byTooltip('Back to bottom'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to bottom'));
    await tester.pumpAndSettle();

    expect(
      scrollController.offset,
      closeTo(scrollController.position.maxScrollExtent, 0.1),
    );
    expect(find.byTooltip('Back to top'), findsOneWidget);
    expect(find.byTooltip('Back to bottom'), findsNothing);
  });

  testWidgets('space and shift space page through the album grid', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final albums = _albums(24);
    final tracksByFolder = {
      for (final album in albums)
        album.folderPath: [_track(folderPath: album.folderPath)],
    };

    await tester.pumpWidget(
      _albumGrid(
        albums: albums,
        tracksByFolder: tracksByFolder,
        scrollController: scrollController,
        onOpen: (_, _) {},
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

  testWidgets('album grid keeps scroll position when shortcuts toggle', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final albums = _albums(24);
    final tracksByFolder = {
      for (final album in albums)
        album.folderPath: [_track(folderPath: album.folderPath)],
    };
    var keyboardShortcutsEnabled = true;
    late StateSetter updateState;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          updateState = setState;
          return _albumGrid(
            albums: albums,
            tracksByFolder: tracksByFolder,
            scrollController: scrollController,
            keyboardShortcutsEnabled: keyboardShortcutsEnabled,
            onOpen: (_, _) {},
          );
        },
      ),
    );
    await tester.pump();

    scrollController.jumpTo(180);
    await tester.pump();

    updateState(() => keyboardShortcutsEnabled = false);
    await tester.pump();

    expect(scrollController.offset, closeTo(180, 0.1));
  });

  testWidgets(
    'album grid resumes space paging after shortcuts are re-enabled',
    (tester) async {
      final scrollController = ScrollController();
      final otherFocusNode = FocusNode();
      addTearDown(scrollController.dispose);
      addTearDown(otherFocusNode.dispose);
      final albums = _albums(24);
      final tracksByFolder = {
        for (final album in albums)
          album.folderPath: [_track(folderPath: album.folderPath)],
      };
      var keyboardShortcutsEnabled = false;
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
                      child: AlbumGrid(
                        albums: albums,
                        tracksByFolder: tracksByFolder,
                        scrollController: scrollController,
                        keyboardShortcutsEnabled: keyboardShortcutsEnabled,
                        onOpen: (_, _) {},
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

      updateState(() => keyboardShortcutsEnabled = true);
      await tester.pump();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(scrollController.offset, greaterThan(0));
    },
  );

  testWidgets('album grid resumes space paging after focus token changes', (
    tester,
  ) async {
    final scrollController = ScrollController();
    final otherFocusNode = FocusNode();
    addTearDown(scrollController.dispose);
    addTearDown(otherFocusNode.dispose);
    final albums = _albums(24);
    final tracksByFolder = {
      for (final album in albums)
        album.folderPath: [_track(folderPath: album.folderPath)],
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
                    child: AlbumGrid(
                      albums: albums,
                      tracksByFolder: tracksByFolder,
                      scrollController: scrollController,
                      keyboardShortcutsEnabled: true,
                      focusRequestToken: focusRequestToken,
                      onOpen: (_, _) {},
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

  testWidgets('album grid restores scroll position after remount', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final albums = _albums(24);
    final tracksByFolder = {
      for (final album in albums)
        album.folderPath: [_track(folderPath: album.folderPath)],
    };
    var showGrid = true;
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
                child: showGrid
                    ? AlbumGrid(
                        albums: albums,
                        tracksByFolder: tracksByFolder,
                        scrollController: scrollController,
                        keyboardShortcutsEnabled: true,
                        onOpen: (_, _) {},
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
    updateState(() => showGrid = false);
    await tester.pump();
    updateState(() => showGrid = true);
    await tester.pump();

    expect(scrollController.offset, closeTo(180, 0.1));
  });

  testWidgets('disabled album grid shortcuts do not page the hidden grid', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final albums = _albums(24);
    final tracksByFolder = {
      for (final album in albums)
        album.folderPath: [_track(folderPath: album.folderPath)],
    };

    await tester.pumpWidget(
      _albumGrid(
        albums: albums,
        tracksByFolder: tracksByFolder,
        scrollController: scrollController,
        keyboardShortcutsEnabled: false,
        onOpen: (_, _) {},
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(scrollController.offset, 0);
  });
}

Widget _albumGrid({
  AlbumSummary? album,
  List<Track>? tracks,
  List<AlbumSummary>? albums,
  Map<String, List<Track>>? tracksByFolder,
  ScrollController? scrollController,
  bool keyboardShortcutsEnabled = true,
  required void Function(AlbumSummary album, List<Track> tracks) onOpen,
}) {
  final resolvedAlbum = album;
  final resolvedAlbums = albums ?? [resolvedAlbum!];
  final resolvedTracksByFolder =
      tracksByFolder ?? {resolvedAlbum!.folderPath: tracks ?? const <Track>[]};
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 900,
        height: 360,
        child: AlbumGrid(
          albums: resolvedAlbums,
          tracksByFolder: resolvedTracksByFolder,
          scrollController: scrollController ?? ScrollController(),
          keyboardShortcutsEnabled: keyboardShortcutsEnabled,
          onOpen: onOpen,
        ),
      ),
    ),
  );
}

List<AlbumSummary> _albums(int count) {
  return [
    for (var index = 0; index < count; index += 1)
      _album(folderPath: '/music/artist/album_$index', title: 'Album $index'),
  ];
}

AlbumSummary _album({
  int trackCount = 1,
  String folderPath = '/music/artist/album',
  String title = 'Album One',
}) {
  return AlbumSummary(
    folderPath: folderPath,
    title: title,
    albumArtist: 'Artist',
    year: 2026,
    trackCount: trackCount,
    coverArtPath: null,
  );
}

Track _track({String folderPath = '/music/artist/album'}) {
  return Track(
    path: '$folderPath/01.flac',
    folderPath: folderPath,
    title: 'Track One',
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
