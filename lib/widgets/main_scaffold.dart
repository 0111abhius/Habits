import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../screens/timeline_screen.dart';
import '../screens/habits_screen.dart';
import '../screens/analytics_screen.dart';
import '../screens/activities_management_screen.dart';
import '../screens/tasks_screen.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  int _analyticsRefreshCounter = 0;

  @override
  bool _isBottomBarVisible = true;

  List<Widget> get _screens => [
    const TimelineScreen(),
    const TasksScreen(),
    const HabitsScreen(),
    AnalyticsScreen(key: ValueKey('analytics_$_analyticsRefreshCounter')),
    const ActivitiesManagementScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          // If content fits the screen (no meaningful scroll extent), never hide the bottom bar
          if (notification.metrics.maxScrollExtent < 50) {
            if (!_isBottomBarVisible) setState(() => _isBottomBarVisible = true);
            return true;
          }

          if (notification.direction == ScrollDirection.reverse) {
            // User scrolling down -> Hide
            if (_isBottomBarVisible) setState(() => _isBottomBarVisible = false);
          } else if (notification.direction == ScrollDirection.forward) {
            // User scrolling up -> Show
            if (!_isBottomBarVisible) setState(() => _isBottomBarVisible = true);
          }
          return true;
        },
        child: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
      ),
      bottomNavigationBar: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: _isBottomBarVisible ? 80 : 0,
        child: SingleChildScrollView(
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
                _isBottomBarVisible = true;
                if (index == 3) {
                  _analyticsRefreshCounter++;
                }
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.timeline),
                label: 'Timeline',
              ),
              NavigationDestination(
                icon: Icon(Icons.task_alt),
                label: 'Tasks',
              ),
              NavigationDestination(
                icon: Icon(Icons.check_circle_outline),
                label: 'Habits',
              ),
              NavigationDestination(
                icon: Icon(Icons.bar_chart),
                label: 'Analytics',
              ),
              NavigationDestination(
                icon: Icon(Icons.category),
                label: 'Activities',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
