import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _agentSessionKey = 'agent_session';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

      await createdUser.sendEmailVerification();
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
        await refreshedUser.sendEmailVerification();
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
      }
    }

    return 'No se pudo guardar tu perfil. $lastError';
  }

  List<String> get _backendBaseUrls {
    const configuredUrl = String.fromEnvironment('API_BASE_URL');
    final urls = <String>[
      if (configuredUrl.trim().isNotEmpty) configuredUrl.trim(),
      'https://backend-movil.web.app',
      'http://192.168.101.12:3000',
      'http://10.0.2.2:3000',
      'http://127.0.0.1:3000',
      'http://localhost:3000',
    ];

    return urls.toSet().toList(growable: false);
  }

  String _backendErrorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {}

    return 'Servidor respondio con error ${response.statusCode}';
  }

  Future<void> _deleteCreatedUser(User user) async {
    try {
      await user.delete();
    } catch (_) {}
  }

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

    Map<String, dynamic>? profileData;
    try {
      final doc =
          await _firestore.collection('users').doc(refreshedUser.uid).get();
      profileData = doc.data();
    } on FirebaseException catch (error) {
      debugPrint(
        'Firestore profile read failed during login: ${error.code} ${error.message}',
      );
    }

    return {
      'uid': refreshedUser.uid,
      'email': refreshedUser.email,
      ...?profileData,
    };
  }

  /// Login de agente: lee Firestore y acepta los esquemas Agentes o
  /// dashboard_agents con campos name/nombre y code/codigo.
  Future<Map<String, dynamic>?> loginAgent({
    required String name,
    required String code,
  }) async {
    final cleanName = name.trim();
    final cleanCode = code.trim();
    if (cleanName.isEmpty || cleanCode.isEmpty) return null;

    try {
      final agent = await _loginAgentFromFirestore(
        name: cleanName,
        code: cleanCode,
      );
      if (agent != null) return agent;
    } on FirebaseException catch (e) {
      debugPrint('Firestore agent login error: ${e.code} ${e.message}');
      if (e.code == 'permission-denied') {
        throw Exception(
          'Firestore no permite leer agentes. Despliega las reglas actualizadas',
        );
      }
      throw Exception('No se pudo verificar el agente. Revisa tu conexion');
    }

    final backendAgent = await _loginAgentWithBackend(
      name: cleanName,
      code: cleanCode,
    );
    if (backendAgent?['__invalidAgent'] == true) return null;
    return backendAgent;
  }

  Future<void> saveAgentSession(Map<String, dynamic> agent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_agentSessionKey, jsonEncode(_jsonSafe(agent)));
  }

  dynamic _jsonSafe(dynamic value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is GeoPoint) {
      return {'lat': value.latitude, 'lng': value.longitude};
    }
    if (value is DocumentReference) return value.path;
    if (value is Map) {
      return value.map(
        (key, nestedValue) => MapEntry(key.toString(), _jsonSafe(nestedValue)),
      );
    }
    if (value is Iterable) return value.map(_jsonSafe).toList();
    return value.toString();
  }

  Future<Map<String, dynamic>?> getSavedAgentSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_agentSessionKey);
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (error) {
      debugPrint('Invalid saved agent session: $error');
    }

    await prefs.remove(_agentSessionKey);
    return null;
  }

  Future<void> clearAgentSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_agentSessionKey);
  }

  Future<Map<String, dynamic>?> _loginAgentFromFirestore({
    required String name,
    required String code,
  }) async {
    const collectionNames = ['Agentes', 'dashboard_agents'];
    const codeFields = ['codigo', 'code'];

    for (final collectionName in collectionNames) {
      for (final codeField in codeFields) {
        final snap = await _firestore
            .collection(collectionName)
            .where(codeField, isEqualTo: code)
            .limit(20)
            .get();

        for (final doc in snap.docs) {
          final data = doc.data();
          final storedName = _readAgentName(data);
          final storedCode = _readAgentCode(data);

          if (_normalizeText(storedName) == _normalizeText(name) &&
              storedCode == code) {
            return _agentPayload(doc.id, data, fallbackName: storedName);
          }
        }
      }
    }

    // Compatibilidad con documentos antiguos que guardan el codigo como
    // numero o usan nombres de campo no estandar.
    for (final collectionName in collectionNames) {
      final snap = await _firestore.collection(collectionName).limit(500).get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final storedName = _readAgentName(data);
        final storedCode = _readAgentCode(data);
        if (_normalizeText(storedName) == _normalizeText(name) &&
            storedCode == code) {
          return _agentPayload(doc.id, data, fallbackName: storedName);
        }
      }
    }

    return null;
  }

  Future<Map<String, dynamic>?> _loginAgentWithBackend({
    required String name,
    required String code,
  }) async {
    Object? lastError;

    for (final baseUrl in _backendBaseUrls) {
      try {
        final response = await http
            .post(
              Uri.parse('$baseUrl/api/auth/agent-login'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'name': name, 'code': code}),
            )
            .timeout(const Duration(seconds: 3));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            return Map<String, dynamic>.from(decoded);
          }
        }

        if (response.statusCode == 400 || response.statusCode == 401) {
          return {'__invalidAgent': true};
        }

        lastError = _backendErrorMessage(response);
      } catch (error) {
        lastError = error;
      }
    }

    debugPrint('Backend agent login failed: $lastError');
    return null;
  }

  Map<String, dynamic> _agentPayload(
    String id,
    Map<String, dynamic> data, {
    required String fallbackName,
  }) {
    final payload = <String, dynamic>{
      'id': id,
      ...data,
    };

    payload['nombre'] = data['nombre'] ?? data['name'] ?? fallbackName;
    payload['name'] = data['name'] ?? data['nombre'] ?? fallbackName;
    payload['codigo'] = data['codigo'] ?? data['code'];
    payload['code'] = data['code'] ?? data['codigo'];

    return payload;
  }

  String _readAgentName(Map<String, dynamic> data) {
    return (data['nombre'] ?? data['name'] ?? '').toString().trim();
  }

  String _readAgentCode(Map<String, dynamic> data) {
    return (data['codigo'] ?? data['code'] ?? '').toString().trim();
  }

  String _normalizeText(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp('[\u00e1\u00e0\u00e4\u00e2\u00e3]'), 'a')
        .replaceAll(RegExp('[\u00e9\u00e8\u00eb\u00ea]'), 'e')
        .replaceAll(RegExp('[\u00ed\u00ec\u00ef\u00ee]'), 'i')
        .replaceAll(RegExp('[\u00f3\u00f2\u00f6\u00f4\u00f5]'), 'o')
        .replaceAll(RegExp('[\u00fa\u00f9\u00fc\u00fb]'), 'u')
        .replaceAll('\u00f1', 'n');
  }

  Future<List<Map<String, dynamic>>> fetchDashboardAlerts({
    String? agentName,
    String? agentId,
    String? companyId,
  }) async {
    try {
      return await _fetchDashboardAlertsFromFirestore(
        agentName: agentName,
        companyId: companyId,
      );
    } catch (error) {
      throw Exception('No se pudieron cargar las alertas: $error');
    }
  }

  Future<void> acceptDashboardAlert({
    required String alertId,
    required String agentName,
    String? agentId,
    String? companyId,
  }) async {
    try {
      await _updateDashboardAlertInFirestore(
        alertId: alertId,
        agentName: agentName,
        agentId: agentId,
        companyId: companyId,
        status: 'accepted',
      );
      return;
    } catch (error) {
      throw Exception('No se pudo aceptar la alerta: $error');
    }
  }

  Future<void> closeDashboardAlert({
    required String alertId,
    required String agentName,
  }) async {
    try {
      await _updateDashboardAlertInFirestore(
        alertId: alertId,
        agentName: agentName,
        status: 'closed',
      );
      return;
    } catch (error) {
      throw Exception('No se pudo cerrar la alerta: $error');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchDashboardAlertsFromFirestore({
    String? agentName,
    String? companyId,
  }) async {
    final snap = await _firestore
        .collection('dashboard_alerts')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();

    final normalizedAgentName = _normalizeText(agentName ?? '');
    final normalizedCompanyId = (companyId ?? '').trim();
    final alerts = snap.docs.map((doc) {
      final data = _serializeFirestoreData(doc.data());
      return {
        'id': doc.id,
        ...data,
      };
    }).where((alert) {
      final status = _normalizeText(
        (alert['status'] ?? alert['estado'] ?? 'active').toString(),
      );
      final assigned = _normalizeText(
        (alert['agenteAsignado'] ?? alert['acceptedBy'] ?? '').toString(),
      );
      final alertCompanyId = (alert['companyId'] ?? '').toString().trim();

      if (status == 'closed' ||
          status == 'cerrada' ||
          status == 'cerrado' ||
          status == 'finalizado' ||
          status == 'cancelado') {
        return false;
      }

      if (alertCompanyId.isEmpty ||
          normalizedCompanyId.isEmpty ||
          alertCompanyId != normalizedCompanyId) {
        return false;
      }

      if (status == 'accepted' ||
          status == 'aceptada' ||
          status == 'aceptado') {
        return normalizedAgentName.isNotEmpty &&
            assigned == normalizedAgentName;
      }

      return assigned.isEmpty || assigned == 'sin asignar';
    }).toList();

    return alerts;
  }

  Future<void> _updateDashboardAlertInFirestore({
    required String alertId,
    required String agentName,
    String? agentId,
    String? companyId,
    required String status,
  }) async {
    final normalizedCompanyId = (companyId ?? '').trim();
    if (status == 'accepted') {
      final alertDoc =
          await _firestore.collection('dashboard_alerts').doc(alertId).get();
      final alertCompanyId =
          (alertDoc.data()?['companyId'] ?? '').toString().trim();
      if (alertCompanyId.isNotEmpty && normalizedCompanyId.isEmpty) {
        throw Exception('Esta alerta requiere empresa asignada');
      }
      if (alertCompanyId.isNotEmpty && alertCompanyId != normalizedCompanyId) {
        throw Exception('Esta alerta pertenece a otra empresa');
      }
    }

    final update = <String, dynamic>{
      'status': status,
      'estado': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (status == 'accepted') {
      update.addAll({
        'agenteAsignado': agentName,
        'acceptedBy': agentName,
        if (agentId != null && agentId.trim().isNotEmpty) ...{
          'agentId': agentId.trim(),
          'agentUid': agentId.trim(),
          'acceptedById': agentId.trim(),
          'guardianId': agentId.trim(),
        },
        'acceptedAt': FieldValue.serverTimestamp(),
      });
    } else if (status == 'closed') {
      update.addAll({
        'closedBy': agentName,
        'closedAt': FieldValue.serverTimestamp(),
      });
    }

    await _firestore.collection('dashboard_alerts').doc(alertId).update(update);

    // These mirrors may not exist for every alert. Keep the main acceptance
    // successful even if an optional mirror cannot be updated.
    for (final collectionName in ['sos_alerts', 'alertas_activas']) {
      try {
        await _firestore.collection(collectionName).doc(alertId).update(update);
      } catch (error) {
        debugPrint(
            'Optional alert mirror update failed: $collectionName $error');
      }
    }
  }

  Map<String, dynamic> _serializeFirestoreData(Map<String, dynamic> data) {
    return data.map((key, value) {
      if (value is Timestamp) {
        return MapEntry(key, value.toDate().toIso8601String());
      }
      if (value is GeoPoint) {
        return MapEntry(key, {'lat': value.latitude, 'lng': value.longitude});
      }
      if (value is Map) {
        return MapEntry(
          key,
          _serializeFirestoreData(Map<String, dynamic>.from(value)),
        );
      }
      if (value is List) {
        return MapEntry(
          key,
          value
              .map((item) => item is Map
                  ? _serializeFirestoreData(Map<String, dynamic>.from(item))
                  : item)
              .toList(),
        );
      }
      return MapEntry(key, value);
    });
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

      await refreshedUser.sendEmailVerification();
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
