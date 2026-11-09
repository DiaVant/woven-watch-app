import 'package:flutter/material.dart';
import 'package:trackapp/demo/demo_class_service.dart';
import 'package:trackapp/demo/demo_script.dart';
import 'package:trackapp/pages/init_page.dart';
import 'package:trackapp/services/alert_manager.dart';
import 'package:trackapp/services/local_store.dart';
import 'package:trackapp/services/store_backend.dart';
import 'package:trackapp/services/watch_ble_service.dart';
import 'package:trackapp/services/watch_settings_service.dart';
import 'package:trackapp/theme/app_theme.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

//try the app with no account and no watch. nothing touches firebase or disk
class DemoMode {
  DemoMode._();

  static final ValueNotifier<bool> active = ValueNotifier(false);

  static bool get isActive => active.value;

  static DemoClassService? _classes;
  static DemoFeed? _feed;
  static WatchSettingsService? _savedSettings;

  @visibleForTesting
  static DemoFeed? get feed => _feed;

  static DemoClassService get classService =>
      _classes ?? (throw StateError('Demo is not running.'));

  static void start() {
    if (isActive) return;
    final manager = AlertManager.instance;
    _savedSettings = manager.settingsService;
    manager.reset();
    //settings and quiet stay in AlertManager's memory
    manager.attachSettings(null);

    final store = LocalStore(backend: MemoryBackend());
    LocalStore.use(store);
    store.load();
    store.startClassSession(demoClassId, demoStudents.keys);

    _classes = DemoClassService([demoClass()]);
    WatchBleService.instance.addSimulatedWatches(demoStudents.keys);
    _feed = DemoFeed()..start();
    active.value = true;
  }

  static void exit() {
    if (!isActive) return;
    _feed?.stop();
    _feed = null;
    WatchBleService.instance.removeSimulatedWatches();
    final manager = AlertManager.instance;
    manager.reset();
    manager.attachSettings(_savedSettings);
    _savedSettings = null;
    LocalStore.use(null);
    _classes = null;
    active.value = false;
  }
}

//leave from any screen: back to the first page, then forget everything
void leaveDemo() {
  appNavigatorKey.currentState?.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const InitPage()),
    (route) => false,
  );
  DemoMode.exit();
}

//strip above every screen so screenshots can't pass as real students
Widget demoFrame(BuildContext context, Widget? child) {
  final app = child ?? const SizedBox.shrink();
  return ValueListenableBuilder<bool>(
    valueListenable: DemoMode.active,
    builder: (context, on, _) {
      if (!on) return app;
      return Column(
        children: [
          Material(
            color: appInk,
            child: Padding(
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
              child: SizedBox(
                height: 34,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.science_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Demo · made-up students',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: leaveDemo,
                      child: const Text(
                        'Exit demo',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: app,
            ),
          ),
        ],
      );
    },
  );
}
