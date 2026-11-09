import 'package:flutter/material.dart';
import 'package:trackapp/pages/account_page.dart';
import 'package:trackapp/screens/home_screen.dart';
import 'package:trackapp/screens/devices_screen.dart';
import 'package:trackapp/theme/app_theme.dart';

class NavigationItem {
  final String title;
  final Widget screen;
  final IconData icon;
  final String label;

  NavigationItem({
    required this.title,
    required this.screen,
    required this.icon,
    required this.label,
  });
}

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});
  
  @override
  State<MainNavigationPage> createState() => MainNavigationPageState();
}

class MainNavigationPageState extends State<MainNavigationPage> {
  int currScreenIndex = 0;

 final _items = [
    NavigationItem(
      title: 'Home',
      screen: HomeScreen(),
      icon: Icons.home_outlined,
      label: 'Home',
    ),
    NavigationItem(
      title: 'Devices',
      screen: DevicesScreen(),
      icon: Icons.bluetooth,
      label: 'Devices',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        //email is on the account page
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 32, showName: false),
            const SizedBox(width: 12),
            Text(_items[currScreenIndex].title),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Account',
            icon: CircleAvatar(
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              child: const Icon(Icons.person_outline, color: Colors.white),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AccountPage()),
              );
            },
          )
        ]
      ),

      body: _items[currScreenIndex].screen,

      bottomNavigationBar: BottomNavigationBar(
        selectedItemColor: appIndigo,
        unselectedItemColor: appMuted,
        currentIndex: currScreenIndex,
        onTap: (index) {
          setState(() {
            currScreenIndex = index;
          });
        },
        items: _items.map((item) {
          return BottomNavigationBarItem(
            icon: Icon(item.icon),
            label: item.label,
          );
        }).toList()
      ),
        
    );
  }
}
