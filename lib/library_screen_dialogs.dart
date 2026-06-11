import 'dart:async';

import 'package:flutter/material.dart';

import 'library_controller.dart';
import 'library_diff.dart';
import 'models.dart';
import 'playback_controller.dart';
import 'rescan_dialog.dart';
import 'settings_dialog.dart';

Future<void> showLibraryRescanDialog({
  required BuildContext context,
  required LibraryController library,
  required Future<void> Function() onEditMusicRoot,
  required Future<bool> Function() onApply,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AnimatedBuilder(
        animation: library,
        builder: (context, _) {
          return RescanDialog(
            stateListenable: library.rescanState,
            trackCoverCacheListenable: library.trackCoverCacheListenable,
            musicRoot: library.musicRoot,
            canEditMusicRoot: library.canChangeMusicRoot,
            onEditMusicRoot: onEditMusicRoot,
            onApply: onApply,
            onScanLibrary: () => unawaited(library.scanLibrary()),
            onRescan: () => library.startRescanDiff(),
            onFullRescan: () => library.startRescanDiff(full: true),
          );
        },
      );
    },
  );
}

Future<String?> showMusicRootDialog(
  BuildContext context, {
  required String musicRoot,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) {
      return _MusicRootDialog(musicRoot: musicRoot);
    },
  );
}

Future<bool> showLargeDeletionConfirmation(
  BuildContext context,
  DeletionRisk risk,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Confirm large removal'),
        content: Text(
          'This refresh would remove ${risk.removedCount} tracks '
          '(${(risk.removedRatio * 100).toStringAsFixed(1)}% of the current library). '
          'Check that the drive is mounted and the music root is correct before applying.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apply anyway'),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

Future<void> showLibrarySettingsDialog({
  required BuildContext context,
  required LibraryController library,
  required PlaybackController playback,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      return AnimatedBuilder(
        animation: Listenable.merge([library, playback]),
        builder: (context, _) {
          return SettingsDialog(
            llmSettings: library.llmSettings,
            onSaveLlmSettings: library.saveLlmSettings,
            audioOutputSettings: library.audioOutputSettings,
            audioDevices: playback.audioDevices,
            activeAudioDevice: playback.audioDevice,
            audioOutputWarning: playback.audioOutputWarning,
            audioOutputError: playback.audioOutputError,
            onSaveAudioOutputSettings: (settings) async {
              await playback.applyAudioOutputSettings(settings);
              await library.saveAudioOutputSettings(settings);
            },
          );
        },
      );
    },
  );
}

class _MusicRootDialog extends StatefulWidget {
  const _MusicRootDialog({required this.musicRoot});

  final String musicRoot;

  @override
  State<_MusicRootDialog> createState() => _MusicRootDialogState();
}

class _MusicRootDialogState extends State<_MusicRootDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.musicRoot);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Music folder'),
      content: SizedBox(
        width: 520,
        child: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Folder path',
            hintText: '~/Music',
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save and rescan')),
      ],
    );
  }

  void _submit() {
    final path = normalizeMusicRootPath(_controller.text);
    if (path.isEmpty) {
      return;
    }
    Navigator.of(context).pop(path);
  }
}
