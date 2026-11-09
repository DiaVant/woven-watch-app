import 'package:flutter/material.dart';
import 'package:trackapp/pages/main_navigation_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:trackapp/theme/app_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => LoginPageState();
}

class LoginPageState extends State<LoginPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  bool submitLock = false;
  bool obscurePasswordToggle = true;


  void navigateToMainNavigationPage() { //!!TODO: check if this is correct
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => MainNavigationPage()),
      (Route<dynamic> route) => false
    );
  }


  String ? validateEmail(String? value) {
    String emailRegex = r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+";
    if (value == null || value.isEmpty) {
      return "Please enter your email.";
    }
    if (!RegExp(emailRegex).hasMatch(value)) {
      return "Invalid Email";
    }
    return null;
  }
  String ? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return "Please enter your password.";
    }
    return null;
  }

  void showSnackBar(String message) {
    //grab the messenger once so the Dismiss action still works after this page is unmounted
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: "Dismiss",
          textColor: appGold,
          onPressed: messenger.hideCurrentSnackBar,
        )
      )
    );
  }


  void onPressLoginButton() async {
    if (submitLock) return; //prevent multiple submits
    submitLock = true;

    if (_formKey.currentState!.validate()) { //valid!
      String email = emailController.text;
      String password = passwordController.text;
      
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password
        );

        if (!mounted) return; //page may have been closed while awaiting
        navigateToMainNavigationPage();
        return; //this page is gone after navigation, don't touch state below
      }
      on FirebaseAuthException catch (e) {
        if (!mounted) return;
        showSnackBar(e.code);
      }
    }

    setState(() {
        submitLock = false;
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Login"),
      ),
      body: AppPage(
        child: AppCard(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 76),
                const SizedBox(height: 18),
                Text(
                  "Welcome back",
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: appInk,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.email),
                  labelText: "Email",
                  hintText: "user@website.com"
                ),
        
                controller: emailController, //userinput stored into controller
                validator: validateEmail,
              ),

                const SizedBox(height: 12),
                TextFormField(
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.lock),
                  labelText: "Password",
                  hintText: "* * * * * *",
                  suffixIcon: IconButton(
                    icon: Icon(obscurePasswordToggle ? Icons.visibility : Icons.visibility_off),
                    onPressed: () {
                      setState(() {
                        obscurePasswordToggle = !obscurePasswordToggle;
                      });
                    }
                  )
                ),
                obscureText: obscurePasswordToggle,

                controller: passwordController,
                validator: validatePassword,
              ),

                const SizedBox(height: 20),
                FilledButton(
                onPressed: onPressLoginButton,
                child: const Text("Login"), //TODO: REPLACE WITH LOGIN FUNCTION... do i need to do () =>??????
              )

              ],
            ),
          ),
        ),
      )
    );
  }
}
