import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class SosSimulationScreen extends StatefulWidget {
  const SosSimulationScreen({super.key});

  @override
  State<SosSimulationScreen> createState() => _SosSimulationScreenState();
}

class _SosSimulationScreenState extends State<SosSimulationScreen> {
  static const Color darkBlue = Color(0xFF002133);
  static const Color gold = Color(0xFFD4AF37);
  static const Color red = Color(0xFFE53935);
  static const Color green = Color(0xFF2ECC71);

  bool _loading = false;
  bool _simulated = false;
  String _name = 'Usuario SOS';
  String _email = '';
  String _companyName = '';
  String _companyStatus = '';
  Position? _position;
  String? _error;

  Future<void> _runSimulation() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Debes iniciar sesion');

      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = profile.data() ?? const <String, dynamic>{};

      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) throw Exception('Activa el GPS del dispositivo');

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Permiso de ubicacion denegado');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;
      setState(() {
        _name = (data['name'] ??
                data['nombre'] ??
                user.displayName ??
                user.email ??
                'Usuario SOS')
            .toString();
        _email = (data['email'] ?? user.email ?? '').toString();
        _companyName = (data['companyName'] ?? '').toString().trim();
        _companyStatus =
            (data['companyAccessStatus'] ?? 'inactive').toString().trim();
        _position = position;
        _simulated = true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _hasActiveCompany =>
      _companyStatus.toLowerCase() == 'active' && _companyName.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBlue,
      appBar: AppBar(
        backgroundColor: darkBlue,
        foregroundColor: Colors.white,
        title: const Text('Simulacion SOS'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _hero(),
          const SizedBox(height: 18),
          if (_error != null) _message(_error!, red),
          if (_simulated) ...[
            _previewCard(),
            const SizedBox(height: 14),
            _locationCard(),
            const SizedBox(height: 14),
            _companyCard(),
          ] else
            _emptyState(),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _loading ? null : _runSimulation,
            style: FilledButton.styleFrom(
              backgroundColor: gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: Text(
              _loading
                  ? 'Simulando'
                  : _simulated
                      ? 'Simular de nuevo'
                      : 'Simular ahora',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gold.withOpacity(0.65)),
      ),
      child: const Row(
        children: [
          Icon(Icons.sos_rounded, color: red, size: 38),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Vista previa de alerta SOS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return _message(
      'La simulacion mostrara los datos que se enviarian en una alerta real.',
      Colors.white70,
    );
  }

  Widget _previewCard() {
    return _infoCard(
      icon: Icons.person_pin_circle_rounded,
      iconColor: gold,
      title: _name,
      lines: [
        if (_email.isNotEmpty) _email,
        'Estado: simulada, no creada',
      ],
    );
  }

  Widget _locationCard() {
    final position = _position;
    return _infoCard(
      icon: Icons.my_location_rounded,
      iconColor: green,
      title: 'Ubicacion detectada',
      lines: [
        if (position == null)
          'Sin ubicacion'
        else
          'Lat ${position.latitude.toStringAsFixed(6)}, Lng ${position.longitude.toStringAsFixed(6)}',
      ],
    );
  }

  Widget _companyCard() {
    return _infoCard(
      icon: _hasActiveCompany
          ? Icons.verified_user_rounded
          : Icons.warning_amber_rounded,
      iconColor: _hasActiveCompany ? green : gold,
      title: _hasActiveCompany ? _companyName : 'Sin empresa activa',
      lines: [
        _hasActiveCompany
            ? 'La alerta real iria a esta empresa'
            : 'La simulacion puede verse sin crear alerta',
      ],
    );
  }

  Widget _message(String text, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: color)),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required List<String> lines,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF083245),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                ...lines.map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      line,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
