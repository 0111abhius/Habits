import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_logger/screens/login_screen.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:google_sign_in_mocks/google_sign_in_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setupFirebaseAuthMocks();

  testWidgets('Google sign-in invokes platform flow on mobile', (tester) async {
    await Firebase.initializeApp();

    // Install mock GoogleSignIn platform handler
    final mockGoogleSignIn = MockGoogleSignIn();
    GoogleSignInPlatform.instance = mockGoogleSignIn;

    // Signed out state so LoginScreen visible
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();

    // Tap Google sign-in button
    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();

    // MockGoogleSignIn should have been called
    expect(mockGoogleSignIn.signInCalled, true);
  });
}