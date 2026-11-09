import 'store_backend_io.dart'
    if (dart.library.js_interop) 'store_backend_web.dart' as platform;

//reads return null for a missing file instead of throwing
abstract class StoreBackend {
  Future<String?> read(String name);

  //atomic, never half written
  Future<void> write(String name, String contents);

  //no error if it isn't there
  Future<void> delete(String name);

  //files on phone/desktop, localStorage on web
  factory StoreBackend.platformDefault() => platform.createDefaultBackend();
}
