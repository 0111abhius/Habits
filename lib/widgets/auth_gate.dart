import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import '../screens/login_screen.dart';
import '../screens/onboarding_screen.dart';
import '../widgets/main_scaffold.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          return _OnboardingGate(uid: snapshot.data!.uid);
        }
        return const LoginScreen();
      },
    );
  }
}

/// Shows onboarding exactly once: only when the user has no settings
/// document yet. Existing users (who already have settings) skip it.
class _OnboardingGate extends StatefulWidget {
  final String uid;
  const _OnboardingGate({required this.uid});

  @override
  State<_OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<_OnboardingGate> {
  bool? _needsOnboarding;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(covariant _OnboardingGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _needsOnboarding = null;
      _check();
    }
  }

  Future<void> _check() async {
    bool needs = false;
    try {
      final doc = await getFirestore().collection('user_settings').doc(widget.uid).get();
      needs = !doc.exists;
    } catch (_) {
      needs = false;
    }
    if (mounted) setState(() => _needsOnboarding = needs);
  }

  @override
  Widget build(BuildContext context) {
    if (_needsOnboarding == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_needsOnboarding == true) {
      return OnboardingScreen(onDone: () => setState(() => _needsOnboarding = false));
    }
    return const MainScaffold();
  }
}
