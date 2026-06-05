import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;

import '/services/notice_service.dart';
import '/services/chat_service.dart';
import '/services/location_services.dart';
import 'chat_detail.dart';

class _Place {
  final String name;
  final ll.LatLng pos;
  _Place(this.name, this.pos);
}

// ─────────────────────────────────────────────────────────
//  PANTALLA GUARDIAN
// ─────────────────────────────────────────────────────────
class GuardianScreen extends StatefulWidget {
  const GuardianScreen({super.key});

  @override
  State<GuardianScreen> createState() => _GuardianScreenState();
}

class _GuardianScreenState extends State<GuardianScreen>
    with SingleTickerProviderStateMixin {
  // ── Colores corporativos SOS.LIVE ───────────────────────
  static const Color azulSOS = Color(0xFF002133);
  static const Color doradoSOS = Color(0xFFD4AF37);
  static const Color rojoSOS = Color(0xFFE53935);
  static const Color verdeSOS = Color(0xFF2ECC71);

  // ── Cooldown SOS: 1 hora entre alertas ─────────────────

  final NoticeService _noticeService = NoticeService();
  final ChatService _chatService = ChatService();
  final LocationService _locationService = LocationService();

  // ── Mapa ────────────────────────────────────────────────
  final MapController _mapController = MapController();
  ll.LatLng _ubicacionActual = const ll.LatLng(4.666, -74.117);
  double _heading = 0;
  bool _gpsListo = false;
  bool _siguiendoUsuario = true;

  // ── GPS stream ──────────────────────────────────────────
  StreamSubscription<Position>? _gpsSub;

  // ── Ruta ────────────────────────────────────────────────
  List<ll.LatLng> _rutaPuntos = [];
  ll.LatLng? _destino;
  String _destinoNombre = '';
  bool _calculandoRuta = false;
  String _distanciaTexto = '';
  String _tiempoTexto = '';

  // ── Búsqueda Nominatim ──────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  final DraggableScrollableController _panelController =
      DraggableScrollableController();
  List<_Place> _sugerencias = [];
  bool _buscando = false;
  Timer? _debounceTimer;

  // ── Historial recientes (estático por ahora) ────────────
  final List<Map<String, String>> _historialRecientes = [
    {"titulo": "Avenida Boyacá calle 66a", "fecha": "Viernes - 12:37 am"},
    {"titulo": "Portal Calle 80", "fecha": "Lunes - 5:30 am"},
  ];

  // ── Modo pánico ─────────────────────────────────────────
  bool _modoPanico = false;
  int _panicSegundos = 5;
  Timer? _panicTimer;
  late AnimationController _panicAnim;
  late Animation<double> _panicPulse;

  // ── Hora en vivo ────────────────────────────────────────
  late Timer _clockTimer;
  String _horaActual = '';

  // ════════════════════════════════════════════════════════
  //  CICLO DE VIDA
  // ════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();

    // Animación pánico
    _panicAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _panicPulse = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _panicAnim, curve: Curves.easeInOut),
    );

    _actualizarHora();
    _clockTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _actualizarHora());
    _iniciarGPS();
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _panicAnim.dispose();
    _panicTimer?.cancel();
    _clockTimer.cancel();
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════
  // ════════════════════════════════════════════════════════

  // ════════════════════════════════════════════════════════
  //  GPS
  // ════════════════════════════════════════════════════════
  Future<void> _iniciarGPS() async {
    bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      _mostrarSnack('⚠️ Activa el GPS del dispositivo', error: true);
      return;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        _mostrarSnack('Permiso de ubicación denegado', error: true);
        return;
      }
    }
    if (perm == LocationPermission.deniedForever) {
      _mostrarSnack('Permiso bloqueado. Actívalo en Ajustes', error: true);
      return;
    }

    // Posición inicial rápida
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    if (!mounted) return;
    setState(() {
      _ubicacionActual = ll.LatLng(pos.latitude, pos.longitude);
      _heading = pos.heading;
      _gpsListo = true;
    });
    _mapController.move(_ubicacionActual, 17.0);

    // Stream continuo
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((p) {
      if (!mounted) return;
      setState(() {
        _ubicacionActual = ll.LatLng(p.latitude, p.longitude);
        _heading = p.heading;
      });
      if (_siguiendoUsuario) {
        _mapController.move(_ubicacionActual, _mapController.camera.zoom);
      }
    });

    await _locationService.iniciarTracking();
  }

  // ════════════════════════════════════════════════════════
  //  HORA
  // ════════════════════════════════════════════════════════
  void _actualizarHora() {
    final now = DateTime.now();
    final dias = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo'
    ];
    final min = now.minute.toString().padLeft(2, '0');
    final ampm = now.hour >= 12 ? 'pm' : 'am';
    final h12 = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    setState(() {
      _horaActual = '${dias[now.weekday - 1]} - $h12:$min $ampm';
    });
  }

  // ════════════════════════════════════════════════════════
  //  BÚSQUEDA NOMINATIM
  // ════════════════════════════════════════════════════════
  Future<void> _buscarLugar(String query) async {
    if (query.length < 3) {
      setState(() => _sugerencias = []);
      return;
    }
    setState(() => _buscando = true);

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=json&limit=5'
        '&lat=${_ubicacionActual.latitude}&lon=${_ubicacionActual.longitude}'
        '&countrycodes=co',
      );
      final resp = await http.get(url, headers: {
        'Accept-Language': 'es',
        'User-Agent': 'SOS.LIVE/1.0',
      }).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List;
        setState(() {
          _sugerencias = data
              .map<_Place>((e) => _Place(
                    e['display_name'],
                    ll.LatLng(
                      double.parse(e['lat']),
                      double.parse(e['lon']),
                    ),
                  ))
              .toList();
          _buscando = false;
        });
      }
    } on TimeoutException {
      setState(() => _buscando = false);
      _mostrarSnack('⏱️ Búsqueda tardó demasiado', error: true);
    } catch (_) {
      setState(() => _buscando = false);
    }
  }

  // ════════════════════════════════════════════════════════
  //  RUTA OSRM
  // ════════════════════════════════════════════════════════
  Future<void> _calcularRuta(ll.LatLng destino, String nombre) async {
    setState(() {
      _calculandoRuta = true;
      _destino = destino;
      _destinoNombre = nombre;
      _rutaPuntos = [];
      _sugerencias = [];
    });

    // Cerrar panel al calcular ruta
    _panelController.animateTo(
      0.12,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${_ubicacionActual.longitude},${_ubicacionActual.latitude};'
        '${destino.longitude},${destino.latitude}'
        '?overview=full&geometries=geojson&steps=true',
      );
      final resp = await http.get(url).timeout(const Duration(seconds: 12));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final routes = data['routes'] as List;
        if (routes.isEmpty) {
          _mostrarSnack('No se encontró ruta', error: true);
          setState(() => _calculandoRuta = false);
          return;
        }

        final route = routes[0];
        final coords = route['geometry']['coordinates'] as List;
        final distM = (route['distance'] as num).toDouble();
        final durSec = (route['duration'] as num).toDouble();

        final puntos = coords
            .map<ll.LatLng>((c) => ll.LatLng(c[1].toDouble(), c[0].toDouble()))
            .toList();

        final minLat = puntos.map((p) => p.latitude).reduce(min);
        final maxLat = puntos.map((p) => p.latitude).reduce(max);
        final minLng = puntos.map((p) => p.longitude).reduce(min);
        final maxLng = puntos.map((p) => p.longitude).reduce(max);

        setState(() {
          _rutaPuntos = puntos;
          _calculandoRuta = false;
          _distanciaTexto = distM < 1000
              ? '${distM.toStringAsFixed(0)} m'
              : '${(distM / 1000).toStringAsFixed(1)} km';
          _tiempoTexto = durSec < 60
              ? '${durSec.toStringAsFixed(0)} seg'
              : '${(durSec / 60).toStringAsFixed(0)} min';
          _siguiendoUsuario = false;
        });

        final bounds = LatLngBounds(
          ll.LatLng(minLat - 0.002, minLng - 0.002),
          ll.LatLng(maxLat + 0.002, maxLng + 0.002),
        );
        _mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(40)),
        );

        _mostrarSnack('✅ Ruta a $nombre calculada');
      }
    } on TimeoutException {
      setState(() => _calculandoRuta = false);
      _mostrarSnack('⏱️ La solicitud tardó demasiado', error: true);
    } catch (e) {
      setState(() => _calculandoRuta = false);
      _mostrarSnack('Error al calcular ruta: $e', error: true);
    }
  }

  void _cancelarRuta() {
    setState(() {
      _rutaPuntos = [];
      _destino = null;
      _destinoNombre = '';
      _distanciaTexto = '';
      _tiempoTexto = '';
      _siguiendoUsuario = true;
    });
    _mapController.move(_ubicacionActual, 17.0);
  }

  // ════════════════════════════════════════════════════════
  //  MODO PÁNICO — con cooldown anti-spam
  // ════════════════════════════════════════════════════════
  void _activarPanico() {
    HapticFeedback.heavyImpact();
    setState(() {
      _modoPanico = true;
      _panicSegundos = 5;
    });
    _panicTimer?.cancel();
    _panicTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _panicSegundos--);
      HapticFeedback.heavyImpact();
      if (_panicSegundos <= 0) {
        t.cancel();
        _ejecutarSOS();
      }
    });
  }

  void _cancelarPanico() {
    _panicTimer?.cancel();
    setState(() => _modoPanico = false);
    _mostrarSnack('✅ Alerta SOS cancelada');
  }

  Future<void> _ejecutarSOS() async {
    setState(() => _modoPanico = false);

    try {
      await _noticeService.crearNoticeSOS(
        lat: _ubicacionActual.latitude,
        lng: _ubicacionActual.longitude,
      );
      _mostrarSnack('🚨 ALERTA SOS ENVIADA — Agentes notificados');
    } on DuplicateSosLocationException {
      _mostrarSnack(
        'Ya tienes una alerta activa en esta ubicacion. Muevete para enviar otra.',
        error: true,
      );
    } catch (e) {
      _mostrarSnack('Error al enviar SOS: $e', error: true);
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>? _activeAlertStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('dashboard_alerts')
        .where('userId', isEqualTo: uid)
        .snapshots();
  }

  MapEntry<String, Map<String, dynamic>>? _pickActiveAlert(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final activeDocs = snapshot.docs.where((doc) {
      final data = doc.data();
      final status = (data['status'] ?? data['estado'] ?? 'active')
          .toString()
          .toLowerCase();
      return status != 'closed' &&
          status != 'cerrada' &&
          status != 'cerrado' &&
          status != 'finalizado' &&
          status != 'cancelado';
    }).toList();

    if (activeDocs.isEmpty) return null;
    activeDocs.sort((a, b) {
      final aDate = (a.data()['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = (b.data()['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    final doc = activeDocs.first;
    return MapEntry(doc.id, doc.data());
  }

  bool _isAcceptedAlert(Map<String, dynamic> alert) {
    final status =
        (alert['status'] ?? alert['estado'] ?? '').toString().toLowerCase();
    final assigned = (alert['agenteAsignado'] ?? alert['acceptedBy'] ?? '')
        .toString()
        .trim();
    return status == 'accepted' ||
        status == 'aceptada' ||
        status == 'aceptado' ||
        (assigned.isNotEmpty && assigned.toLowerCase() != 'sin asignar');
  }

  ll.LatLng? _agentPositionFromAlert(Map<String, dynamic> alert) {
    final location = alert['agentLocation'] is Map
        ? alert['agentLocation'] as Map
        : alert['guardianLocation'] is Map
            ? alert['guardianLocation'] as Map
            : null;
    final lat = _readDouble(location?['lat']);
    final lng = _readDouble(location?['lng']);
    if (lat == null || lng == null) return null;
    return ll.LatLng(lat, lng);
  }

  double? _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Future<void> _openGuardianChat(Map<String, dynamic> alert) async {
    var agentId = (alert['agentId'] ??
            alert['agentUid'] ??
            alert['acceptedById'] ??
            alert['guardianId'] ??
            '')
        .toString()
        .trim();
    final agentName =
        (alert['agenteAsignado'] ?? alert['acceptedBy'] ?? 'Guardián SOS')
            .toString();

    if (agentId.isEmpty && agentName.trim().isNotEmpty) {
      final agent = await _chatService.getAgentByName(agentName);
      agentId = (agent?['uid'] ?? '').toString().trim();
    }

    if (agentId.isEmpty) {
      _mostrarSnack('Aún no se encontró el usuario del guardián', error: true);
      return;
    }

    try {
      final chatId = await _chatService.openOrCreateChat(
        agentId,
        otherName: agentName,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            chatId: chatId,
            otherUserId: agentId,
            otherUserName: agentName,
          ),
        ),
      );
    } catch (e) {
      _mostrarSnack('No se pudo abrir el chat: $e', error: true);
    }
  }

  Future<void> _closeAlertFromPerson(
    String alertId,
    Map<String, dynamic> alert,
  ) async {
    final rating = await _showRatingDialog(alert);
    if (rating == null) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _mostrarSnack('Debes iniciar sesión para cerrar la alerta', error: true);
      return;
    }

    final update = {
      'status': 'closed',
      'estado': 'closed',
      'closedBy': uid,
      'closedByRole': 'persona',
      'closedAt': FieldValue.serverTimestamp(),
      'rating': rating['score'],
      'ratingComment': rating['comment'],
      'ratedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      final db = FirebaseFirestore.instance;
      await db.collection('dashboard_alerts').doc(alertId).update(update);
      for (final collectionName in ['sos_alerts', 'alertas_activas']) {
        try {
          await db.collection(collectionName).doc(alertId).update(update);
        } catch (_) {}
      }
      try {
        await db.collection('service_ratings').add({
          'alertId': alertId,
          'userId': uid,
          'agentId': alert['agentId'],
          'agentName': alert['agenteAsignado'] ?? alert['acceptedBy'],
          'score': rating['score'],
          'comment': rating['comment'],
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
      await _locationService.detenerTracking();
      _mostrarSnack('Servicio finalizado y calificado');
    } catch (e) {
      _mostrarSnack('No se pudo cerrar la alerta: $e', error: true);
    }
  }

  Future<Map<String, dynamic>?> _showRatingDialog(
    Map<String, dynamic> alert,
  ) async {
    final agentName =
        (alert['agenteAsignado'] ?? alert['acceptedBy'] ?? 'el guardián')
            .toString();

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _RatingDialog(agentName: agentName),
    );

    /*
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: azulSOS,
          scrollable: true,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: doradoSOS, width: 1.3),
          ),
          title: const Text(
            'Califica el servicio',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '¿Cómo fue la atención de $agentName?',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final value = index + 1;
                  return IconButton(
                    onPressed: () => setDialogState(() => score = value),
                    icon: Icon(
                      value <= score ? Icons.star : Icons.star_border,
                      color: doradoSOS,
                      size: 34,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentCtrl,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Comentario opcional',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar',
                  style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: doradoSOS),
              onPressed: () => Navigator.pop(ctx, {
                'score': score,
                'comment': commentCtrl.text.trim(),
              }),
              child: const Text(
                'Finalizar',
                style:
                    TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );

    commentCtrl.dispose();
    return result;
    */
  }

  // ════════════════════════════════════════════════════════
  //  UTILIDADES
  // ════════════════════════════════════════════════════════
  void _mostrarSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? rojoSOS : const Color(0xFF1A3A45),
      duration: const Duration(seconds: 3),
    ));
  }

  // ════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: azulSOS,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ── 1. MAPA ──────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _ubicacionActual,
              initialZoom: 16.0,
              onPositionChanged: (_, hasGesture) {
                if (hasGesture) {
                  setState(() => _siguiendoUsuario = false);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.sos_live',
              ),

              // Línea de ruta
              if (_rutaPuntos.isNotEmpty)
                PolylineLayer(polylines: [
                  Polyline(
                    points: _rutaPuntos,
                    color: doradoSOS,
                    strokeWidth: 5.0,
                    borderColor: azulSOS.withOpacity(0.4),
                    borderStrokeWidth: 2,
                  ),
                ]),

              // Marcadores
              MarkerLayer(markers: [
                // Marcador usuario con heading
                Marker(
                  point: _ubicacionActual,
                  width: 60,
                  height: 60,
                  child: Transform.rotate(
                    angle: _heading * (pi / 180),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: azulSOS,
                        border: Border.all(color: doradoSOS, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: doradoSOS.withOpacity(0.4),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.navigation_rounded,
                          color: Colors.white, size: 28),
                    ),
                  ),
                ),

                // Marcador destino
                if (_destino != null)
                  Marker(
                    point: _destino!,
                    width: 48,
                    height: 48,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: rojoSOS,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: rojoSOS.withOpacity(0.5),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.flag_rounded,
                          color: Colors.white, size: 24),
                    ),
                  ),
              ]),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _activeAlertStream(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final activeAlert = _pickActiveAlert(snapshot.data!);
                  final alert = activeAlert?.value;
                  if (alert == null || !_isAcceptedAlert(alert)) {
                    return const SizedBox.shrink();
                  }

                  final agentPosition = _agentPositionFromAlert(alert);
                  if (agentPosition == null) return const SizedBox.shrink();

                  return MarkerLayer(markers: [
                    Marker(
                      point: agentPosition,
                      width: 58,
                      height: 58,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: verdeSOS,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: verdeSOS.withOpacity(0.45),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.security_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ]);
                },
              ),
            ],
          ),

          // ── 2. OVERLAY PÁNICO ────────────────────────────
          if (_modoPanico)
            Positioned.fill(
              child: Container(
                color: rojoSOS.withOpacity(0.18),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: _panicPulse,
                        child: Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: rojoSOS,
                            boxShadow: [
                              BoxShadow(
                                color: rojoSOS.withOpacity(0.6),
                                blurRadius: 40,
                                spreadRadius: 15,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: Colors.white, size: 56),
                              Text(
                                '$_panicSegundos',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 40,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const Text('segundos',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      const Text(
                        '¡ENVIANDO ALERTA SOS!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 8)
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _cancelarPanico,
                        icon: const Icon(Icons.close, color: Colors.white),
                        label: const Text(
                          'CANCELAR',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: azulSOS,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── 3. TOP BAR ───────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [azulSOS, azulSOS.withOpacity(0)],
                ),
              ),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                right: 16,
                bottom: 20,
              ),
              child: Row(
                children: [
                  // Logo
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: azulSOS,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: doradoSOS, width: 1.5),
                    ),
                    child: const Text(
                      'SOS.LIVE',
                      style: TextStyle(
                        color: doradoSOS,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const Spacer(),

                  // Botón centrar GPS
                  _topBtn(
                    icon: _siguiendoUsuario
                        ? Icons.my_location_rounded
                        : Icons.location_searching_rounded,
                    color: _siguiendoUsuario ? doradoSOS : Colors.white70,
                    onTap: () {
                      setState(() => _siguiendoUsuario = true);
                      _mapController.move(_ubicacionActual, 17.0);
                    },
                  ),

                  const SizedBox(width: 10),

                  // ── Botón SOS con estado de cooldown ─────
                  GestureDetector(
                    onTap: _activarPanico,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        // Gris cuando está en cooldown, rojo cuando disponible
                        color: rojoSOS,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: rojoSOS.withOpacity(0.5),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'SOS',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Tooltip cooldown bajo el botón SOS ────────────
          // ── 4. PANEL INFO RUTA ────────────────────────────
          if (_rutaPuntos.isNotEmpty)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: azulSOS,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: doradoSOS.withOpacity(0.5)),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 12),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: rojoSOS.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.flag_rounded,
                          color: rojoSOS, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _destinoNombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.straighten,
                                  color: doradoSOS, size: 14),
                              const SizedBox(width: 4),
                              Text(_distanciaTexto,
                                  style: const TextStyle(
                                      color: doradoSOS, fontSize: 13)),
                              const SizedBox(width: 14),
                              const Icon(Icons.schedule_rounded,
                                  color: Colors.white54, size: 14),
                              const SizedBox(width: 4),
                              Text(_tiempoTexto,
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 13)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _cancelarRuta,
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ),

          // ── 5. CALCULANDO RUTA ────────────────────────────
          if (_calculandoRuta)
            Positioned(
              bottom: 160,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: azulSOS,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: doradoSOS.withOpacity(0.5)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: doradoSOS, strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Calculando ruta...',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── 6. PANEL DESLIZABLE CON BÚSQUEDA ─────────────
          if (!_modoPanico)
            Positioned(
              left: 16,
              right: 16,
              bottom: 112,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _activeAlertStream(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final activeAlert = _pickActiveAlert(snapshot.data!);
                  if (activeAlert == null) return const SizedBox.shrink();
                  return _buildActiveAlertCard(
                    alertId: activeAlert.key,
                    alert: activeAlert.value,
                  );
                },
              ),
            ),

          if (!_modoPanico)
            DraggableScrollableSheet(
              controller: _panelController,
              initialChildSize: 0.30,
              minChildSize: 0.12,
              maxChildSize: 0.92,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: azulSOS,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(35)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 15,
                      ),
                    ],
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(25, 15, 25, 25),
                    children: [
                      // Handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Barra de búsqueda funcional ───────
                      TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: '¿A dónde vas a ir hoy?',
                          hintStyle:
                              TextStyle(color: Colors.white.withOpacity(0.4)),
                          prefixIcon:
                              const Icon(Icons.search, color: doradoSOS),
                          suffixIcon: _buscando
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: doradoSOS,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : _searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(Icons.close,
                                          color: Colors.white.withOpacity(0.5)),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        setState(() => _sugerencias = []);
                                      },
                                    )
                                  : Icon(Icons.mic,
                                      color: Colors.white.withOpacity(0.7)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (v) {
                          _debounceTimer?.cancel();
                          _debounceTimer = Timer(
                            const Duration(milliseconds: 500),
                            () => _buscarLugar(v),
                          );
                          setState(() {});
                        },
                      ),

                      // ── Sugerencias de búsqueda ───────────
                      if (_sugerencias.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: _sugerencias.take(5).map((p) {
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.place_outlined,
                                    color: doradoSOS, size: 20),
                                title: Text(
                                  p.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                ),
                                onTap: () {
                                  _searchCtrl.clear();
                                  _calcularRuta(
                                    p.pos,
                                    p.name.split(',').first,
                                  );
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ],

                      // ── Recientes (cuando no hay búsqueda) ─
                      if (_sugerencias.isEmpty && _searchCtrl.text.isEmpty) ...[
                        const SizedBox(height: 25),
                        Row(
                          children: [
                            const Text(
                              'Recientes',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            // Indicador GPS
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _gpsListo
                                    ? verdeSOS.withOpacity(0.15)
                                    : rojoSOS.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.gps_fixed_rounded,
                                    color: _gpsListo ? verdeSOS : rojoSOS,
                                    size: 11,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _gpsListo ? 'GPS activo' : 'Sin GPS',
                                    style: TextStyle(
                                      color: _gpsListo ? verdeSOS : rojoSOS,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._historialRecientes.map((item) =>
                            _buildRecentTile(item['titulo']!, item['fecha']!)),
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
      ),

      // ── BOTTOM NAV ────────────────────────────────────────
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  // ════════════════════════════════════════════════════════
  //  WIDGETS AUXILIARES
  // ════════════════════════════════════════════════════════
  Widget _buildActiveAlertCard({
    required String alertId,
    required Map<String, dynamic> alert,
  }) {
    final accepted = _isAcceptedAlert(alert);
    final agentName =
        (alert['agenteAsignado'] ?? alert['acceptedBy'] ?? '').toString();
    final title = accepted ? 'Guardián en camino' : 'Alerta enviada';
    final subtitle = accepted
        ? 'Asignado: ${agentName.isEmpty ? 'Guardián SOS' : agentName}'
        : 'Esperando que un guardián acepte tu alerta';

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: azulSOS,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accepted ? verdeSOS : doradoSOS,
            width: 1.4,
          ),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 14),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accepted
                    ? verdeSOS.withOpacity(0.18)
                    : rojoSOS.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(
                accepted ? Icons.verified_user : Icons.sos,
                color: accepted ? verdeSOS : rojoSOS,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (accepted)
              IconButton(
                tooltip: 'Chat',
                onPressed: () => _openGuardianChat(alert),
                icon: const Icon(Icons.chat_bubble, color: doradoSOS),
              ),
            if (accepted)
              ElevatedButton(
                onPressed: () => _closeAlertFromPerson(alertId, alert),
                style: ElevatedButton.styleFrom(
                  backgroundColor: verdeSOS,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Finalizar',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentTile(String title, String subtitle) {
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.access_time_filled,
                color: Colors.white.withOpacity(0.7), size: 20),
          ),
          title: Text(title,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w500)),
          subtitle: Text(subtitle,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.4), fontSize: 12)),
          onTap: () {
            // TODO: buscar y navegar al lugar del historial
          },
        ),
        Divider(color: Colors.white.withOpacity(0.05), indent: 50),
      ],
    );
  }

  Widget _topBtn({
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: azulSOS.withOpacity(0.9),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white12),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 8),
          ],
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: BottomNavigationBar(
        currentIndex: 1,
        backgroundColor: azulSOS,
        selectedItemColor: doradoSOS,
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          if (index == 1) return;
          const routes = ['/profile', '', '/maps', '/chats', '/notices'];
          Navigator.pushReplacementNamed(context, routes[index]);
        },
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Perfil'),
          BottomNavigationBarItem(
              icon: Icon(Icons.shield_outlined),
              activeIcon: Icon(Icons.shield),
              label: 'Guardian'),
          BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map),
              label: 'Mapa'),
          BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              activeIcon: Icon(Icons.chat_bubble),
              label: 'Chats'),
          BottomNavigationBarItem(
              icon: Icon(Icons.notifications_none),
              activeIcon: Icon(Icons.notifications),
              label: 'Avisos'),
        ],
      ),
    );
  }
}

class _RatingDialog extends StatefulWidget {
  final String agentName;

  const _RatingDialog({required this.agentName});

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  static const Color _azulSOS = Color(0xFF002133);
  static const Color _doradoSOS = Color(0xFFD4AF37);

  final TextEditingController _commentCtrl = TextEditingController();
  int _score = 5;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  void _finish() {
    Navigator.pop(context, {
      'score': _score,
      'comment': _commentCtrl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _azulSOS,
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _doradoSOS, width: 1.3),
      ),
      title: const Text(
        'Califica el servicio',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Como fue la atencion de ${widget.agentName}?',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final value = index + 1;
              return IconButton(
                onPressed: () => setState(() => _score = value),
                icon: Icon(
                  value <= _score ? Icons.star : Icons.star_border,
                  color: _doradoSOS,
                  size: 34,
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _commentCtrl,
            maxLines: 3,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Comentario opcional',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancelar',
            style: TextStyle(color: Colors.white54),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _doradoSOS),
          onPressed: _finish,
          child: const Text(
            'Finalizar',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
