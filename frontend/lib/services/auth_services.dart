import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _verificationContinueUrl =
      'https://soslive-f7513.firebaseapp.com/email-verified';

  Future<String?> register({
    required String email,
    required String password,
    required String name,
    int? age,
    String? gender,
    String? bloodType,
  }) async {
    User? createdUser;
    final normalizedEmail = email.trim().toLowerCase();

    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      createdUser = credential.user;
      if (createdUser == null) {
        return 'No se pudo crear la cuenta';
      }

      final profileError = await _saveProfile(
        user: createdUser,
        email: normalizedEmail,
        name: name.trim(),
        age: age,
        gender: gender,
        bloodType: bloodType,
      );

      if (profileError != null) {
        await _deleteCreatedUser(createdUser);
        await _auth.signOut();
        return profileError;
      }

      await _sendVerificationEmail(createdUser);
      await _auth.signOut();
      return null;
    } on FirebaseAuthException catch (error) {
      if (createdUser != null) {
        await _deleteCreatedUser(createdUser);
      }

      if (error.code == 'email-already-in-use') {
        final repairError = await _completeExistingRegistration(
          email: normalizedEmail,
          password: password,
          name: name.trim(),
          age: age,
          gender: gender,
          bloodType: bloodType,
        );

        if (repairError == null) return null;
        return repairError;
      }

      switch (error.code) {
        case 'email-already-in-use':
          return 'El correo ya esta registrado';
        case 'invalid-email':
          return 'Ingresa un correo valido';
        case 'weak-password':
          return 'La contrasena debe tener minimo 6 caracteres';
        case 'network-request-failed':
          return 'No se pudo conectar. Revisa tu internet';
        default:
          return 'No se pudo registrar el usuario';
      }
    } catch (_) {
      if (createdUser != null) {
        await _deleteCreatedUser(createdUser);
      }
      return 'No se pudo completar el registro';
    }
  }

  Future<String?> _completeExistingRegistration({
    required String email,
    required String password,
    required String name,
    required int? age,
    required String? gender,
    required String? bloodType,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) return 'No se encontro la cuenta';

      final profileError = await _saveProfile(
        user: user,
        email: email,
        name: name,
        age: age,
        gender: gender,
        bloodType: bloodType,
      );

      if (profileError != null) {
        await _auth.signOut();
        return profileError;
      }

      await user.reload();
      final refreshedUser = _auth.currentUser;
      if (refreshedUser != null && !refreshedUser.emailVerified) {
        await _sendVerificationEmail(refreshedUser);
      }

      await _auth.signOut();
      return null;
    } on FirebaseAuthException catch (error) {
      await _auth.signOut();
      switch (error.code) {
        case 'invalid-credential':
        case 'wrong-password':
          return 'Ese correo ya existe. Ingresa la misma contrasena o usa otro correo';
        case 'network-request-failed':
          return 'No se pudo conectar. Revisa tu internet';
        default:
          return 'No se pudo completar el perfil de la cuenta existente';
      }
    } catch (error) {
      await _auth.signOut();
      debugPrint('Existing registration repair failed: $error');
      return 'No se pudo completar el perfil de la cuenta existente';
    }
  }

  Future<String?> _saveProfile({
    required User user,
    required String email,
    required String name,
    required int? age,
    required String? gender,
    required String? bloodType,
  }) async {
    final firestoreData = {
      'name': name,
      'email': email,
      'age': age,
      'gender': gender,
      'bloodType': bloodType,
      'role': 'persona',
      'type': 'persona',
      'guardians': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    };

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set(firestoreData, SetOptions(merge: true));
      return null;
    } on FirebaseException catch (error) {
      debugPrint(
        'Firestore profile save failed: ${error.code} ${error.message}',
      );
      return _saveProfileWithBackend(
        user: user,
        email: email,
        name: name,
        age: age,
        gender: gender,
        bloodType: bloodType,
      );
    }
  }

  Future<String?> _saveProfileWithBackend({
    required User user,
    required String email,
    required String name,
    required int? age,
    required String? gender,
    required String? bloodType,
  }) async {
    final token = await user.getIdToken(true);
    final payload = jsonEncode({
      'uid': user.uid,
      'email': email,
      'name': name,
      'age': age,
      'gender': gender,
      'bloodType': bloodType,
    });

    String lastError = 'No se pudo conectar con el servidor local';

    for (final baseUrl in _backendBaseUrls) {
      try {
        debugPrint('Trying backend profile save at $baseUrl');
        final response = await http
            .post(
              Uri.parse('$baseUrl/api/auth/profile'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: payload,
            )
            .timeout(const Duration(seconds: 6));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return null;
        }
        lastError = _backendErrorMessage(response);
        debugPrint('Backend profile save failed at $baseUrl: $lastError');
      } catch (error) {
        lastError = 'No hubo respuesta desde $baseUrl';
        debugPrint('Backend profile save failed at $baseUrl: $error');
        // Try the next local backend address.
      }
    }

    return 'No se pudo guardar tu perfil. $lastError';
  }

  List<String> get _backendBaseUrls {
    const configuredUrl = String.fromEnvironment('API_BASE_URL');
    const localNetworkUrl = 'http://10.153.218.90:3000';
    if (kIsWeb) {
      return [
        if (configuredUrl.trim().isNotEmpty) configuredUrl.trim(),
        'http://127.0.0.1:3000',
      ].toSet().toList();
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return [
          if (configuredUrl.trim().isNotEmpty) configuredUrl.trim(),
          'http://127.0.0.1:3000',
          localNetworkUrl,
          'http://10.0.2.2:3000',
        ].toSet().toList();
      default:
        return [
          if (configuredUrl.trim().isNotEmpty) configuredUrl.trim(),
          localNetworkUrl,
          'http://127.0.0.1:3000',
        ].toSet().toList();
    }
  }

  String _backendErrorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {
      // Fall back to the HTTP status below.
    }

    return 'Servidor respondio con error ${response.statusCode}';
  }

  Future<void> _deleteCreatedUser(User user) async {
    try {
      await user.delete();
    } catch (_) {
      // Ignore cleanup failures; the visible error still explains the failure.
    }
  }

  Future<void> _sendVerificationEmail(User user) {
    return user.sendEmailVerification(_verificationActionCodeSettings);
  }

  Future<void> sendVerificationEmailToCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No hay un usuario autenticado',
      );
    }

    await user.reload();
    final refreshedUser = _auth.currentUser;
    if (refreshedUser == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No se encontro la cuenta',
      );
    }

    if (refreshedUser.emailVerified) {
      return;
    }

    await _sendVerificationEmail(refreshedUser);
  }

  ActionCodeSettings get _verificationActionCodeSettings =>
      ActionCodeSettings(
        url: _verificationContinueUrl,
        handleCodeInApp: false,
        androidPackageName: 'com.sosLive.app',
        androidInstallApp: true,
        iOSBundleId: 'com.SosLive.appssos',
      );

  Future<Map<String, dynamic>?> login({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );

    final user = credential.user;
    if (user == null) return null;

    await user.reload();
    final refreshedUser = _auth.currentUser;
    if (refreshedUser == null) return null;

    await refreshedUser.getIdToken(true);

    if (!refreshedUser.emailVerified) {
      await _auth.signOut();
      throw FirebaseAuthException(
        code: 'email-not-verified',
        message: 'Verifica tu correo antes de ingresar',
      );
    }

    final doc =
        await _firestore.collection('users').doc(refreshedUser.uid).get();
    return {
      'uid': refreshedUser.uid,
      'email': refreshedUser.email,
      ...?doc.data(),
    };
  }

  Future<String?> resendVerificationEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final user = credential.user;
      if (user == null) return 'No se encontro la cuenta';

      await user.reload();
      final refreshedUser = _auth.currentUser;
      if (refreshedUser == null) return 'No se encontro la cuenta';

      if (refreshedUser.emailVerified) {
        return null;
      }

      await _sendVerificationEmail(refreshedUser);
      await _auth.signOut();
      return 'Te enviamos un nuevo enlace de verificacion';
    } on FirebaseAuthException catch (error) {
      switch (error.code) {
        case 'invalid-credential':
        case 'wrong-password':
        case 'user-not-found':
          return 'Correo o contrasena incorrectos';
        case 'too-many-requests':
          return 'Demasiados intentos. Intenta mas tarde';
        case 'network-request-failed':
          return 'Sin conexion a internet';
        default:
          return 'No se pudo enviar el correo de verificacion';
      }
    }
  }
}
