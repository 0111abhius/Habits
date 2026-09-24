@TestOn('browser')
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_logger/screens/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Web auth flow', () {
    setUpAll(() async {
      await Firebase.initializeApp();
    });

    testWidgets('Google sign-in invokes signInWithPopup on web', (tester) async {
      final mockUser = MockUser(uid: 'web', email: 'w@e.com');
      final mockAuth = _PopupMockAuth(mockUser: mockUser);
      // Replace global instance (visibleForTesting) – safe in test context
      FirebaseAuth.instance = mockAuth;

      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign in with Google'));
      await tester.pumpAndSettle();

      expect(mockAuth.popupCalled, isTrue);
    });
  });
}

class _PopupMockAuth extends MockFirebaseAuth {
  bool popupCalled = false;
  _PopupMockAuth({required MockUser mockUser}) : super(mockUser: mockUser);

  @override
  Future<UserCredential> signInWithPopup(AuthProvider provider) async {
    popupCalled = true;
    return super.signInWithCredential(GoogleAuthProvider.credential(idToken: 't', accessToken: 'a'));
  }
}