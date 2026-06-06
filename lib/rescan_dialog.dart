part of 'main.dart';

class _RescanUiState {
  const _RescanUiState({
    required this.phase,
    this.message = '',
    this.progress,
    this.diff,
    this.error,
  });

  final _RescanPhase phase;
  final String message;
  final ScanProgress? progress;
  final LibraryDiff? diff;
  final String? error;

  _RescanUiState copyWith({
    _RescanPhase? phase,
    String? message,
    ScanProgress? progress,
    LibraryDiff? diff,
    String? error,
  }) {
    return _RescanUiState(
      phase: phase ?? this.phase,
      message: message ?? this.message,
      progress: progress,
      diff: diff ?? this.diff,
      error: error,
    );
  }
}

class _RescanDialog extends StatelessWidget {
  const _RescanDialog({
    required this.stateListenable,
    required this.onApply,
    required this.onRescan,
    required this.onFullRescan,
  });

  final ValueListenable<_RescanUiState> stateListenable;
  final Future<void> Function() onApply;
  final VoidCallback onRescan;
  final VoidCallback onFullRescan;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_RescanUiState>(
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
              onPressed: state.phase == _RescanPhase.applying
                  ? null
                  : () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: busy ? null : onRescan,
              child: Text(
                state.phase == _RescanPhase.error ? 'Retry' : 'Rescan',
              ),
            ),
            TextButton(
              onPressed: busy ? null : onFullRescan,
              child: const Text('Full rescan'),
            ),
            FilledButton(
              onPressed:
                  state.phase == _RescanPhase.ready &&
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

  final _RescanUiState state;

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

  IconData _phaseIcon(_RescanPhase phase) {
    return switch (phase) {
      _RescanPhase.ready => Icons.fact_check,
      _RescanPhase.done => Icons.check_circle,
      _RescanPhase.error => Icons.error,
      _RescanPhase.applying => Icons.save,
      _ => Icons.sync,
    };
  }

  String _phaseLabel(_RescanPhase phase) {
    return switch (phase) {
      _RescanPhase.idle => 'Ready to rescan',
      _RescanPhase.loadingDatabase => 'Loading current library snapshot',
      _RescanPhase.scanning => 'Scanning local files',
      _RescanPhase.diffing => 'Comparing scan with database',
      _RescanPhase.ready => 'Review changes before applying',
      _RescanPhase.applying => 'Applying library changes',
      _RescanPhase.done => 'Library refreshed',
      _RescanPhase.error => 'Rescan failed',
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

  final _RescanUiState state;

  @override
  Widget build(BuildContext context) {
    final diff = state.diff;
    if (state.phase == _RescanPhase.error) {
      return const _EmptyState(message: 'Fix the error and retry the scan');
    }
    if (diff == null) {
      return const _EmptyState(
        message: 'Scanning will continue even if this window is closed',
      );
    }
    if (!diff.hasChanges) {
      return const _EmptyState(message: 'Library is already up to date');
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
      return const _EmptyState(message: 'No tracks in this category');
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
