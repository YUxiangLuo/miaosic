import 'package:flutter/material.dart';

import 'library_screen.dart';

class MiaosicApp extends StatelessWidget {
  const MiaosicApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xff246b5b);
    return MaterialApp(
      title: 'Miaosic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        scaffoldBackgroundColor: const Color(0xfff7f7f4),
        useMaterial3: true,
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: Color(0xffeeeeea),
          indicatorColor: Color(0xffd8ebe3),
          selectedIconTheme: IconThemeData(color: seed),
          selectedLabelTextStyle: TextStyle(
            color: seed,
            fontWeight: FontWeight.w700,
          ),
        ),
        sliderTheme: const SliderThemeData(trackHeight: 3),
      ),
      home: const LibraryScreen(),
    );
  }
}
