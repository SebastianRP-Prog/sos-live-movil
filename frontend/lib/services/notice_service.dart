import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class Notice {
  final String id;
  final String tipo;
  final String titulo;
  final String mensaje;
  final DateTime? timestamp;
  final bool leido;
  final String icono;
  final String color;
  final String creadoPor;

  Notice({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.mensaje,
    this.timestamp,
    required this.leido,
    required this.icono,
    required this.color,
    required this.creadoPor,
  });

  factory Notice.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Notice(
      id: doc.id,
      tipo: data['tipo'] ?? 'comunicado',
      titulo: data['titulo'] ?? 'Aviso',
      mensaje: data['mensaje'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
      leido: data['leido'] ?? false,
      icono: data['icono'] ?? 'shield',
      color: data['color'] ?? 'gold',
      creadoPor: data['creadoPor'] ?? '',
    );
  }
}

class DuplicateSosLocationException implements Exception {
  const DuplicateSosLocationException();

  @override
  String toString() => 'Ya tienes una alerta activa en esta misma ubicacion';
}

class NoticeService {
  static final NoticeService _instance = NoticeService._internal();
  factory NoticeService() => _instance;
  NoticeService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const double _duplicateLocationRadiusMeters = 25;

  String? get _uid => _auth.currentUser?.uid;

  Stream<List<Notice>> misNotices() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();

    return _db
        .collection('notices')
        .where('destinatarios', arrayContains: uid)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map(Notice.fromDoc).toList());
  }

  Future<void> crearNoticeSOS({
    required double lat,
    required double lng,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Usuario no autenticado');

    Map<String, dynamic> userData = {};
    try {
      final userDoc = await _db.collection('users').doc(uid).get();
      userData = userDoc.data() ?? {};
    } on FirebaseException {
      // El SOS debe guardarse aunque el perfil no cargue.
    }

    final user = _auth.currentUser;
    final nombre = userData['name'] ??
        userData['nombre'] ??
        user?.displayName ??
        user?.email ??
        'Usuario SOS';
    final email = userData['email'] ?? user?.email ?? '';
    final guardianes = userData['guardians'];
    final guardianIds = guardianes is List
        ? guardianes.whereType<String>().toList()
        : <String>[];
    final destinatarios = <String>[uid, ...guardianIds];
    final mapUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

    await _assertNoActiveSosAtLocation(uid: uid, lat: lat, lng: lng);

    await _crearAlertaSOS(
      uid: uid,
      nombre: nombre,
      email: email,
      guardianIds: guardianIds,
      lat: lat,
      lng: lng,
      mapUrl: mapUrl,
    );

    try {
      await _db.collection('notices').add({
        'tipo': 'sos',
        'titulo': 'SOS Activado',
        'mensaje':
            '$nombre activó una alerta de emergencia. Ubicación: lat $lat, lng $lng',
        'timestamp': FieldValue.serverTimestamp(),
        'destinatarios': destinatarios,
        'creadoPor': uid,
        'leido': false,
        'icono': 'sos',
        'color': 'red',
        'ubicacion': {
          'lat': lat,
          'lng': lng,
        },
      });
    } catch (_) {
      // La alerta para agentes ya se creó; no bloqueamos el SOS por avisos.
    }
  }

  Future<void> _crearAlertaSOS({
    required String uid,
    required String nombre,
    required String email,
    required List<String> guardianIds,
    required double lat,
    required double lng,
    required String mapUrl,
  }) async {
    try {
      await _crearAlertaBackend(
        uid: uid,
        nombre: nombre,
        email: email,
        guardianIds: guardianIds,
        lat: lat,
        lng: lng,
        mapUrl: mapUrl,
      );
    } on DuplicateSosLocationException {
      rethrow;
    } catch (_) {
      await _crearAlertaFirestore(
        uid: uid,
        nombre: nombre,
        email: email,
        guardianIds: guardianIds,
        lat: lat,
        lng: lng,
        mapUrl: mapUrl,
      );
    }
  }

  Future<void> _assertNoActiveSosAtLocation({
    required String uid,
    required double lat,
    required double lng,
  }) async {
    final snap = await _db
        .collection('dashboard_alerts')
        .where('userId', isEqualTo: uid)
        .limit(30)
        .get();

    for (final doc in snap.docs) {
      final data = doc.data();
      final status = '${data['status'] ?? data['estado'] ?? 'active'}'
          .trim()
          .toLowerCase();
      if (status == 'closed' || status == 'cerrada' || status == 'cerrado') {
        continue;
      }

      final existingLat = _readDouble(data['lat']) ??
          (data['location'] is Map
              ? _readDouble(data['location']['lat'])
              : null);
      final existingLng = _readDouble(data['lng']) ??
          (data['location'] is Map
              ? _readDouble(data['location']['lng'])
              : null);

      if (existingLat == null || existingLng == null) continue;

      final distance = _distanceMeters(lat, lng, existingLat, existingLng);
      if (distance <= _duplicateLocationRadiusMeters) {
        throw const DuplicateSosLocationException();
      }
    }
  }

  double? _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  double _distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return earthRadiusMeters * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _toRadians(double degrees) => degrees * pi / 180;

  Future<void> _crearAlertaFirestore({
    required String uid,
    required String nombre,
    required String email,
    required List<String> guardianIds,
    required double lat,
    required double lng,
    required String mapUrl,
  }) async {
    final alertData = {
      'type': 'sos',
      'status': 'active',
      'estado': 'active',
      'priority': 'high',
      'prioridad': 'Alta',
      'title': 'SOS Activado',
      'message': '$nombre activó una alerta de emergencia',
      'persona': nombre,
      'correoPersona': email,
      'ubicacion': 'lat $lat, lng $lng',
      'mapUrl': mapUrl,
      'userId': uid,
      'userName': nombre,
      'userEmail': email,
      'guardianIds': guardianIds,
      'agenteAsignado': 'Sin asignar',
      'location': {
        'lat': lat,
        'lng': lng,
      },
      'ubicacionActiva': {
        'lat': lat,
        'lng': lng,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'lat': lat,
      'lng': lng,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'source': 'mobile_app',
    };

    final dashboardAlertRef = _db.collection('dashboard_alerts').doc();
    final sosAlertRef = _db.collection('sos_alerts').doc(dashboardAlertRef.id);
    final batch = _db.batch();
    batch.set(dashboardAlertRef, alertData);
    batch.set(sosAlertRef, {
      ...alertData,
      'dashboardAlertId': dashboardAlertRef.id,
    });
    await batch.commit();
  }

  Future<void> _crearAlertaBackend({
    required String uid,
    required String nombre,
    required String email,
    required List<String> guardianIds,
    required double lat,
    required double lng,
    required String mapUrl,
  }) async {
    final token = await _auth.currentUser?.getIdToken(true);
    if (token == null) throw Exception('Usuario no autenticado');

    final payload = jsonEncode({
      'uid': uid,
      'userName': nombre,
      'userEmail': email,
      'guardianIds': guardianIds,
      'lat': lat,
      'lng': lng,
      'mapUrl': mapUrl,
    });

    Object? lastError;
    for (final baseUrl in _backendBaseUrls) {
      try {
        final response = await http
            .post(
              Uri.parse('$baseUrl/api/auth/dashboard-alert'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: payload,
            )
            .timeout(const Duration(seconds: 6));

        if (response.statusCode >= 200 && response.statusCode < 300) return;
        if (response.statusCode == 409) {
          throw const DuplicateSosLocationException();
        }
        lastError = response.body;
      } catch (error) {
        lastError = error;
      }
    }

    throw Exception('No se pudo crear la alerta SOS: $lastError');
  }

  List<String> get _backendBaseUrls {
    const configuredUrl = String.fromEnvironment('API_BASE_URL');
    final urls = <String>[
      if (configuredUrl.trim().isNotEmpty) configuredUrl.trim(),
      'http://192.168.101.12:3000',
      'http://127.0.0.1:3000',
      'http://localhost:3000',
      'http://10.0.2.2:3000',
    ];

    return urls.toSet().toList(growable: false);
  }

  Future<void> marcarLeido(String noticeId) async {
    await _db.collection('notices').doc(noticeId).update({'leido': true});
  }

  Future<void> marcarTodosLeidos() async {
    final uid = _uid;
    if (uid == null) return;

    final snap = await _db
        .collection('notices')
        .where('destinatarios', arrayContains: uid)
        .where('leido', isEqualTo: false)
        .get();

    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'leido': true});
    }
    await batch.commit();
  }

  Stream<int> contadorNoLeidos() {
    final uid = _uid;
    if (uid == null) return Stream.value(0);

    return _db
        .collection('notices')
        .where('destinatarios', arrayContains: uid)
        .where('leido', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }
}
