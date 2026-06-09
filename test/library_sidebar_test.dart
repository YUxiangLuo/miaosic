import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/library_sidebar.dart';
import 'package:miaosic/library_types.dart';

void main() {
  testWidgets('library storage button opens rescan modal entry only', (
    tester,
  ) async {
    var openLibraryCount = 0;
    var selectedCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibrarySidebar(
            selected: LibraryView.albums,
            albums: 12,
            playlists: 4,
            nowPlaying: null,
            onOpenLibrary: () => openLibraryCount += 1,
            onOpenNowPlaying: null,
            onSelected: (_) => selectedCount += 1,
          ),
        ),
      ),
    );

    expect(find.byTooltip('Library settings'), findsOneWidget);
    expect(find.widgetWithIcon(IconButton, Icons.brightness_6), findsOneWidget);
    expect(find.widgetWithIcon(IconButton, Icons.settings), findsOneWidget);

    final themeButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.brightness_6),
    );
    final settingsButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.settings),
    );
    expect(themeButton.onPressed, isNull);
    expect(settingsButton.onPressed, isNull);

    await tester.tap(find.byTooltip('Library settings'));
    await tester.pump();

    expect(openLibraryCount, 1);
    expect(selectedCount, 0);
  });
}
