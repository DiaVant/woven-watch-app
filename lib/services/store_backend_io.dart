import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

import 'store_backend.dart';

StoreBackend createDefaultBackend() => FileStoreBackend.appDocuments();

class FileStoreBackend implements StoreBackend {
  //tests pass a temp dir
  FileStoreBackend(Directory directory) : _resolve = (() async => directory);

  FileStoreBackend.appDocuments()
      : _resolve = (() async {
          try {
            final docs = await getApplicationDocumentsDirectory();
            return Directory('${docs.path}/wovenwatch');
          } catch (e) {
            //no documents dir (unit tests), so memory only
            debugPrint('LocalStore: no storage directory ($e)');
            return null;
          }
        });

  final Future<Directory?> Function() _resolve;
  Future<Directory?>? _directory;

  Future<File?> _file(String name) async {
    final dir = await (_directory ??= _resolve());
    if (dir == null) return null;
    try {
      await dir.create(recursive: true);
      return File('${dir.path}/$name.json');
    } catch (e) {
      debugPrint('LocalStore: cannot use ${dir.path} ($e)');
      return null;
    }
  }

  @override
  Future<String?> read(String name) async {
    final file = await _file(name);
    if (file == null) return null;
    try {
      return await file.exists() ? await file.readAsString() : null;
    } catch (e) {
      debugPrint('LocalStore: could not read $name.json ($e)');
      return null;
    }
  }

  @override
  Future<void> write(String name, String contents) async {
    final file = await _file(name);
    if (file == null) return;
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(file.path); //atomic on the same filesystem
  }

  @override
  Future<void> delete(String name) async {
    final file = await _file(name);
    if (file != null && await file.exists()) await file.delete();
  }
}
