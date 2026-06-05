import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

// ─────────────────────────────────────────────────────────
//  MODELO: Zona Peligrosa
// ─────────────────────────────────────────────────────────
class DangerZone {
  final String id;
  final double lat;
  final double lng;
  final double radiusMeters;
  final String nombre;
  final String descripcion;

  DangerZone({
    required this.id,
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    required this.nombre,
    required this.descripcion,
  });

  factory DangerZone.fromMap(String id, Map<String, dynamic> data) {
    return DangerZone(
      id: id,
      lat: (data['lat'] as num).toDouble(),
      lng: (data['lng'] as num).toDouble(),
      radiusMeters: (data['radiusMeters'] as num?)?.toDouble() ?? 300,
      nombre: data['nombre'] ?? 'Zona Peligrosa',
      descripcion: data['descripcion'] ?? 'Área de riesgo reportada.',
    );
  }
}

// ─────────────────────────────────────────────────────────
//  LOCATION SERVICE
// ─────────────────────────────────────────────────────────
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  StreamSubscription<Position>? _gpsSub;

  // IDs de zonas ya notificadas en esta sesión (para no repetir)
  final Set<String> _zonasNotificadas = {};

  String? get _uid => _auth.currentUser?.uid;

  // ── Iniciar tracking continuo ──────────────────────────
  Future<void> iniciarTracking() async {
    await _gpsSub?.cancel();

    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15, // cada 15 metros
      ),
    ).listen((pos) async {
      await _guardarUbicacion(pos);
      await _verificarZonasPeligrosas(pos);
    });
  }

  // ── Detener tracking ───────────────────────────────────
  Future<void> detenerTracking() async {
    await _gpsSub?.cancel();
    _gpsSub = null;
  }

  // ── Guardar ubicación en Firestore ─────────────────────
  Future<void> _guardarUbicacion(Position pos) async {
    final uid = _uid;
    if (uid == null) return;

    await _db.collection('users').doc(uid).set({
      'location': {
        'lat': pos.latitude,
        'lng': pos.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));

    try {
      await _actualizarAlertasActivas(uid, pos);
    } catch (_) {
      // La ubicacion del perfil ya quedo guardada; no detenemos el GPS por
      // un fallo temporal al reflejarla en las alertas.
    }
  }

  Future<void> _actualizarAlertasActivas(String uid, Position pos) async {
    final snap = await _db
        .collection('dashboard_alerts')
        .where('userId', isEqualTo: uid)
        .limit(10)
        .get();

    final ubicacionActiva = {
      'lat': pos.latitude,
      'lng': pos.longitude,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final update = {
      'ubicacionActiva': ubicacionActiva,
      'mapUrl':
          'https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}',
      'updatedAt': FieldValue.serverTimestamp(),
    };

    for (final doc in snap.docs) {
      final data = doc.data();
      final status = '${data['status'] ?? data['estado'] ?? 'active'}'
          .trim()
          .toLowerCase();
      if (status == 'closed' || status == 'cerrada' || status == 'cerrado') {
        continue;
      }

      await doc.reference.set(update, SetOptions(merge: true));
      for (final collectionName in ['sos_alerts', 'alertas_activas']) {
        await _db
            .collection(collectionName)
            .doc(doc.id)
            .set(update, SetOptions(merge: true));
      }
    }
  }

  // ── Verificar zonas peligrosas cercanas ─────────────────
  Future<void> _verificarZonasPeligrosas(Position pos) async {
    final uid = _uid;
    if (uid == null) return;

    // Leer zonas peligrosas de Firestore
    final snap = await _db.collection('danger_zones').get();

    for (final doc in snap.docs) {
      final zona = DangerZone.fromMap(doc.id, doc.data());

      final distancia = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        zona.lat,
        zona.lng,
      );

      final dentroDeZona = distancia <= zona.radiusMeters;
      final yaNotificado = _zonasNotificadas.contains(zona.id);

      if (dentroDeZona && !yaNotificado) {
        // Crear notice para este usuario
        await _db.collection('notices').add({
          'tipo': 'zona_peligrosa',
          'titulo': '⚠️ Zona de Riesgo',
          'mensaje': 'Estás cerca de: ${zona.nombre}. ${zona.descripcion}',
          'timestamp': FieldValue.serverTimestamp(),
          'destinatarios': [uid],
          'creadoPor': 'sistema',
          'leido': false,
          'icono': 'warning',
          'color': 'red',
        });

        _zonasNotificadas.add(zona.id);
      }

      // Si sale de la zona, permitir que vuelva a notificar en el futuro
      if (!dentroDeZona && yaNotificado) {
        _zonasNotificadas.remove(zona.id);
      }
    }
  }

  // ── Obtener ubicación actual una sola vez ──────────────
  Future<Position?> obtenerPosicionActual() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (_) {
      return null;
    }
  }
}
