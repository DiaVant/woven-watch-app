import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trackapp/pages/main_navigation_page.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
import 'package:trackapp/pages/login_page.dart';
import 'package:trackapp/theme/app_theme.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => SignUpPageState();
}

class SignUpPageState extends State<SignUpPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController1 = TextEditingController();
  TextEditingController passwordController2 = TextEditingController();
  bool submitLock = false;
  bool obscurePasswordToggle = true; 

  String eulaText = "";


  void navigateToMainNavigationPage() { 
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => MainNavigationPage()),
      (Route<dynamic> route) => false
    );
  }
  void navigateToLoginPage() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => LoginPage()),
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
  String ? validatePassword2(String? value) {
    if (value == null || value.isEmpty) {
      return "Please enter your password.";
    }
    if (value != passwordController1.text) {
      return "Passwords do not match.";
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


  Future<void> loadEulaText() async {
    eulaText = await rootBundle.loadString("assets/eula.txt");
  }
  Future<void> showEulaDialog() async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("End-User License Agreement (EULA)"),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                Text(eulaText)
              ],
            ),
          ),

          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () {Navigator.of(context).pop();},
            ),

            TextButton(
              child: const Text("Accept"),
              onPressed: () {
                Navigator.of(context).pop();
                signUp();
              }
            )
          ]
        );
      }
    );
  }



  Future<void> signUp() async {
    String email = emailController.text;
    String password = passwordController1.text;
    
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password
      );

      if (!mounted) return; //page may have been closed while awaiting
      showSnackBar("Account created successfully!");
      navigateToLoginPage();
      // navigateToMainNavigationPage();
    }
    on FirebaseAuthException catch (e) {
      if (!mounted) return;
      //these customs are probbably outdated
      if(e.code == "weak-password"){
        showSnackBar("The provided password is too weak.");
      }
      else if (e.code == 'email-already-in-use') {
        showSnackBar("That email is already in use.");
      }
      else if (e.code == 'invalid-email') {
        showSnackBar("The provided email is invalid.");
      }
      else{
        showSnackBar(e.code);
      }     
      // showSnackBar(e.code);
    }
  }

  Future<void> onPressSignUpButton() async {
    if (submitLock) return; //prevent multiple submits
    submitLock = true;

    if (_formKey.currentState!.validate()) { //run validator wrote above
      await loadEulaText();
      await showEulaDialog();
    }

    if (!mounted) return; //signUp() may have navigated away from this page
    setState(() {
      submitLock = false;
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Sign Up"),
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
                  "Create your account",
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
        
              controller: passwordController1,
              validator: validatePassword,
            ),
        
                const SizedBox(height: 12),
                TextFormField(
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.lock),
                labelText: "Password Verification",
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
        
              controller: passwordController2,
              validator: validatePassword2, 
            ),
        
                const SizedBox(height: 20),
                FilledButton(
              onPressed: onPressSignUpButton,
              child: const Text("Sign Up"), 
            )
        
              ],
            ),
          ),
        ),
      )
    );
  }
}
