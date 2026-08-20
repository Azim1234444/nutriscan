import 'package:flutter/material.dart';

import '../screens/history/history_screen.dart';
import '../screens/home/home_dashboard_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/scan/scan_screen.dart';

/// The four main tabs of the app.
enum AppTab { home, scan, history, profile }

/// Holds the bottom navigation bar and keeps one screen per tab alive.
///
/// [IndexedStack] means switching tabs does not rebuild or reset the other
/// screens, which is what users expect from a bottom navigation bar.
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialTab = AppTab.home});

  final AppTab initialTab;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late AppTab _currentTab = widget.initialTab;

  void _selectTab(AppTab tab) {
    if (_currentTab == tab) return;
    setState(() => _currentTab = tab);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentTab.index,
        children: <Widget>[
          HomeDashboardScreen(
            onScanPressed: () => _selectTab(AppTab.scan),
            onSeeAllMealsPressed: () => _selectTab(AppTab.history),
          ),
          const ScanScreen(),
          // Told which tab is showing, because this stack keeps History alive
          // between visits: it re-reads when it comes back rather than going
          // on showing whatever it loaded the first time.
          HistoryScreen(isActive: _currentTab == AppTab.history),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab.index,
        onDestinationSelected: (int index) => _selectTab(AppTab.values[index]),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.center_focus_weak_outlined),
            selectedIcon: Icon(Icons.center_focus_strong_rounded),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
