import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:guidex/models/register_student_request.dart';
import 'package:guidex/services/auth/auth_failure.dart';
import 'package:guidex/services/auth/auth_service.dart';

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn(
          scopes: <String>['email'],
          serverClientId: '59155610982-fpfq7823cs4u713eaj3ouaut9rd50r73.apps.googleusercontent.com',
        );

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  @override
  Future<User> registerWithEmail(
      RegisterStudentRequest request) async {
    _validateRegisterRequest(request);

    try {
      final UserCredential credential =
          await _auth.createUserWithEmailAndPassword(
        email: request.email.trim(),
        password: request.password,
      );

      final User? user = credential.user;
      if (user == null) {
        throw const AuthFailure(
          'register-failed',
          'Unable to create account. Please try again.',
        );
      }
      
      if (user.displayName == null || user.displayName!.isEmpty) {
        await user.updateDisplayName(request.name.trim());
      }

      return user;
    } on FirebaseAuthException catch (exception) {
      throw mapFirebaseAuthException(exception);
    } catch (exception) {
      throw mapGenericAuthError(exception);
    }
  }

  @override
  Future<User> signInWithEmail({
    required String email,
    required String password,
  }) async {
    _validateEmail(email);
    _validatePassword(password);

    try {
      final UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final User? user = credential.user;
      if (user == null) {
        throw const AuthFailure(
          'login-failed',
          'Unable to login. Please try again.',
        );
      }

      return user;
    } on FirebaseAuthException catch (exception) {
      throw mapFirebaseAuthException(exception);
    } catch (exception) {
      throw mapGenericAuthError(exception);
    }
  }

  @override
  Future<User> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw const AuthFailure(
            'google-cancelled', 'Google sign-in was cancelled.');
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      if (googleAuth.idToken == null) {
        throw const AuthFailure(
          'google-token-missing',
          'Unable to read Google ID token.',
        );
      }

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);

      final User? user = userCredential.user;
      if (user == null) {
        throw const AuthFailure(
            'google-login-failed', 'Google sign-in failed.');
      }

      return user;
    } on FirebaseAuthException catch (exception) {
      throw mapFirebaseAuthException(exception);
    } catch (exception) {
      throw mapGenericAuthError(exception);
    }
  }

  @override
  Future<User> signInWithApple() async {
    final bool isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final bool isApplePlatform = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

    if (!isAndroid && !isApplePlatform) {
      throw const AuthFailure(
        'apple-not-supported',
        'Apple sign-in is not supported on this device.',
      );
    }

    try {
      final AppleAuthProvider provider = AppleAuthProvider();
      provider.addScope('email');
      provider.addScope('name');

      final UserCredential credential =
          await _auth.signInWithProvider(provider);
      final User? user = credential.user;
      if (user == null) {
        throw const AuthFailure('apple-login-failed', 'Apple sign-in failed.');
      }

      return user;
    } on UnimplementedError {
      throw const AuthFailure(
        'apple-not-supported',
        'Apple sign-in is not available in this build.',
      );
    } on UnsupportedError {
      throw const AuthFailure(
        'apple-not-supported',
        'Apple sign-in is not supported on this Android configuration.',
      );
    } on FirebaseAuthException catch (exception) {
      throw mapFirebaseAuthException(exception);
    } catch (exception) {
      throw mapGenericAuthError(exception);
    }
  }

  @override
  Future<User?> restoreSession() async {
    return _auth.currentUser;
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Google session may not exist for email/password users.
    }
  }

  void _validateRegisterRequest(RegisterStudentRequest request) {
    if (request.name.trim().isEmpty) {
      throw const AuthFailure('invalid-name', 'Name is required.');
    }
    _validateEmail(request.email);
    _validatePassword(request.password);
  }

  void _validateEmail(String email) {
    final String value = email.trim();
    if (value.isEmpty) {
      throw const AuthFailure('invalid-email', 'Email is required.');
    }

    const String pattern = r'^[^@\s]+@[^@\s]+\.[^@\s]+$';
    if (!RegExp(pattern).hasMatch(value)) {
      throw const AuthFailure('invalid-email', 'Please enter a valid email.');
    }
  }

  void _validatePassword(String password) {
    if (password.isEmpty) {
      throw const AuthFailure('invalid-password', 'Password is required.');
    }
    if (password.length < 6) {
      throw const AuthFailure(
        'weak-password',
        'Password must be at least 6 characters.',
      );
    }
  }
}
