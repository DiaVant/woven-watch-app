import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:trackapp/pages/splash_page.dart';
import 'package:trackapp/services/alert_manager.dart';
import 'package:trackapp/services/local_data_mover.dart';
import 'package:trackapp/services/watch_settings_service.dart';
import 'package:trackapp/theme/app_theme.dart';
import 'firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform
  );
  //phones keep a disk cache so settings load with no signal and offline
  //writes are queued. web has no disk cache
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android)) {
    FirebaseDatabase.instance.setPersistenceEnabled(true);
  }
  //alert settings + quiet sync from firebase
  AlertManager.instance.attachSettings(WatchSettingsService());
  //old settings saved on this device go up to whoever signs in
  final mover = LocalDataMover();
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) mover.run(user.uid);
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: appIndigo,
          primary: appIndigo,
          secondary: appGold,
          tertiary: appBlue,
          surface: appSoftGray,
        ),
        scaffoldBackgroundColor: appSoftGray,
        appBarTheme: const AppBarTheme(
          backgroundColor: appIndigo,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: appIndigo,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: appBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: appIndigo, width: 2),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: appIndigo,
          unselectedItemColor: appMuted,
        ),
        useMaterial3: true,
      ),
      home: SplashPage(),
    );
  }
}
