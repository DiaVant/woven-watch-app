import 'dart:js_interop';

import 'package:flutter/foundation.dart' show debugPrint;

import 'store_backend.dart';

StoreBackend createDefaultBackend() => LocalStorageBackend();

@JS('localStorage')
external _Storage get _localStorage;

extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

//localStorage on web until the app runs on a phone
class LocalStorageBackend implements StoreBackend {
  static String _key(String name) => 'wovenwatch/$name.json';

  @override
  Future<String?> read(String name) async {
    try {
      return _localStorage.getItem(_key(name));
    } catch (e) {
      debugPrint('LocalStore: could not read $name from localStorage ($e)');
      return null;
    }
  }

  @override
  Future<void> write(String name, String contents) async {
    _localStorage.setItem(_key(name), contents);
  }

  @override
  Future<void> delete(String name) async {
    _localStorage.removeItem(_key(name));
  }
}
