import 'package:flutter/material.dart';

import 'library_screen.dart';

class MiaosicApp extends StatefulWidget {
  const MiaosicApp({super.key});

  @override
  State<MiaosicApp> createState() => _MiaosicAppState();
}

class _MiaosicAppState extends State<MiaosicApp> {
  static const _seed = Color(0xff246b5b);

  ThemeMode _themeMode = ThemeMode.light;

  void _setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) {
      return;
    }
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Miaosic',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _themeMode,
      home: LibraryScreen(
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? const Color(0xff101412)
          : const Color(0xfff7f7f4),
      useMaterial3: true,
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: dark
            ? const Color(0xff171d1a)
            : const Color(0xffeeeeea),
        indicatorColor: dark
            ? const Color(0xff24483d)
            : const Color(0xffd8ebe3),
        selectedIconTheme: IconThemeData(color: scheme.primary),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      sliderTheme: const SliderThemeData(trackHeight: 3),
    );
  }
}
