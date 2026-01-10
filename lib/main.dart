import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
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
    
    // Configure Firestore settings
    // Disable persistence on web to avoid "Failed to obtain exclusive access" 
    // errors when multiple tabs are open.
    getFirestore().settings = const Settings(
      persistenceEnabled: false,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    
    // Ensure auth persistence on web so the user stays signed in across reloads.
    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    }
    
    print('Firebase initialized successfully');
  } catch (e) {
    print('Failed to initialize Firebase: $e');
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Habit Logger',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
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
