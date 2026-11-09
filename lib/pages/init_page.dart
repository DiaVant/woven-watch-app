import 'package:flutter/material.dart';
import 'package:trackapp/pages/login_page.dart';
import 'package:trackapp/pages/onboarding_page.dart';
import 'package:trackapp/theme/app_theme.dart';

class InitPage extends StatelessWidget {
  const InitPage({super.key});

  void navigateToLoginPage(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => LoginPage()));
  }

  void navigateToOnBoardingPage(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => OnboardingPage()));
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: AppPage(
          child: AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 104),
                const SizedBox(height: 18),
                Text(
                  "Support for connected care.",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: appInk,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Monitor devices, groups, and family support from one calm dashboard.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: appMuted),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  child: const Text("Create New Account"),
                  onPressed: () => navigateToOnBoardingPage(context), //() {} == anonymous function... created when used then deleted, has no name
            ),
                const SizedBox(height: 10),
                FilledButton(
                  child: const Text("Login"),
                  onPressed: () => navigateToLoginPage(context), //null == nonexistent function / unknown = grayed out button
            ),

              ],
            ),
          ),
        ),
      ),
    );
  }
}
