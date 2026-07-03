import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AlertHistoryScreen extends StatelessWidget {
  const AlertHistoryScreen({super.key});

  static const Color darkBlue = Color(0xFF002133);
  static const Color gold = Color(0xFFD4AF37);
  static const Color red = Color(0xFFE53935);
  static const Color green = Color(0xFF2ECC71);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: darkBlue,
      appBar: AppBar(
        backgroundColor: darkBlue,
        foregroundColor: Colors.white,
        title: const Text('Historial SOS'),
      ),
      body: uid == null
          ? const Center(
              child: Text(
                'Inicia sesion para ver tu historial',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('dashboard_alerts')
                  .where('userId', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _state(
                    icon: Icons.error_outline,
                    text: 'No se pudo cargar el historial',
                    color: red,
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: gold),
                  );
                }

                final docs = [...(snapshot.data?.docs ?? const [])]..sort(
                    (a, b) =>
                        _dateFrom(b.data()).compareTo(_dateFrom(a.data())),
                  );

                if (docs.isEmpty) {
                  return _state(
                    icon: Icons.history_rounded,
                    text: 'Aun no has creado alertas SOS',
                    color: gold,
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(18),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    return _AlertTile(id: doc.id, data: doc.data());
                  },
                );
              },
            ),
    );
  }

  static Widget _state({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 44),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  static DateTime _dateFrom(Map<String, dynamic> data) {
    final value = data['createdAt'] ?? data['timestamp'] ?? data['updatedAt'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({
    required this.id,
    required this.data,
  });

  final String id;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final status = _status(data);
    final createdAt = _dateFrom(data);
    final agentName =
        (data['agenteAsignado'] ?? data['acceptedBy'] ?? '').toString();
    final companyName = (data['companyName'] ?? '').toString();
    final location = _locationText(data);
    final isClosed = _isClosed(status);
    final isAccepted = _isAccepted(status, agentName);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF083245),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _statusColor(isClosed, isAccepted).withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isClosed
                      ? Icons.check_circle_rounded
                      : isAccepted
                          ? Icons.verified_user_rounded
                          : Icons.sos_rounded,
                  color: _statusColor(isClosed, isAccepted),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title(isClosed, isAccepted),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(createdAt),
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _line(Icons.place_outlined, location),
          if (companyName.trim().isNotEmpty)
            _line(Icons.business_rounded, companyName),
          if (agentName.trim().isNotEmpty &&
              agentName.trim().toLowerCase() != 'sin asignar')
            _line(Icons.shield_rounded, 'Asignado: $agentName'),
          _line(Icons.tag_rounded, id),
        ],
      ),
    );
  }

  static String _status(Map<String, dynamic> data) =>
      (data['status'] ?? data['estado'] ?? 'active')
          .toString()
          .trim()
          .toLowerCase();

  static bool _isClosed(String status) =>
      status == 'closed' ||
      status == 'cerrada' ||
      status == 'cerrado' ||
      status == 'finalizado' ||
      status == 'cancelado';

  static bool _isAccepted(String status, String agentName) =>
      status == 'accepted' ||
      status == 'aceptada' ||
      status == 'aceptado' ||
      (agentName.trim().isNotEmpty &&
          agentName.trim().toLowerCase() != 'sin asignar');

  static Color _statusColor(bool isClosed, bool isAccepted) {
    if (isClosed) return AlertHistoryScreen.green;
    if (isAccepted) return AlertHistoryScreen.gold;
    return AlertHistoryScreen.red;
  }

  static String _title(bool isClosed, bool isAccepted) {
    if (isClosed) return 'Alerta finalizada';
    if (isAccepted) return 'Alerta aceptada';
    return 'Alerta activa';
  }

  static DateTime _dateFrom(Map<String, dynamic> data) {
    final value = data['createdAt'] ?? data['timestamp'] ?? data['updatedAt'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  static String _formatDate(DateTime date) {
    if (date.millisecondsSinceEpoch == 0) return 'Fecha no disponible';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} $hour:$minute';
  }

  static String _locationText(Map<String, dynamic> data) {
    final direct = (data['ubicacion'] ?? '').toString().trim();
    if (direct.isNotEmpty && direct != '{}') return direct;

    final location = data['location'];
    final lat = location is Map ? _readDouble(location['lat']) : null;
    final lng = location is Map ? _readDouble(location['lng']) : null;
    if (lat != null && lng != null) {
      return 'Lat ${lat.toStringAsFixed(6)}, Lng ${lng.toStringAsFixed(6)}';
    }
    return 'Ubicacion no disponible';
  }

  static double? _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Widget _line(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AlertHistoryScreen.gold),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}
