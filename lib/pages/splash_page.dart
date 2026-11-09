import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:trackapp/pages/init_page.dart';
import 'package:trackapp/pages/main_navigation_page.dart';
import 'package:trackapp/theme/app_theme.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
 //safer for stateful, but less optimal 
  @override
  State<SplashPage> createState() => SplashPageState();

}

class SplashPageState extends State<SplashPage> {
  void navigateToInitPage() {

    final User? user = FirebaseAuth.instance.currentUser;

    Navigator.pushReplacement(
      context, 
      MaterialPageRoute(builder: (context) => user != null ? MainNavigationPage() : InitPage())
    );
  }

  @override
  Widget build(BuildContext context) {
    Future.delayed(
      Duration(seconds: 3),
      navigateToInitPage
    );

    return Scaffold(
      body: Center(
        child: AppLogo(size: 128),
      ),
    );
  }
}
