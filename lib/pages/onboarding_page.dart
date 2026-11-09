import 'package:flutter/material.dart';
import 'package:trackapp/pages/singup_page.dart';
import 'package:trackapp/theme/app_theme.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => OnboardingPageState();
}

class OnboardingPageState extends State<OnboardingPage> {

  void navigateToSignUpPage() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => SignUpPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Onboarding"),
      ),
      body: AppPage(
        child: AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 88),
              const SizedBox(height: 18),
              Text(
                "Welcome to $appName",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: appInk,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                "A simple place to keep devices, groups, and family support visible.",
                textAlign: TextAlign.center,
                style: TextStyle(color: appMuted),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed:  navigateToSignUpPage,
                child: const Text("continue"), //() {} == anonymous function... created when used then deleted, has no name
             ),
            ],
          ),
        ),
      )
    );
  }
}
