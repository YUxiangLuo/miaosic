import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/library_sidebar.dart';
import 'package:miaosic/library_types.dart';

void main() {
  testWidgets('library storage button opens rescan modal entry only', (
    tester,
  ) async {
    var openLibraryCount = 0;
    var toggleThemeCount = 0;
    var openSettingsCount = 0;
    var selectedCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibrarySidebar(
            selected: LibraryView.albums,
            albums: 12,
            playlists: 4,
            favorites: 2,
            nowPlaying: null,
            themeMode: ThemeMode.light,
            onOpenLibrary: () => openLibraryCount += 1,
            onToggleThemeMode: () => toggleThemeCount += 1,
            onOpenSettings: () => openSettingsCount += 1,
            onOpenNowPlaying: null,
            onSelected: (_) => selectedCount += 1,
          ),
        ),
      ),
    );

    expect(find.byTooltip('Library settings'), findsOneWidget);
    expect(find.byTooltip('Switch to dark mode'), findsOneWidget);
    expect(find.widgetWithIcon(IconButton, Icons.dark_mode), findsOneWidget);
    expect(find.widgetWithIcon(IconButton, Icons.settings), findsOneWidget);

    await tester.tap(find.byTooltip('Library settings'));
    await tester.pump();
    await tester.tap(find.byTooltip('Switch to dark mode'));
    await tester.pump();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();

    expect(openLibraryCount, 1);
    expect(toggleThemeCount, 1);
    expect(openSettingsCount, 1);
    expect(selectedCount, 0);
  });

  testWidgets('theme button reflects dark mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibrarySidebar(
            selected: LibraryView.albums,
            albums: 12,
            playlists: 4,
            favorites: 2,
            nowPlaying: null,
            themeMode: ThemeMode.dark,
            onOpenLibrary: () {},
            onToggleThemeMode: () {},
            onOpenSettings: () {},
            onOpenNowPlaying: null,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Switch to light mode'), findsOneWidget);
    expect(find.widgetWithIcon(IconButton, Icons.light_mode), findsOneWidget);
  });

  testWidgets('footer actions are centered in the sidebar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibrarySidebar(
            selected: LibraryView.albums,
            albums: 12,
            playlists: 4,
            favorites: 2,
            nowPlaying: null,
            themeMode: ThemeMode.light,
            onOpenLibrary: () {},
            onToggleThemeMode: () {},
            onOpenSettings: () {},
            onOpenNowPlaying: null,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    final sidebarCenterX = tester
        .getRect(find.byType(LibrarySidebar))
        .center
        .dx;
    final firstButtonRect = tester.getRect(
      find.widgetWithIcon(IconButton, Icons.storage),
    );
    final lastButtonRect = tester.getRect(
      find.widgetWithIcon(IconButton, Icons.settings),
    );
    final actionGroupCenterX =
        (firstButtonRect.left + lastButtonRect.right) / 2;

    expect(actionGroupCenterX, closeTo(sidebarCenterX, 0.1));
  });

  testWidgets('footer actions can be disabled during startup', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibrarySidebar(
            selected: LibraryView.albums,
            albums: 12,
            playlists: 4,
            favorites: 2,
            nowPlaying: null,
            themeMode: ThemeMode.light,
            onOpenLibrary: null,
            onToggleThemeMode: null,
            onOpenSettings: null,
            onOpenNowPlaying: null,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    final libraryButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.storage),
    );
    final themeButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.dark_mode),
    );
    final settingsButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.settings),
    );

    expect(libraryButton.onPressed, isNull);
    expect(themeButton.onPressed, isNull);
    expect(settingsButton.onPressed, isNull);
  });
}
