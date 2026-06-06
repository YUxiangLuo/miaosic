// ignore_for_file: avoid_print

import 'package:miaosic/models.dart';
import 'package:miaosic/music_scanner.dart';

Future<void> main(List<String> args) async {
  final root = args.isEmpty ? defaultMusicRoot : args.first;
  final scanner = MusicScanner();
  final result = await scanner.scan(
    root,
    onProgress: (progress) {
      if (progress.tracksParsed % 250 == 0) {
        print(
          'parsed=${progress.tracksParsed} current=${progress.currentPath}',
        );
      }
    },
  );

  final albumFolders = result.folders
      .where((folder) => folder.kind == FolderKind.album)
      .length;
  final playlistFolders = result.folders
      .where((folder) => folder.kind == FolderKind.playlist)
      .length;
  final mixedFolders = result.folders
      .where((folder) => folder.kind == FolderKind.mixed)
      .length;

  print('root=${result.rootPath}');
  print('tracks=${result.tracks.length}');
  print('folders=${result.folders.length}');
  print('album_folders=$albumFolders');
  print('playlist_folders=$playlistFolders');
  print('mixed_folders=$mixedFolders');
  print('albums=${result.albums.length}');
  print('elapsed=${result.elapsed.inMilliseconds}ms');
  print('');
  print('Largest playlist-like folders:');
  final playlists =
      result.folders
          .where((folder) => folder.kind == FolderKind.playlist)
          .toList()
        ..sort((a, b) => b.trackCount.compareTo(a.trackCount));
  for (final folder in playlists.take(12)) {
    print(
      '${folder.trackCount.toString().padLeft(4)}  '
      '${folder.name}  '
      'albums=${folder.albumCount} artists=${folder.artistCount}',
    );
  }
}
