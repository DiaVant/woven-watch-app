import 'package:flutter/material.dart';

const appName = 'WovenWatch';
//colors from the logo
const appIndigo = Color(0xFF6662D9); //app bar, primary action, active tab
const appBlue = Color(0xFF335AA6); //section titles, links, secondary icons
const appTeal = Color(0xFF24BFA3); //calm
const appGold = Color(0xFFF2A341); //low fidgeting
const appRed = Color(0xFFE2524A); //high fidgeting
const appInk = Color(0xFF1B2440); //headings and values
const appMuted = Color(0xFF6B7390); //labels and captions
const appBorder = Color(0xFFE4E4F0); //card edges and rules
const appSoftGray = Color(0xFFF4F4F9); //screen background

//darker versions for text on a tinted background
const appTealText = Color(0xFF17887A);
const appGoldText = Color(0xFFB5731A);

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 88, this.showName = true});

  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.asset(
            'assets/app.png',
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        ),
        if (showName) ...[
          const SizedBox(height: 10),
          Text(
            appName,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: appBlue,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ],
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.color = Colors.white});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: appBorder),
        boxShadow: [
          BoxShadow(
            color: appIndigo.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }
}
