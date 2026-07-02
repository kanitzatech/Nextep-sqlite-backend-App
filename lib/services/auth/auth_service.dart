import 'package:firebase_auth/firebase_auth.dart';
import 'package:guidex/models/register_student_request.dart';

abstract class AuthService {
  Future<User> registerWithEmail(RegisterStudentRequest request);

  Future<User> signInWithEmail({
    required String email,
    required String password,
  });

  Future<User> signInWithGoogle();

  Future<User> signInWithApple();

  Future<User?> restoreSession();

  Future<void> signOut();
}
