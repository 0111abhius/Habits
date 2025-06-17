import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/timeline_screen.dart';
import 'screens/habits_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/template_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

FirebaseFirestore? _testFirestore;

/// Used by tests to inject a Fake/Mock Firestore.
void overrideFirestoreForTests(FirebaseFirestore instance) {
  _testFirestore = instance;
}

FirebaseFirestore getFirestore() {
  if (_testFirestore != null) return _testFirestore!;
  return FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'habitstore',
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyAfmZKJgt64-4l94e0S_tE9wsXO0x0TQxA",
        appId: "1:308942065441:android:a382694cb907a458eeb860",
        messagingSenderId: "308942065441",
        projectId: "habitlogger-55050",
        storageBucket: "habitlogger-55050.firebasestorage.app",
      ),
    );
    
    // Configure Firestore settings
    getFirestore().settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    
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
      ),
      home: const LoginScreen(),
      routes: {
        '/timeline': (context) => const TimelineScreen(),
        '/habits': (context) => const HabitsScreen(),
        '/analytics': (context) => const AnalyticsScreen(),
        '/template': (context) => const TemplateScreen(),
      },
    );
  }
}
