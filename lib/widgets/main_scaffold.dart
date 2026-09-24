import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../screens/timeline_screen.dart';
import '../screens/habits_screen.dart';
import '../screens/analytics_screen.dart';
import '../screens/tasks_screen.dart';
import '../screens/plan_tomorrow_screen.dart';
import '../services/reminder_service.dart';

enum MainTab { today, tasks, habits, progress }

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  /// Lets any screen switch the active bottom tab (e.g. "Pick tasks" on the
  /// timeline jumps to the Tasks tab).
  static final ValueNotifier<MainTab> tabNotifier = ValueNotifier(MainTab.today);

  static void selectTab(MainTab tab) => tabNotifier.value = tab;

  /// Ask the Today tab to show a specific date (consumed by TimelineScreen).
  static final ValueNotifier<DateTime?> dateRequest = ValueNotifier(null);
  static void openDay(DateTime date) {
    dateRequest.value = DateTime(date.year, date.month, date.day);
    selectTab(MainTab.today);
  }

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _analyticsRefreshCounter = 0;
  bool _isBottomBarVisible = true;

  @override
  void initState() {
    super.initState();
    MainScaffold.tabNotifier.addListener(_onTabChanged);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) ReminderService.instance.start(uid);
    ReminderService.instance.lastFired.addListener(_onReminderFired);
  }

  @override
  void dispose() {
    MainScaffold.tabNotifier.removeListener(_onTabChanged);
    ReminderService.instance.lastFired.removeListener(_onReminderFired);
    ReminderService.instance.stop();
    super.dispose();
  }

  /// In-app echo of a reminder, so it is seen even if the browser suppressed
  /// the system notification because the tab is in the foreground.
  void _onReminderFired() {
    final r = ReminderService.instance.lastFired.value;
    if (r == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${r.title} — ${r.body}'),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: r.id.startsWith('habit') ? 'Habits' : (r.id == 'plan_tomorrow' ? 'Plan' : 'Open'),
        onPressed: () {
          if (r.id == 'plan_tomorrow') {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlanTomorrowScreen()));
          } else {
            MainScaffold.selectTab(r.id.startsWith('habit') ? MainTab.habits : MainTab.today);
          }
        },
      ),
    ));
  }

  void _onTabChanged() {
    if (!mounted) return;
    setState(() {
      _isBottomBarVisible = true;
      if (MainScaffold.tabNotifier.value == MainTab.progress) _analyticsRefreshCounter++;
    });
  }

  List<Widget> get _screens => [
        const TimelineScreen(),
        const TasksScreen(),
        const HabitsScreen(),
        AnalyticsScreen(key: ValueKey('analytics_$_analyticsRefreshCounter')),
      ];

  @override
  Widget build(BuildContext context) {
    final currentIndex = MainScaffold.tabNotifier.value.index;
    final wide = MediaQuery.of(context).size.width >= 900;

    const destinations = [
      NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
      NavigationDestination(icon: Icon(Icons.task_alt_outlined), selectedIcon: Icon(Icons.task_alt), label: 'Tasks'),
      NavigationDestination(
          icon: Icon(Icons.self_improvement_outlined), selectedIcon: Icon(Icons.self_improvement), label: 'Habits'),
      NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Progress'),
    ];

    final body = NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.maxScrollExtent < 50) {
          if (!_isBottomBarVisible) setState(() => _isBottomBarVisible = true);
          return true;
        }
        if (notification.direction == ScrollDirection.reverse) {
          if (_isBottomBarVisible) setState(() => _isBottomBarVisible = false);
        } else if (notification.direction == ScrollDirection.forward) {
          if (!_isBottomBarVisible) setState(() => _isBottomBarVisible = true);
        }
        return true;
      },
      child: IndexedStack(index: currentIndex, children: _screens),
    );

    if (wide) {
      // Desktop / wide web: persistent rail instead of a bottom bar.
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: currentIndex,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) => MainScaffold.selectTab(MainTab.values[i]),
              destinations: destinations
                  .map((d) => NavigationRailDestination(icon: d.icon, selectedIcon: d.selectedIcon, label: Text(d.label)))
                  .toList(),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: _isBottomBarVisible ? 80 : 0,
        child: SingleChildScrollView(
          child: NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: (index) => MainScaffold.selectTab(MainTab.values[index]),
            destinations: destinations,
          ),
        ),
      ),
    );
  }
}
