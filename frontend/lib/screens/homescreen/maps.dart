import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;

import '/services/location_services.dart'; // ajusta el path a tu estructura
import '/services/notice_service.dart'; // ajusta el path a tu estructura
import '/services/device_alert_service.dart';

// ─────────────────────────────────────────────────────────
//  MODELO: Lugar de búsqueda
// ─────────────────────────────────────────────────────────
class _Place {
  final String name;
  final ll.LatLng pos;
  _Place(this.name, this.pos);
}

// ─────────────────────────────────────────────────────────
//  PANTALLA PRINCIPAL
// ─────────────────────────────────────────────────────────
class MapsScreen extends StatefulWidget {
  const MapsScreen({super.key});
  @override
  State<MapsScreen> createState() => _MapsScreenState();
}

class _MapsScreenState extends State<MapsScreen>
    with SingleTickerProviderStateMixin {
  // ── Colores corporativos ────────────────────────────────
  static const Color azul = Color(0xFF002133);
  static const Color dorado = Color(0xFFD4AF37);
  static const Color rojo = Color(0xFFE53935);
  static const Color verde = Color(0xFF2ECC71);

  // ── Servicios ───────────────────────────────────────────
  final LocationService _locationService = LocationService();
  final NoticeService _noticeService = NoticeService();

  // ── Mapa ────────────────────────────────────────────────
  final MapController _mapCtrl = MapController();
  ll.LatLng _miPos = const ll.LatLng(4.666, -74.117);
  double _heading = 0;
  bool _gpsListo = false;
  bool _siguiendoUsuario = true;

  // ── Ruta ────────────────────────────────────────────────
  List<ll.LatLng> _rutaPuntos = [];
  ll.LatLng? _destino;
  String _destinoNombre = '';
  bool _calculandoRuta = false;
  String _distanciaTexto = '';
  String _tiempoTexto = '';

  // ── Lugares seguros predefinidos ───────────────────────
  final List<Map<String, dynamic>> _lugaresSeguros = [
    {
      'nombre': 'Hospital Más Cercano',
      'icono': Icons.local_hospital,
      'tipo': 'hospital'
    },
    {
      'nombre': 'Policía Más Cercana',
      'icono': Icons.local_police,
      'tipo': 'police'
    },
    {'nombre': 'Bomberos', 'icono': Icons.fire_truck, 'tipo': 'fire_station'},
    {'nombre': 'Farmacia', 'icono': Icons.medication, 'tipo': 'pharmacy'},
  ];

  // ── Búsqueda ────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  List<_Place> _sugerencias = [];
  bool _buscando = false;
  Timer? _debounceTimer;
  bool _mostrarSearch = false;

  // ── Modo pánico ─────────────────────────────────────────
  bool _modoPanico = false;
  late AnimationController _panicAnim;
  late Animation<double> _panicPulse;
  Timer? _panicTimer;
  int _panicSegundos = 5;

  // ── GPS en tiempo real (solo para actualizar _miPos en UI) ─
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<void>? _volumeSosSub;

  // ── Hora en vivo ────────────────────────────────────────
  late Timer _clockTimer;
  String _horaActual = '';

  @override
  void initState() {
    super.initState();

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
    _volumeSosSub = DeviceAlertService.volumeSosPatternStream().listen((_) {
      if (mounted && !_modoPanico) {
        _activarPanico();
      }
    });
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _volumeSosSub?.cancel();
    _locationService.detenerTracking();
    _panicAnim.dispose();
    _panicTimer?.cancel();
    _clockTimer.cancel();
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Hora actual ──────────────────────────────────────────
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

  // ── Iniciar GPS ──────────────────────────────────────────
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
      _miPos = ll.LatLng(pos.latitude, pos.longitude);
      _heading = pos.heading;
      _gpsListo = true;
    });
    _mapCtrl.move(_miPos, 17.0);

    // ✅ Iniciar tracking con Firestore + detección de zonas peligrosas
    await _locationService.iniciarTracking();

    // Stream continuo solo para actualizar UI del mapa
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((p) {
      if (!mounted) return;
      setState(() {
        _miPos = ll.LatLng(p.latitude, p.longitude);
        _heading = p.heading;
      });
      if (_siguiendoUsuario) {
        _mapCtrl.move(_miPos, _mapCtrl.camera.zoom);
      }
    });
  }

  // ── OSRM: calcular ruta ──────────────────────────────────
  Future<void> _calcularRuta(ll.LatLng destino, String nombre) async {
    setState(() {
      _calculandoRuta = true;
      _destino = destino;
      _destinoNombre = nombre;
      _rutaPuntos = [];
    });

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${_miPos.longitude},${_miPos.latitude};'
        '${destino.longitude},${destino.latitude}'
        '?overview=full&geometries=geojson&steps=true',
      );
      final resp = await http.get(url).timeout(const Duration(seconds: 12));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final routes = data['routes'] as List;
        if (routes.isEmpty) {
          _mostrarSnack('No se encontró ruta', error: true);
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
        _mapCtrl.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(40)),
        );

        _mostrarSnack('✅ Ruta a $nombre calculada');
      }
    } on TimeoutException {
      setState(() => _calculandoRuta = false);
      _mostrarSnack('⏱️ La solicitud tardó demasiado, intenta de nuevo',
          error: true);
    } catch (e) {
      setState(() => _calculandoRuta = false);
      _mostrarSnack('Error al calcular ruta: $e', error: true);
    }
  }

  // ── Búsqueda de lugares (Nominatim/OSM) ─────────────────
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
        '&lat=${_miPos.latitude}&lon=${_miPos.longitude}'
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
      _mostrarSnack('⏱️ Búsqueda tardó demasiado, intenta de nuevo',
          error: true);
    } catch (_) {
      setState(() => _buscando = false);
    }
  }

  // ── Buscar lugar seguro cercano (Overpass) ───────────────
  Future<void> _irALugarSeguro(String tipo) async {
    setState(() => _calculandoRuta = true);
    try {
      final query = '[out:json];'
          'node["amenity"="$tipo"]'
          '(around:3000,${_miPos.latitude},${_miPos.longitude});'
          'out 1;';
      final url = Uri.parse(
          'https://overpass-api.de/api/interpreter?data=${Uri.encodeComponent(query)}');

      final resp = await http.get(url).timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final elements = data['elements'] as List;
        if (elements.isEmpty) {
          setState(() => _calculandoRuta = false);
          _mostrarSnack('No encontré $tipo cercano en 3 km', error: true);
          return;
        }
        final e = elements[0];
        final pos = ll.LatLng(e['lat'], e['lon']);
        final name = e['tags']?['name'] ?? tipo;
        await _calcularRuta(pos, name);
      } else {
        setState(() => _calculandoRuta = false);
        _mostrarSnack('Error en búsqueda de lugar', error: true);
      }
    } on TimeoutException {
      setState(() => _calculandoRuta = false);
      _mostrarSnack('⏱️ Servidor tardó mucho, intenta de nuevo', error: true);
    } catch (e) {
      setState(() => _calculandoRuta = false);
      _mostrarSnack('Error: $e', error: true);
    }
  }

  // ── Modo pánico ──────────────────────────────────────────
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

  // ✅ CONECTADO: SOS ahora crea notice en Firestore para guardianes
  Future<void> _ejecutarSOS() async {
    setState(() => _modoPanico = false);

    try {
      await _noticeService.crearNoticeSOS(
        lat: _miPos.latitude,
        lng: _miPos.longitude,
      );
      _mostrarSnack('🚨 ALERTA SOS ENVIADA — Guardanes notificados');
    } catch (e) {
      _mostrarSnack('Error al enviar SOS: $e', error: true);
    }
  }

  // ── Cancelar ruta ────────────────────────────────────────
  void _cancelarRuta() {
    setState(() {
      _rutaPuntos = [];
      _destino = null;
      _destinoNombre = '';
      _distanciaTexto = '';
      _tiempoTexto = '';
      _siguiendoUsuario = true;
    });
    _mapCtrl.move(_miPos, 17.0);
  }

  void _mostrarSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? rojo : const Color(0xFF1A3A45),
      duration: const Duration(seconds: 3),
    ));
  }

  // ─────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: azul,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ── 1. MAPA ──────────────────────────────────────
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _miPos,
              initialZoom: 16.0,
              onPositionChanged: (_, hasGesture) {
                if (hasGesture) setState(() => _siguiendoUsuario = false);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.sos_live.app',
              ),
              if (_rutaPuntos.isNotEmpty)
                PolylineLayer(polylines: [
                  Polyline(
                    points: _rutaPuntos,
                    color: dorado,
                    strokeWidth: 5.0,
                    borderColor: azul.withOpacity(0.4),
                    borderStrokeWidth: 2,
                  ),
                ]),
              MarkerLayer(markers: [
                // Usuario
                Marker(
                  point: _miPos,
                  width: 60,
                  height: 60,
                  child: Transform.rotate(
                    angle: _heading * (pi / 180),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: azul,
                        border: Border.all(color: dorado, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: dorado.withOpacity(0.4),
                            blurRadius: 12,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                      child: const Icon(Icons.navigation_rounded,
                          color: Colors.white, size: 28),
                    ),
                  ),
                ),

                // Destino
                if (_destino != null)
                  Marker(
                    point: _destino!,
                    width: 48,
                    height: 48,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: rojo,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: rojo.withOpacity(0.5),
                            blurRadius: 10,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                      child: const Icon(Icons.flag_rounded,
                          color: Colors.white, size: 24),
                    ),
                  ),
              ]),
            ],
          ),

          // ── 2. OVERLAY PÁNICO ────────────────────────────
          if (_modoPanico)
            Positioned.fill(
              child: Container(
                color: rojo.withOpacity(0.18),
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
                            color: rojo,
                            boxShadow: [
                              BoxShadow(
                                color: rojo.withOpacity(0.6),
                                blurRadius: 40,
                                spreadRadius: 15,
                              )
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
                        label: const Text('CANCELAR',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: azul,
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
                  colors: [azul, azul.withOpacity(0)],
                ),
              ),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                right: 16,
                bottom: 20,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: azul,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: dorado, width: 1.5),
                        ),
                        child: const Text('SOS.LIVE',
                            style: TextStyle(
                                color: dorado,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                      ),
                      const Spacer(),
                      _topBtn(
                        icon: Icons.search_rounded,
                        onTap: () => setState(() {
                          _mostrarSearch = !_mostrarSearch;
                          if (!_mostrarSearch) _sugerencias = [];
                        }),
                      ),
                      const SizedBox(width: 10),
                      _topBtn(
                        icon: _siguiendoUsuario
                            ? Icons.my_location_rounded
                            : Icons.location_searching_rounded,
                        color: _siguiendoUsuario ? dorado : Colors.white70,
                        onTap: () {
                          setState(() => _siguiendoUsuario = true);
                          _mapCtrl.move(_miPos, 17.0);
                        },
                      ),
                    ],
                  ),
                  if (_mostrarSearch) ...[
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 10)
                        ],
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        autofocus: true,
                        style: const TextStyle(color: Colors.black),
                        decoration: InputDecoration(
                          hintText: 'Buscar destino...',
                          hintStyle: const TextStyle(color: Colors.black45),
                          prefixIcon: const Icon(Icons.search,
                              color: Color(0xFF002133)),
                          suffixIcon: _buscando
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2)),
                                )
                              : _searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.close,
                                          color: Colors.black45),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        setState(() => _sugerencias = []);
                                      },
                                    )
                                  : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                        ),
                        onChanged: (v) {
                          _debounceTimer?.cancel();
                          _debounceTimer = Timer(
                              const Duration(milliseconds: 500),
                              () => _buscarLugar(v));
                          setState(() {});
                        },
                      ),
                    ),
                    if (_sugerencias.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 8)
                          ],
                        ),
                        child: Column(
                          children: _sugerencias.take(5).map((p) {
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.place_outlined,
                                  color: Color(0xFF002133), size: 20),
                              title: Text(
                                p.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black87),
                              ),
                              onTap: () {
                                setState(() {
                                  _mostrarSearch = false;
                                  _sugerencias = [];
                                });
                                _searchCtrl.clear();
                                _calcularRuta(p.pos, p.name.split(',').first);
                              },
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),

          // ── 4. PANEL LUGARES SEGUROS ──────────────────────
          if (!_modoPanico && !_mostrarSearch)
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              left: 16,
              child: Column(
                children: _lugaresSeguros.map((l) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GestureDetector(
                      onTap: () => _irALugarSeguro(l['tipo']),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: azul.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: dorado.withOpacity(0.5)),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 8)
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(l['icono'] as IconData,
                                color: dorado, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              l['nombre'],
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

          // ── 5. PANEL INFO RUTA ────────────────────────────
          if (_rutaPuntos.isNotEmpty)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: azul,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: dorado.withOpacity(0.5)),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 12)
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: rojo.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child:
                          const Icon(Icons.flag_rounded, color: rojo, size: 24),
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
                                  color: dorado, size: 14),
                              const SizedBox(width: 4),
                              Text(_distanciaTexto,
                                  style: const TextStyle(
                                      color: dorado, fontSize: 13)),
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

          // ── 6. CALCULANDO RUTA ────────────────────────────
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
                    color: azul,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: dorado.withOpacity(0.5)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: dorado, strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Calculando ruta...',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),

          // ── 7. BARRA INFERIOR ─────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_rutaPuntos.isEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.only(bottom: 8, left: 60, right: 60),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 16),
                      decoration: BoxDecoration(
                        color: azul.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: Colors.white10),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 8)
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.access_time_rounded,
                              color: dorado, size: 16),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _horaActual,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _gpsListo
                                  ? verde.withOpacity(0.2)
                                  : rojo.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.gps_fixed_rounded,
                                    color: _gpsListo ? verde : rojo, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  _gpsListo ? 'GPS activo' : 'Sin GPS',
                                  style: TextStyle(
                                      color: _gpsListo ? verde : rojo,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Bottom Nav con badge en Avisos
                StreamBuilder<int>(
                  stream: _noticeService.contadorNoLeidos(),
                  builder: (context, snap) {
                    final count = snap.data ?? 0;
                    return BottomNavigationBar(
                      currentIndex: 2,
                      backgroundColor: azul,
                      selectedItemColor: dorado,
                      unselectedItemColor: Colors.white54,
                      type: BottomNavigationBarType.fixed,
                      onTap: (index) {
                        if (index == 2) return;
                        const routes = [
                          '/profile',
                          '/guardian',
                          '',
                          '/chats',
                          '/notices'
                        ];
                        Navigator.pushReplacementNamed(context, routes[index]);
                      },
                      items: [
                        const BottomNavigationBarItem(
                            icon: Icon(Icons.person_outline),
                            activeIcon: Icon(Icons.person),
                            label: 'Perfil'),
                        const BottomNavigationBarItem(
                            icon: Icon(Icons.shield_outlined),
                            activeIcon: Icon(Icons.shield),
                            label: 'Guardian'),
                        const BottomNavigationBarItem(
                            icon: Icon(Icons.map_outlined),
                            activeIcon: Icon(Icons.map),
                            label: 'Mapa'),
                        const BottomNavigationBarItem(
                            icon: Icon(Icons.chat_bubble_outline),
                            activeIcon: Icon(Icons.chat_bubble),
                            label: 'Chats'),
                        // ✅ Badge dinámico en Avisos
                        BottomNavigationBarItem(
                          icon: Badge(
                            isLabelVisible: count > 0,
                            label: Text('$count'),
                            child: const Icon(Icons.notifications_none),
                          ),
                          activeIcon: const Icon(Icons.notifications),
                          label: 'Avisos',
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
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
          color: azul.withOpacity(0.9),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white12),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}
