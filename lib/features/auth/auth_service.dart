import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
/// Xác thực Email / Google (mục 2.3) và tạo hồ sơ users/{uid} (Bảng 2).
class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  AuthService({FirebaseAuth? auth, FirebaseFirestore? db})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  Stream<User?> get authState => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> signInWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> registerWithEmail(
      String email, String password, String displayName) async {
    final cred = await _auth.createUserWithEmailAndPassword(
        email: email, password: password);
    await cred.user?.updateDisplayName(displayName);
    await _ensureProfile(cred.user!, displayName: displayName);
  }

  /// Trả về false nếu người dùng hủy.
  Future<bool> signInWithGoogle() async {
    if (kIsWeb) {
    final result = await _auth.signInWithPopup(GoogleAuthProvider());
    await _ensureProfile(result.user!);
    return true;
  }
    final account = await GoogleSignIn().signIn();
    if (account == null) return false;
    final auth = await account.authentication;
    final cred = GoogleAuthProvider.credential(
      accessToken: auth.accessToken,
      idToken: auth.idToken,
    );
    final result = await _auth.signInWithCredential(cred);
    await _ensureProfile(result.user!);
    return true;
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
  }

  Future<void> _ensureProfile(User u, {String? displayName}) async {
    final ref = _db.collection('users').doc(u.uid);
    final snap = await ref.get();
    if (snap.exists) return;
    await ref.set({
      'uid': u.uid,
      'email': u.email,
      'displayName': displayName ?? u.displayName ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static String messageFor(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return 'Email không hợp lệ.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Email hoặc mật khẩu không đúng.';
        case 'email-already-in-use':
          return 'Email này đã được đăng ký.';
        case 'weak-password':
          return 'Mật khẩu quá yếu (tối thiểu 6 ký tự).';
        case 'network-request-failed':
          return 'Không có kết nối mạng.';
      }
    }
    return 'Đăng nhập thất bại. Vui lòng thử lại.';
  }
}
