import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'library_widgets.dart';
import 'models.dart';

const _fallbackAlbumColor = Color(0xff246b5b);

class AlbumPlaybackView extends StatefulWidget {
  const AlbumPlaybackView({
    super.key,
    required this.album,
    required this.tracks,
    required this.currentTrack,
    required this.playing,
    required this.onClose,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
  });

  final AlbumSummary album;
  final List<Track> tracks;
  final Track? currentTrack;
  final bool playing;
  final VoidCallback onClose;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;

  @override
  State<AlbumPlaybackView> createState() => _AlbumPlaybackViewState();
}

class _AlbumPlaybackViewState extends State<AlbumPlaybackView> {
  Color _themeColor = _fallbackAlbumColor;
  int _paletteGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadThemeColor();
  }

  @override
  void didUpdateWidget(covariant AlbumPlaybackView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.album.coverArtPath != widget.album.coverArtPath) {
      _loadThemeColor();
    }
  }

  void _loadThemeColor() {
    final coverPath = widget.album.coverArtPath;
    final generation = ++_paletteGeneration;
    if (coverPath == null || coverPath.isEmpty) {
      setState(() => _themeColor = _fallbackAlbumColor);
      return;
    }

    _extractThemeColor(coverPath).then((color) {
      if (mounted && generation == _paletteGeneration) {
        setState(() => _themeColor = color);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentTrack = widget.currentTrack;
    final currentIndex = currentTrack == null
        ? -1
        : widget.tracks.indexWhere((track) => track.path == currentTrack.path);
    final canPrevious = currentIndex > 0;
    final canNext =
        currentIndex >= 0 && currentIndex < widget.tracks.length - 1;
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          _AlbumPlaybackBackground(
            coverArtPath: widget.album.coverArtPath,
            themeColor: _themeColor,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Back to library',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 860) {
                          return _AlbumPlaybackNarrowLayout(
                            album: widget.album,
                            tracks: widget.tracks,
                            currentTrack: currentTrack,
                            coverSize: math.min(
                              constraints.maxWidth - 36,
                              constraints.maxHeight * 0.52,
                            ),
                            playing: widget.playing,
                            canPrevious: canPrevious,
                            canNext: canNext,
                            onPrevious: widget.onPrevious,
                            onToggle: widget.onToggle,
                            onNext: widget.onNext,
                          );
                        }
                        return _AlbumPlaybackWideLayout(
                          album: widget.album,
                          tracks: widget.tracks,
                          currentTrack: currentTrack,
                          coverSize: math.min(
                            constraints.maxWidth * 0.46,
                            constraints.maxHeight * 0.82,
                          ),
                          playing: widget.playing,
                          canPrevious: canPrevious,
                          canNext: canNext,
                          onPrevious: widget.onPrevious,
                          onToggle: widget.onToggle,
                          onNext: widget.onNext,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumPlaybackWideLayout extends StatelessWidget {
  const _AlbumPlaybackWideLayout({
    required this.album,
    required this.tracks,
    required this.currentTrack,
    required this.coverSize,
    required this.playing,
    required this.canPrevious,
    required this.canNext,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
  });

  final AlbumSummary album;
  final List<Track> tracks;
  final Track? currentTrack;
  final double coverSize;
  final bool playing;
  final bool canPrevious;
  final bool canNext;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _LargeAlbumArtwork(album: album, size: coverSize),
          const SizedBox(width: 54),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _AlbumPlaybackInfo(
              album: album,
              tracks: tracks,
              currentTrack: currentTrack,
              playing: playing,
              canPrevious: canPrevious,
              canNext: canNext,
              onPrevious: onPrevious,
              onToggle: onToggle,
              onNext: onNext,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumPlaybackNarrowLayout extends StatelessWidget {
  const _AlbumPlaybackNarrowLayout({
    required this.album,
    required this.tracks,
    required this.currentTrack,
    required this.coverSize,
    required this.playing,
    required this.canPrevious,
    required this.canNext,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
  });

  final AlbumSummary album;
  final List<Track> tracks;
  final Track? currentTrack;
  final double coverSize;
  final bool playing;
  final bool canPrevious;
  final bool canNext;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _LargeAlbumArtwork(album: album, size: coverSize),
          const SizedBox(height: 28),
          _AlbumPlaybackInfo(
            album: album,
            tracks: tracks,
            currentTrack: currentTrack,
            playing: playing,
            canPrevious: canPrevious,
            canNext: canNext,
            onPrevious: onPrevious,
            onToggle: onToggle,
            onNext: onNext,
            centered: true,
          ),
        ],
      ),
    );
  }
}

class _AlbumPlaybackInfo extends StatelessWidget {
  const _AlbumPlaybackInfo({
    required this.album,
    required this.tracks,
    required this.currentTrack,
    required this.playing,
    required this.canPrevious,
    required this.canNext,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
    this.centered = false,
  });

  final AlbumSummary album;
  final List<Track> tracks;
  final Track? currentTrack;
  final bool playing;
  final bool canPrevious;
  final bool canNext;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final textAlign = centered ? TextAlign.center : TextAlign.start;
    final crossAxisAlignment = centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    final current = currentTrack;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Text(
          album.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            height: 1.02,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _albumSubtitle(album, tracks),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.74),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 34),
        if (current != null) ...[
          Text(
            current.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            current.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 34),
        ],
        _AlbumPlaybackControls(
          playing: playing,
          canPrevious: canPrevious,
          canNext: canNext,
          onPrevious: onPrevious,
          onToggle: onToggle,
          onNext: onNext,
        ),
      ],
    );
  }
}

class _AlbumPlaybackControls extends StatelessWidget {
  const _AlbumPlaybackControls({
    required this.playing,
    required this.canPrevious,
    required this.canNext,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
  });

  final bool playing;
  final bool canPrevious;
  final bool canNext;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PlaybackIconButton(
          tooltip: 'Previous',
          icon: Icons.skip_previous,
          onPressed: canPrevious ? onPrevious : null,
        ),
        const SizedBox(width: 18),
        _PlaybackIconButton(
          tooltip: playing ? 'Pause' : 'Play',
          icon: playing ? Icons.pause : Icons.play_arrow,
          prominent: true,
          onPressed: onToggle,
        ),
        const SizedBox(width: 18),
        _PlaybackIconButton(
          tooltip: 'Next',
          icon: Icons.skip_next,
          onPressed: canNext ? onNext : null,
        ),
      ],
    );
  }
}

class _PlaybackIconButton extends StatelessWidget {
  const _PlaybackIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.prominent = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final size = prominent ? 72.0 : 54.0;
    return IconButton.filled(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: prominent ? 34 : 26,
      style: IconButton.styleFrom(
        fixedSize: Size.square(size),
        backgroundColor: Colors.white.withValues(alpha: prominent ? 0.92 : 0.2),
        foregroundColor: prominent
            ? const Color(0xff151515)
            : Colors.white.withValues(alpha: 0.95),
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.28),
      ),
      icon: Icon(icon),
    );
  }
}

class _LargeAlbumArtwork extends StatelessWidget {
  const _LargeAlbumArtwork({required this.album, required this.size});

  final AlbumSummary album;
  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.36),
            blurRadius: 34,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Artwork(
        path: album.coverArtPath,
        size: size.clamp(260.0, 820.0).toDouble(),
        icon: Icons.album,
        radius: 14,
      ),
    );
  }
}

class _AlbumPlaybackBackground extends StatelessWidget {
  const _AlbumPlaybackBackground({
    required this.coverArtPath,
    required this.themeColor,
  });

  final String? coverArtPath;
  final Color themeColor;

  @override
  Widget build(BuildContext context) {
    final coverPath = coverArtPath;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                themeColor.withValues(alpha: 0.96),
                HSLColor.fromColor(
                  themeColor,
                ).withLightness(0.12).toColor().withValues(alpha: 1),
              ],
            ),
          ),
        ),
        if (coverPath != null && coverPath.isNotEmpty)
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
            child: Transform.scale(
              scale: 1.08,
              child: Image.file(
                File(coverPath),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                themeColor.withValues(alpha: 0.55),
                Colors.black.withValues(alpha: 0.84),
              ],
            ),
          ),
        ),
        ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
      ],
    );
  }
}

Future<Color> _extractThemeColor(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) {
      return _fallbackAlbumColor;
    }
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 40);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) {
      return _fallbackAlbumColor;
    }

    double red = 0;
    double green = 0;
    double blue = 0;
    double totalWeight = 0;
    final pixels = data.buffer.asUint8List();
    for (var offset = 0; offset + 3 < pixels.length; offset += 4) {
      final alpha = pixels[offset + 3];
      if (alpha < 128) {
        continue;
      }
      final r = pixels[offset];
      final g = pixels[offset + 1];
      final b = pixels[offset + 2];
      final color = Color.fromARGB(255, r, g, b);
      final hsl = HSLColor.fromColor(color);
      final lightness = hsl.lightness;
      final saturation = hsl.saturation;
      if (lightness < 0.05 || lightness > 0.95) {
        continue;
      }
      final balance = 1 - (lightness - 0.5).abs();
      final weight = (0.25 + saturation) * balance;
      red += r * weight;
      green += g * weight;
      blue += b * weight;
      totalWeight += weight;
    }

    if (totalWeight <= 0) {
      return _fallbackAlbumColor;
    }
    final averaged = Color.fromARGB(
      255,
      (red / totalWeight).round().clamp(0, 255).toInt(),
      (green / totalWeight).round().clamp(0, 255).toInt(),
      (blue / totalWeight).round().clamp(0, 255).toInt(),
    );
    final hsl = HSLColor.fromColor(averaged);
    return hsl
        .withSaturation(math.max(0.34, hsl.saturation))
        .withLightness(hsl.lightness.clamp(0.22, 0.46).toDouble())
        .toColor();
  } catch (_) {
    return _fallbackAlbumColor;
  }
}

String _albumSubtitle(AlbumSummary album, List<Track> tracks) {
  final year = album.year;
  final yearText = year == null ? '' : ' · $year';
  return '${album.albumArtist}$yearText · ${tracks.length} tracks';
}
