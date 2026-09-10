// Run a visible native profile/release window; no audio, scan, or database access.
// See docs/performance/cd-rotation.md for build and measurement commands.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:miaosic/album_playback_view.dart';
import 'package:miaosic/models.dart';

final cover = Platform.environment['MIAOSIC_DIAG_COVER'] ?? '';
final output =
    Platform.environment['MIAOSIC_DIAG_OUTPUT'] ??
    '/tmp/miaosic-frame-probe.json';
final stageNames = ['album_view', 'isolated_image_rotation', 'solid_rotation'];
final frames = <ui.FrameTiming>[];
final ticks = <int>[];
final results = <Map<String, Object?>>[];
bool collecting = false;

Future<void> main() async {
  if (cover.isEmpty || !File(cover).existsSync()) {
    stderr.writeln('Set MIAOSIC_DIAG_COVER to an existing cover image path.');
    exit(2);
  }
  WidgetsFlutterBinding.ensureInitialized();
  imageCache.maximumSize = 1600;
  imageCache.maximumSizeBytes = 256 * 1024 * 1024;
  SchedulerBinding.instance.addTimingsCallback((values) {
    if (collecting) frames.addAll(values);
  });
  SchedulerBinding.instance.addPersistentFrameCallback((time) {
    if (collecting) ticks.add(time.inMicroseconds);
  });
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: Probe()));
}

Map<String, Object> stats(Iterable<num> input) {
  final values = input.map((v) => v.toDouble()).toList()..sort();
  if (values.isEmpty) return {'n': 0};
  double p(double q) => values[((values.length - 1) * q).round()];
  return {
    'n': values.length,
    'mean': values.reduce((a, b) => a + b) / values.length,
    'p50': p(.5),
    'p95': p(.95),
    'p99': p(.99),
    'max': values.last,
    'over_10ms': values.where((v) => v > 10).length,
    'over_16_67ms': values.where((v) => v > 16.67).length,
    'over_25ms': values.where((v) => v > 25).length,
  };
}

class Probe extends StatefulWidget {
  const Probe({super.key});
  @override
  State<Probe> createState() => ProbeState();
}

class ProbeState extends State<Probe> {
  int stage = 0;
  @override
  void initState() {
    super.initState();
    unawaited(run());
  }

  Future<void> run() async {
    for (int i = 0; i < stageNames.length; i++) {
      if (i > 0) setState(() => stage = i);
      await Future<void>.delayed(const Duration(seconds: 3));
      frames.clear();
      ticks.clear();
      collecting = true;
      await Future<void>.delayed(const Duration(seconds: 10));
      collecting = false;
      if (!mounted) return;
      final intervals = [
        for (int j = 1; j < ticks.length; j++) (ticks[j] - ticks[j - 1]) / 1000,
      ];
      final result = <String, Object?>{
        'stage': stageNames[i],
        'display_refresh_rate': View.of(context).display.refreshRate,
        'device_pixel_ratio': View.of(context).devicePixelRatio,
        'physical_size': [
          View.of(context).physicalSize.width,
          View.of(context).physicalSize.height,
        ],
        'engine_fps': ticks.length > 1
            ? (ticks.length - 1) * 1e6 / (ticks.last - ticks.first)
            : 0,
        'ui_ms': stats(
          frames.map((f) => f.buildDuration.inMicroseconds / 1000),
        ),
        'raster_ms': stats(
          frames.map((f) => f.rasterDuration.inMicroseconds / 1000),
        ),
        'vsync_overhead_ms': stats(
          frames.map((f) => f.vsyncOverhead.inMicroseconds / 1000),
        ),
        'total_ms': stats(frames.map((f) => f.totalSpan.inMicroseconds / 1000)),
        'ticker_interval_ms': stats(intervals),
        'tick_us': ticks.toList(),
        'frame_timings': frames
            .map(
              (f) => {
                'vsync': f.timestampInMicroseconds(ui.FramePhase.vsyncStart),
                'build_start': f.timestampInMicroseconds(
                  ui.FramePhase.buildStart,
                ),
                'build_end': f.timestampInMicroseconds(
                  ui.FramePhase.buildFinish,
                ),
                'raster_start': f.timestampInMicroseconds(
                  ui.FramePhase.rasterStart,
                ),
                'raster_end': f.timestampInMicroseconds(
                  ui.FramePhase.rasterFinish,
                ),
                'layer_cache_bytes': f.layerCacheBytes,
              },
            )
            .toList(),
      };
      results.add(result);
      stdout.writeln(
        'PROBE ${jsonEncode(Map.of(result)
          ..remove('frame_timings')
          ..remove('tick_us'))}',
      );
    }
    await File(output).writeAsString(jsonEncode(results));
    stdout.writeln('PROBE_DONE $output');
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    if (stage > 0) {
      return Scaffold(
        backgroundColor: const Color(0xff173932),
        body: Center(
          child: SimpleRotation(key: ValueKey(stage), solid: stage == 2),
        ),
      );
    }
    final album = AlbumSummary(
      folderPath: '/probe',
      title: 'CD performance probe',
      albumArtist: 'Diagnostic',
      year: 2026,
      trackCount: 12,
      coverArtPath: cover,
    );
    final tracks = List.generate(
      12,
      (i) => Track(
        path: '/probe/$i.flac',
        folderPath: '/probe',
        title: 'Track ${i + 1}',
        artist: 'Diagnostic',
        album: album.title,
        albumArtist: 'Diagnostic',
        trackNumber: i + 1,
        discNumber: 1,
        year: 2026,
        durationMs: 180000,
        sizeBytes: 1,
        modifiedMs: 0,
        coverArtPath: cover,
      ),
    );
    return AlbumPlaybackView(
      album: album,
      tracks: tracks,
      currentTrack: tracks.first,
      playing: true,
      onClose: () {},
      onPrevious: () {},
      onToggle: () {},
      onNext: () {},
      canSwitchPreviousAlbum: false,
      canSwitchNextAlbum: false,
      onSwitchPreviousAlbum: null,
      onSwitchNextAlbum: null,
      onPlayTrack: (_) {},
    );
  }
}

class SimpleRotation extends StatefulWidget {
  const SimpleRotation({super.key, required this.solid});
  final bool solid;
  @override
  State<SimpleRotation> createState() => SimpleRotationState();
}

class SimpleRotationState extends State<SimpleRotation>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: RotationTransition(
      turns: controller,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: 820,
          child: widget.solid
              ? const ColoredBox(color: Color(0xffaaaaaa))
              : ClipOval(
                  child: Image.file(
                    File(cover),
                    fit: BoxFit.cover,
                    cacheWidth: 1640,
                    cacheHeight: 1640,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
        ),
      ),
    ),
  );
}
