part of 'album_playback_view.dart';

class _LargeAlbumArtwork extends StatelessWidget {
  const _LargeAlbumArtwork({
    required this.album,
    required this.size,
    required this.transitionDirection,
    required this.active,
    required this.playing,
    required this.onWheel,
  });

  final AlbumSummary album;
  final double size;
  final int transitionDirection;
  final bool active;
  final bool playing;
  final ValueChanged<PointerScrollEvent> onWheel;

  @override
  Widget build(BuildContext context) {
    final artworkSize = size.clamp(260.0, 820.0).roundToDouble();
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          GestureBinding.instance.pointerSignalResolver.register(event, (
            resolvedEvent,
          ) {
            if (resolvedEvent is PointerScrollEvent) {
              onWheel(resolvedEvent);
            }
          });
        }
      },
      child: SizedBox.square(
        dimension: artworkSize,
        child: AnimatedSwitcher(
          duration: _albumCoverTransitionDuration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: _coverTransitionBuilder,
          child: KeyedSubtree(
            key: ValueKey(album.folderPath),
            child: _MorphingAlbumDisc(
              key: const ValueKey('album-morphing-artwork'),
              coverArtPath: album.coverArtPath,
              size: artworkSize,
              active: active,
              playing: playing,
            ),
          ),
        ),
      ),
    );
  }

  Widget _coverTransitionBuilder(Widget child, Animation<double> animation) {
    final entering = child.key == ValueKey(album.folderPath);
    final direction = transitionDirection == 0 ? 1 : transitionDirection;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final offset = Tween<Offset>(
      begin: Offset(entering ? direction * 0.012 : -direction * 0.006, 0),
      end: Offset.zero,
    ).animate(curved);
    return SlideTransition(position: offset, child: child);
  }
}

class _MorphingAlbumDisc extends StatefulWidget {
  const _MorphingAlbumDisc({
    super.key,
    required this.coverArtPath,
    required this.size,
    required this.active,
    required this.playing,
  });

  final String? coverArtPath;
  final double size;
  final bool active;
  final bool playing;

  @override
  State<_MorphingAlbumDisc> createState() => _MorphingAlbumDiscState();
}

class _MorphingAlbumDiscState extends State<_MorphingAlbumDisc>
    with TickerProviderStateMixin {
  late final AnimationController _morphController;
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _morphController = AnimationController(
      vsync: this,
      duration: _albumDiscMorphDuration,
      value: widget.active ? 1 : 0,
    );
    _rotationController = AnimationController(
      vsync: this,
      duration: _albumDiscRotationDuration,
    );
    if (widget.playing) {
      _rotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _MorphingAlbumDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) {
      if (widget.playing) {
        _rotationController.repeat();
      } else {
        _rotationController.stop();
      }
    }

    if (oldWidget.active == widget.active) {
      return;
    }
    if (widget.active) {
      if (widget.playing) {
        _rotationController.repeat();
      }
      _morphController.forward();
    } else {
      _morphController.reverse().then((_) {
        if (mounted && !widget.active) {
          _rotationController.stop();
          _rotationController.reset();
        }
      });
    }
  }

  @override
  void dispose() {
    _morphController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _morphController,
      builder: (context, _) {
        final discProgress = Curves.easeInOutCubic.transform(
          _morphController.value,
        );
        final radius = ui.lerpDouble(14, widget.size / 2, discProgress)!;
        final holeSize = widget.size * 0.22;

        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.36),
                blurRadius: 34,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                RotationTransition(
                  turns: _rotationController,
                  filterQuality: FilterQuality.medium,
                  child: RepaintBoundary(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _AlbumDiscFill(
                          coverArtPath: widget.coverArtPath,
                          size: widget.size,
                        ),
                        if (discProgress > 0)
                          Opacity(
                            key: const ValueKey('album-disc-sheen'),
                            opacity: discProgress,
                            child: const CustomPaint(painter: _DiscPainter()),
                          ),
                      ],
                    ),
                  ),
                ),
                if (discProgress > 0)
                  Center(
                    child: Opacity(
                      opacity: discProgress,
                      child: Transform.scale(
                        scale: 0.72 + discProgress * 0.28,
                        child: _DiscHole(
                          key: const ValueKey('album-disc-hole'),
                          size: holeSize,
                          discSize: widget.size,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DiscHole extends StatelessWidget {
  const _DiscHole({super.key, required this.size, required this.discSize});

  final double size;
  final double discSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.58),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.28),
          width: math.max(2, discSize * 0.008),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.42),
            blurRadius: discSize * 0.04,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: size * 0.34,
          height: size * 0.34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.14),
          ),
        ),
      ),
    );
  }
}

class _AlbumDiscFill extends StatelessWidget {
  const _AlbumDiscFill({required this.coverArtPath, required this.size});

  final String? coverArtPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = coverArtPath;
    if (path == null || path.isEmpty) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            colors: [Color(0xff3a3a3a), Color(0xff111111)],
          ),
        ),
        child: Icon(
          Icons.album,
          size: 96,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      );
    }

    final cacheSize = size.isFinite ? (size * 2).round() : null;
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: cacheSize,
      cacheHeight: cacheSize,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            colors: [Color(0xff3a3a3a), Color(0xff111111)],
          ),
        ),
        child: Icon(
          Icons.album,
          size: 96,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _DiscPainter extends CustomPainter {
  const _DiscPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;

    final sheen = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.white.withValues(alpha: 0.02),
          Colors.white.withValues(alpha: 0.20),
          Colors.white.withValues(alpha: 0.04),
          Colors.black.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.08),
          Colors.white.withValues(alpha: 0.02),
        ],
        stops: const [0.0, 0.12, 0.24, 0.52, 0.74, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sheen);

    final outerRim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, radius * 0.018)
      ..color = Colors.white.withValues(alpha: 0.24);
    canvas.drawCircle(center, radius - outerRim.strokeWidth / 2, outerRim);

    final innerGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(5, radius * 0.045)
      ..color = Colors.white.withValues(alpha: 0.10);
    canvas.drawCircle(center, radius * 0.25, innerGlow);
  }

  @override
  bool shouldRepaint(covariant _DiscPainter oldDelegate) => false;
}
