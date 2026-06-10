import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'artwork_resolver.dart';
import 'library_diff.dart';
import 'library_formatters.dart';
import 'library_types.dart';
import 'library_widgets.dart';

class RescanDialog extends StatefulWidget {
  const RescanDialog({
    super.key,
    required this.stateListenable,
    required this.trackCoverCacheListenable,
    required this.musicRoot,
    required this.canEditMusicRoot,
    required this.onEditMusicRoot,
    required this.onApply,
    required this.onRescan,
    required this.onFullRescan,
  });

  final ValueListenable<RescanUiState> stateListenable;
  final ValueListenable<Map<String, String?>> trackCoverCacheListenable;
  final String musicRoot;
  final bool canEditMusicRoot;
  final VoidCallback onEditMusicRoot;
  final Future<bool> Function() onApply;
  final VoidCallback onRescan;
  final VoidCallback onFullRescan;

  @override
  State<RescanDialog> createState() => _RescanDialogState();
}

class _RescanDialogState extends State<RescanDialog> {
  Future<void> _applyAndClose() async {
    final applied = await widget.onApply();
    if (mounted && applied) {
      Navigator.of(context).pop();
    }
  }

  void _close() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RescanUiState>(
      valueListenable: widget.stateListenable,
      builder: (context, state, _) {
        final busy = state.phase.isBusy;
        final applying = state.phase == RescanPhase.applying;
        final diff = state.diff;
        final canApply =
            state.phase == RescanPhase.ready &&
            !busy &&
            diff != null &&
            diff.hasChanges;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (!applying) {
                _close();
              }
            },
          },
          child: Focus(
            autofocus: true,
            child: AlertDialog(
              title: Row(
                children: [
                  const Expanded(child: Text('Rescan library')),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: applying ? null : _close,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              content: SizedBox(
                width: 840,
                height: 600,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RescanStatus(state: state),
                    const SizedBox(height: 14),
                    _MusicRootPanel(
                      musicRoot: widget.musicRoot,
                      canEdit: widget.canEditMusicRoot && !busy,
                      onEdit: widget.onEditMusicRoot,
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: _RescanBody(
                        state: state,
                        trackCoverCacheListenable:
                            widget.trackCoverCacheListenable,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    _RescanActions(
                      busy: busy,
                      canApply: canApply,
                      phase: state.phase,
                      onRescan: widget.onRescan,
                      onFullRescan: widget.onFullRescan,
                      onApply: _applyAndClose,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RescanActions extends StatelessWidget {
  const _RescanActions({
    required this.busy,
    required this.canApply,
    required this.phase,
    required this.onRescan,
    required this.onFullRescan,
    required this.onApply,
  });

  final bool busy;
  final bool canApply;
  final RescanPhase phase;
  final VoidCallback onRescan;
  final VoidCallback onFullRescan;
  final Future<void> Function() onApply;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TextButton.icon(
          onPressed: busy ? null : onFullRescan,
          icon: const Icon(Icons.restart_alt, size: 18),
          label: const Text('Full rescan'),
        ),
        const Spacer(),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          onPressed: busy ? null : onRescan,
          icon: Icon(
            phase == RescanPhase.error ? Icons.refresh : Icons.sync,
            size: 18,
          ),
          label: Text(phase == RescanPhase.error ? 'Retry' : 'Rescan'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: canApply ? onApply : null,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Apply'),
        ),
      ],
    );
  }
}

class _MusicRootPanel extends StatelessWidget {
  const _MusicRootPanel({
    required this.musicRoot,
    required this.canEdit,
    required this.onEdit,
  });

  final String musicRoot;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Icon(Icons.storage, size: 19, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Music folder',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    musicRoot,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Change music folder',
              onPressed: canEdit ? onEdit : null,
              icon: const Icon(Icons.edit, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _RescanStatus extends StatelessWidget {
  const _RescanStatus({required this.state});

  final RescanUiState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = state.progress;
    final diff = state.diff;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _phaseColor(
                      scheme,
                      state.phase,
                    ).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _phaseIcon(state.phase),
                    size: 19,
                    color: _phaseColor(scheme, state.phase),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.message.isEmpty
                            ? _phaseLabel(state.phase)
                            : state.message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          '${progress.tracksParsed} tracks · ${progress.currentPath}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (state.phase.isBusy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(value: null, minHeight: 3),
            ],
            if (diff != null) ...[
              const SizedBox(height: 14),
              _DiffStats(diff: diff),
            ],
            if (state.error != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(error: state.error!),
            ],
          ],
        ),
      ),
    );
  }

  Color _phaseColor(ColorScheme scheme, RescanPhase phase) {
    return switch (phase) {
      RescanPhase.ready || RescanPhase.done => scheme.primary,
      RescanPhase.error => scheme.error,
      RescanPhase.applying => scheme.tertiary,
      _ => scheme.primary,
    };
  }

  IconData _phaseIcon(RescanPhase phase) {
    return switch (phase) {
      RescanPhase.ready => Icons.fact_check,
      RescanPhase.done => Icons.check_circle,
      RescanPhase.error => Icons.error,
      RescanPhase.applying => Icons.save,
      _ => Icons.sync,
    };
  }

  String _phaseLabel(RescanPhase phase) {
    return switch (phase) {
      RescanPhase.idle => 'Ready to rescan',
      RescanPhase.loadingDatabase => 'Loading current library snapshot',
      RescanPhase.scanning => 'Scanning local files',
      RescanPhase.diffing => 'Comparing scan with database',
      RescanPhase.ready => 'Review changes before applying',
      RescanPhase.applying => 'Applying library changes',
      RescanPhase.done => 'Library refreshed',
      RescanPhase.error => 'Rescan failed',
    };
  }
}

class _DiffStats extends StatelessWidget {
  const _DiffStats({required this.diff});

  final LibraryDiff diff;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        _DiffStat(
          label: 'Added',
          value: diff.added.length,
          icon: Icons.add_circle,
          color: scheme.tertiary,
        ),
        const SizedBox(width: 8),
        _DiffStat(
          label: 'Removed',
          value: diff.removed.length,
          icon: Icons.remove_circle,
          color: scheme.error,
        ),
        const SizedBox(width: 8),
        _DiffStat(
          label: 'Modified',
          value: diff.modified.length,
          icon: Icons.change_circle,
          color: scheme.primary,
        ),
        const SizedBox(width: 8),
        _DiffStat(
          label: 'Unchanged',
          value: diff.unchangedCount,
          icon: Icons.check_circle,
          color: scheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _DiffStat extends StatelessWidget {
  const _DiffStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value.toString(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: scheme.onSurface,
                    ),
                  ),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        error,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onErrorContainer),
      ),
    );
  }
}

class _RescanBody extends StatelessWidget {
  const _RescanBody({
    required this.state,
    required this.trackCoverCacheListenable,
  });

  final RescanUiState state;
  final ValueListenable<Map<String, String?>> trackCoverCacheListenable;

  @override
  Widget build(BuildContext context) {
    final diff = state.diff;
    if (state.phase == RescanPhase.error) {
      return const _EmptyReview(
        icon: Icons.error_outline,
        title: 'Rescan failed',
        subtitle: 'Fix the error and retry the scan',
      );
    }
    if (state.phase == RescanPhase.idle && diff == null) {
      return const _EmptyReview(
        icon: Icons.storage,
        title: 'Ready to rescan',
        subtitle: 'Press Rescan to compare the library with local files',
      );
    }
    if (diff == null) {
      return const _EmptyReview(
        icon: Icons.sync,
        title: 'Scanning library',
        subtitle: 'The refresh continues while this window is open',
      );
    }
    if (!diff.hasChanges) {
      return _EmptyReview(
        icon: Icons.check_circle_outline,
        title: 'Library is up to date',
        subtitle: '${diff.unchangedCount} tracks checked',
      );
    }
    return ValueListenableBuilder<Map<String, String?>>(
      valueListenable: trackCoverCacheListenable,
      builder: (context, trackCoverCache, _) {
        return _ChangeReview(diff: diff, trackCoverCache: trackCoverCache);
      },
    );
  }
}

class _ChangeReview extends StatelessWidget {
  const _ChangeReview({required this.diff, required this.trackCoverCache});

  final LibraryDiff diff;
  final Map<String, String?> trackCoverCache;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            TabBar(
              tabs: [
                Tab(text: 'Added ${diff.added.length}'),
                Tab(text: 'Removed ${diff.removed.length}'),
                Tab(text: 'Modified ${diff.modified.length}'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _ChangeList(
                    changes: diff.added,
                    trackCoverCache: trackCoverCache,
                  ),
                  _ChangeList(
                    changes: diff.removed,
                    trackCoverCache: trackCoverCache,
                  ),
                  _ChangeList(
                    changes: diff.modified,
                    trackCoverCache: trackCoverCache,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangeList extends StatelessWidget {
  const _ChangeList({required this.changes, required this.trackCoverCache});

  final List<TrackChange> changes;
  final Map<String, String?> trackCoverCache;

  @override
  Widget build(BuildContext context) {
    if (changes.isEmpty) {
      return const _EmptyReview(
        icon: Icons.inbox,
        title: 'No tracks',
        subtitle: 'Nothing in this category',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      itemCount: changes.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        return _ChangeTrackRow(
          change: changes[index],
          artworkPath: resolveChangeArtwork(changes[index], trackCoverCache),
        );
      },
    );
  }
}

class _ChangeTrackRow extends StatelessWidget {
  const _ChangeTrackRow({required this.change, required this.artworkPath});

  final TrackChange change;
  final String? artworkPath;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final track = change.newTrack ?? change.oldTrack!;
    final color = _changeColor(scheme, change.reason);
    return SizedBox(
      height: 82,
      child: Row(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Artwork(
                path: artworkPath,
                size: 58,
                icon: Icons.music_note,
                radius: 7,
              ),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                child: Icon(
                  _changeIcon(change.reason),
                  size: 13,
                  color: scheme.surface,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  '${track.artist} · ${track.album.isEmpty ? track.folderName : track.album}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 3),
                Text(
                  track.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 54,
            child: Text(
              formatDurationMs(track.durationMs),
              textAlign: TextAlign.right,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Color _changeColor(ColorScheme scheme, TrackChangeReason reason) {
    return switch (reason) {
      TrackChangeReason.added => scheme.tertiary,
      TrackChangeReason.removed => scheme.error,
      TrackChangeReason.fileChanged => scheme.primary,
    };
  }

  IconData _changeIcon(TrackChangeReason reason) {
    return switch (reason) {
      TrackChangeReason.added => Icons.add,
      TrackChangeReason.removed => Icons.remove,
      TrackChangeReason.fileChanged => Icons.sync,
    };
  }
}

class _EmptyReview extends StatelessWidget {
  const _EmptyReview({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: scheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
