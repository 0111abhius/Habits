import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/timeline_screen.dart';
import 'screens/habits_screen.dart';
import 'screens/tasks_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/template_screen.dart';
import 'screens/templates_list_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'widgets/auth_gate.dart';
import 'widgets/main_scaffold.dart';

FirebaseFirestore? _testFirestore;

/// Used by tests to inject a Fake/Mock Firestore.
void overrideFirestoreForTests(FirebaseFirestore instance) {
  _testFirestore = instance;
}

FirebaseFirestore getFirestore() {
  if (_testFirestore != null) return _testFirestore!;
  return FirebaseFirestore.instanceFor(
    app: Firebase.app(),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: "assets/env");
  
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyB0BbNpPnUt-ixHTwRXhn1fFUMfTsJXnh4",
        appId: "1:1033076029638:web:0fd9006d04040cf7557fc7",
        messagingSenderId: "1033076029638",
        projectId: "habitslogger",
        authDomain: "habitslogger.firebaseapp.com",
        storageBucket: "habitslogger.firebasestorage.app",
        measurementId: "G-JHW4N1XDPX",
      ),
    );
    
    // Offline cache. On web, multi-tab persistence avoids the historical
    // "Failed to obtain exclusive access" error while keeping data available
    // offline / on flaky connections and making reloads instant.
    getFirestore().settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    if (kIsWeb) {
      try {
        // ignore: deprecated_member_use
        await getFirestore().enablePersistence(const PersistenceSettings(synchronizeTabs: true));
      } catch (e) {
        debugPrint('Web persistence unavailable: $e');
      }
    }

    // Ensure auth persistence on web so the user stays signed in across reloads.
    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    }

    debugPrint('Firebase initialized successfully');
  } catch (e) {
    debugPrint('Failed to initialize Firebase: $e');
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Day Coach',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
        fontFamilyFallback: const ['Noto Color Emoji'],
      ),
      home: const AuthGate(),
      routes: {
        '/home': (context) => const MainScaffold(),
        '/timeline': (context) => const TimelineScreen(),
        '/tasks': (context) => const TasksScreen(),
        '/habits': (context) => const HabitsScreen(),
        '/analytics': (context) => const AnalyticsScreen(),
        '/template': (context) => const TemplatesListScreen(),
        '/template-edit': (context) => const TemplateScreen(),
      },
    );
  }
}
