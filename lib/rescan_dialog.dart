import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'library_diff.dart';
import 'library_types.dart';
import 'library_widgets.dart';
import 'models.dart';

class RescanUiState {
  const RescanUiState({
    required this.phase,
    this.message = '',
    this.progress,
    this.diff,
    this.error,
  });

  final RescanPhase phase;
  final String message;
  final ScanProgress? progress;
  final LibraryDiff? diff;
  final String? error;

  RescanUiState copyWith({
    RescanPhase? phase,
    String? message,
    ScanProgress? progress,
    LibraryDiff? diff,
    String? error,
  }) {
    return RescanUiState(
      phase: phase ?? this.phase,
      message: message ?? this.message,
      progress: progress,
      diff: diff ?? this.diff,
      error: error,
    );
  }
}

class RescanDialog extends StatelessWidget {
  const RescanDialog({
    super.key,
    required this.stateListenable,
    required this.onApply,
    required this.onRescan,
    required this.onFullRescan,
  });

  final ValueListenable<RescanUiState> stateListenable;
  final Future<void> Function() onApply;
  final VoidCallback onRescan;
  final VoidCallback onFullRescan;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RescanUiState>(
      valueListenable: stateListenable,
      builder: (context, state, _) {
        final busy = state.phase.isBusy;
        final diff = state.diff;
        return AlertDialog(
          title: const Text('Rescan library'),
          content: SizedBox(
            width: 760,
            height: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RescanStatus(state: state),
                const SizedBox(height: 16),
                Expanded(child: _RescanBody(state: state)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: state.phase == RescanPhase.applying
                  ? null
                  : () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: busy ? null : onRescan,
              child: Text(
                state.phase == RescanPhase.error ? 'Retry' : 'Rescan',
              ),
            ),
            TextButton(
              onPressed: busy ? null : onFullRescan,
              child: const Text('Full rescan'),
            ),
            FilledButton(
              onPressed:
                  state.phase == RescanPhase.ready &&
                      !busy &&
                      diff != null &&
                      diff.hasChanges
                  ? onApply
                  : null,
              child: const Text('Apply'),
            ),
          ],
        );
      },
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_phaseIcon(state.phase), color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                state.message.isEmpty
                    ? _phaseLabel(state.phase)
                    : state.message,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        if (state.phase.isBusy) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(value: null, minHeight: 3),
        ],
        if (progress != null) ...[
          const SizedBox(height: 8),
          Text(
            '${progress.tracksParsed} tracks · ${progress.currentPath}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (diff != null) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              _DiffStat(label: 'Added', value: diff.added.length),
              _DiffStat(label: 'Removed', value: diff.removed.length),
              _DiffStat(label: 'Modified', value: diff.modified.length),
              _DiffStat(label: 'Unchanged', value: diff.unchangedCount),
            ],
          ),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 10),
          Text(state.error!, style: TextStyle(color: scheme.error)),
        ],
      ],
    );
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

class _DiffStat extends StatelessWidget {
  const _DiffStat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value.toString(),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _RescanBody extends StatelessWidget {
  const _RescanBody({required this.state});

  final RescanUiState state;

  @override
  Widget build(BuildContext context) {
    final diff = state.diff;
    if (state.phase == RescanPhase.error) {
      return const EmptyState(message: 'Fix the error and retry the scan');
    }
    if (diff == null) {
      return const EmptyState(
        message: 'Scanning will continue even if this window is closed',
      );
    }
    if (!diff.hasChanges) {
      return const EmptyState(message: 'Library is already up to date');
    }
    return DefaultTabController(
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
                _ChangeList(changes: diff.added),
                _ChangeList(changes: diff.removed),
                _ChangeList(changes: diff.modified),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangeList extends StatelessWidget {
  const _ChangeList({required this.changes});

  final List<TrackChange> changes;

  @override
  Widget build(BuildContext context) {
    if (changes.isEmpty) {
      return const EmptyState(message: 'No tracks in this category');
    }
    return ListView.builder(
      itemCount: changes.length,
      itemBuilder: (context, index) {
        final change = changes[index];
        final track = change.newTrack ?? change.oldTrack!;
        return ListTile(
          dense: true,
          leading: Icon(_changeIcon(change.reason)),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${track.artist} · ${track.album.isEmpty ? track.folderName : track.album}\n${track.path}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  IconData _changeIcon(TrackChangeReason reason) {
    return switch (reason) {
      TrackChangeReason.added => Icons.add_circle,
      TrackChangeReason.removed => Icons.remove_circle,
      TrackChangeReason.fileChanged => Icons.change_circle,
    };
  }
}
