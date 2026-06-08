import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'library_widgets.dart';
import 'models.dart';

const _albumCaseRadius = 8.0;

class AlbumGrid extends StatelessWidget {
  const AlbumGrid({
    super.key,
    required this.albums,
    required this.tracksByFolder,
    required this.onOpen,
  });

  final List<AlbumSummary> albums;
  final Map<String, List<Track>> tracksByFolder;
  final void Function(AlbumSummary album, List<Track> tracks) onOpen;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return const EmptyState(message: 'No album folders detected');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const gridPadding = 26.0;
        const crossAxisSpacing = 30.0;
        const mainAxisSpacing = 36.0;
        final columns = math.min(6, math.max(2, (width / 220).floor()));
        final usableWidth =
            width - (gridPadding * 2) - (crossAxisSpacing * (columns - 1));
        final tileWidth = math.max(0.0, usableWidth / columns);
        return GridView.builder(
          padding: const EdgeInsets.all(gridPadding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: mainAxisSpacing,
            mainAxisExtent: tileWidth,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            final tracks = tracksByFolder[album.folderPath] ?? const <Track>[];
            return _AlbumTile(
              album: album,
              onTap: tracks.isEmpty ? null : () => onOpen(album, tracks),
            );
          },
        );
      },
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({required this.album, required this.onTap});

  final AlbumSummary album;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(_albumCaseRadius),
      onTap: onTap,
      child: _AlbumJewelCase(coverArtPath: album.coverArtPath),
    );
  }
}

class _AlbumJewelCase extends StatelessWidget {
  const _AlbumJewelCase({required this.coverArtPath});

  final String? coverArtPath;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_albumCaseRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.56),
            blurRadius: 1,
            offset: const Offset(-1, -1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_albumCaseRadius),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.maxWidth;
            final leftEdgeWidth = math.max(6.0, side * 0.040);
            final edgeWidth = math.max(3.0, side * 0.018);
            return Stack(
              fit: StackFit.expand,
              children: [
                Artwork(
                  path: coverArtPath,
                  size: double.infinity,
                  icon: Icons.album,
                  radius: 0,
                ),
                const _PlasticShellTint(),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: leftEdgeWidth,
                  child: const _SubtleCaseLeftEdge(),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: edgeWidth,
                  child: const _CaseRightEdge(),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: edgeWidth,
                  child: const _CaseBottomEdge(),
                ),
                const _CaseBottomHighlight(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlasticShellTint extends StatelessWidget {
  const _PlasticShellTint();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withValues(alpha: 0.42)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.18),
            Colors.white.withValues(alpha: 0.05),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.045),
          ],
          stops: const [0, 0.34, 0.68, 1],
        ),
      ),
    );
  }
}

class _SubtleCaseLeftEdge extends StatelessWidget {
  const _SubtleCaseLeftEdge();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Colors.black.withValues(alpha: 0.035)),
              ),
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.22),
                  Colors.white.withValues(alpha: 0.06),
                  Colors.black.withValues(alpha: 0.035),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 3,
          top: 0,
          bottom: 0,
          width: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
        ),
      ],
    );
  }
}

class _CaseRightEdge extends StatelessWidget {
  const _CaseRightEdge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.10)],
        ),
      ),
    );
  }
}

class _CaseBottomEdge extends StatelessWidget {
  const _CaseBottomEdge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.10)],
        ),
      ),
    );
  }
}

class _CaseBottomHighlight extends StatelessWidget {
  const _CaseBottomHighlight();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: 18,
            right: 18,
            bottom: 12,
            height: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
