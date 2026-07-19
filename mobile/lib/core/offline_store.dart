import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'models.dart';

typedef DownloadProgress = void Function(int completed, int total);

class OfflineStore {
  static const _downloadedKey = 'downloaded_book_ids';

  Future<Directory> _bookDirectory(int bookId) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/offline/book-$bookId');
    await directory.create(recursive: true);
    return directory;
  }

  Future<Set<int>> downloadedBookIds() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_downloadedKey) ?? const [])
        .map(int.parse)
        .toSet();
  }

  Future<OfflineManifestData?> load(int bookId) async {
    final directory = await _bookDirectory(bookId);
    final file = File('${directory.path}/manifest.json');
    if (!await file.exists()) return null;
    try {
      return OfflineManifestData.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<OfflineManifestData> download(
    ApiClient api,
    OfflineManifestData manifest, {
    DownloadProgress? onProgress,
  }) async {
    final directory = await _bookDirectory(manifest.bookId);
    final assets = <({String url, String name, String? sha})>[];
    if (manifest.coverUrl != null) {
      assets.add((url: manifest.coverUrl!, name: 'cover.webp', sha: null));
    }
    for (final page in manifest.pages) {
      assets.add((url: page.imageUrl, name: 'page-${page.id}.webp', sha: null));
      assets.add((
        url: page.thumbnailUrl,
        name: 'page-${page.id}-thumb.webp',
        sha: null,
      ));
      for (final entry in page.audio.entries) {
        final extension = entry.value.mimeType == 'audio/wav' ? 'wav' : 'mp3';
        assets.add((
          url: entry.value.url,
          name: 'page-${page.id}-${entry.key}.$extension',
          sha: entry.value.sha256,
        ));
      }
    }
    var completed = 0;
    for (final asset in assets) {
      final bytes = await api.getBytes(asset.url);
      if (asset.sha != null && sha256.convert(bytes).toString() != asset.sha) {
        throw ApiException('离线音频校验失败，请重试');
      }
      final target = File('${directory.path}/${asset.name}');
      await target.writeAsBytes(bytes, flush: true);
      final localUrl = target.uri.toString();
      if (asset.name == 'cover.webp') {
        manifest.coverUrl = localUrl;
      }
      for (final page in manifest.pages) {
        if (asset.name == 'page-${page.id}.webp') {
          page.imageUrl = localUrl;
        }
        if (asset.name == 'page-${page.id}-thumb.webp') {
          page.thumbnailUrl = localUrl;
        }
        for (final entry in page.audio.entries) {
          if (asset.url == entry.value.url) {
            page.audio[entry.key] = AudioAssetData(
              language: entry.value.language,
              url: localUrl,
              mimeType: entry.value.mimeType,
              sha256: entry.value.sha256,
            );
          }
        }
      }
      completed++;
      onProgress?.call(completed, assets.length);
    }
    await File(
      '${directory.path}/manifest.json',
    ).writeAsString(jsonEncode(manifest.toJson()), flush: true);
    final preferences = await SharedPreferences.getInstance();
    final ids = await downloadedBookIds();
    ids.add(manifest.bookId);
    await preferences.setStringList(
      _downloadedKey,
      ids.map((item) => '$item').toList(),
    );
    return manifest;
  }

  Future<void> remove(int bookId) async {
    final directory = await _bookDirectory(bookId);
    if (await directory.exists()) await directory.delete(recursive: true);
    final preferences = await SharedPreferences.getInstance();
    final ids = await downloadedBookIds();
    ids.remove(bookId);
    await preferences.setStringList(
      _downloadedKey,
      ids.map((item) => '$item').toList(),
    );
  }
}
