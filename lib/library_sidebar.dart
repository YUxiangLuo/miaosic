import 'package:flutter/material.dart';

import 'library_formatters.dart';
import 'library_types.dart';
import 'models.dart';

class LibrarySidebar extends StatelessWidget {
  const LibrarySidebar({
    super.key,
    required this.selected,
    required this.albums,
    required this.playlists,
    required this.scanState,
    required this.musicRoot,
    required this.scanning,
    required this.progress,
    required this.error,
    required this.onEditMusicRoot,
    required this.onRescan,
    required this.onSelected,
  });

  final LibraryView selected;
  final int albums;
  final int playlists;
  final Map<String, Object?>? scanState;
  final String musicRoot;
  final bool scanning;
  final ScanProgress? progress;
  final String? error;
  final VoidCallback onEditMusicRoot;
  final VoidCallback onRescan;
  final ValueChanged<LibraryView> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 212,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.equalizer, color: scheme.onPrimary),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Miaosic',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            for (final view in LibraryView.values)
              _SidebarItem(
                view: view,
                selected: selected == view,
                count: switch (view) {
                  LibraryView.albums => albums,
                  LibraryView.playlists => playlists,
                },
                onTap: () => onSelected(view),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: _LibraryStats(
                scanState: scanState,
                musicRoot: musicRoot,
                scanning: scanning,
                progress: progress,
                error: error,
                onEditMusicRoot: onEditMusicRoot,
                onRescan: onRescan,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.view,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final LibraryView view;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                view.icon,
                size: 20,
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  view.label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              Text(
                count.toString(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryStats extends StatelessWidget {
  const _LibraryStats({
    required this.scanState,
    required this.musicRoot,
    required this.scanning,
    required this.progress,
    required this.error,
    required this.onEditMusicRoot,
    required this.onRescan,
  });

  final Map<String, Object?>? scanState;
  final String musicRoot;
  final bool scanning;
  final ScanProgress? progress;
  final String? error;
  final VoidCallback onEditMusicRoot;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scannedAt = scanState?['scanned_at_ms'] as int?;
    final elapsedMs = scanState?['elapsed_ms'] as int?;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                scanning ? Icons.sync : Icons.storage,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                scanning ? 'Scanning' : 'Library',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Change music folder',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 30,
                  height: 30,
                ),
                onPressed: scanning ? null : onEditMusicRoot,
                icon: const Icon(Icons.edit, size: 17),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            musicRoot,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            scannedAt == null
                ? 'No scan yet'
                : 'Last scan ${formatDate(scannedAt)} · ${formatElapsed(elapsedMs)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (scanning || error != null) ...[
            const SizedBox(height: 10),
            if (scanning) LinearProgressIndicator(value: null, minHeight: 3),
            if (progress != null) ...[
              const SizedBox(height: 6),
              Text(
                '${progress!.tracksParsed} tracks',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                progress!.currentPath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (error != null)
              Text(
                error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: scanning ? null : onRescan,
              icon: scanning
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(scanning ? 'Scanning' : 'Rescan'),
            ),
          ),
        ],
      ),
    );
  }
}
