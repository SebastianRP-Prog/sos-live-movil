import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─────────────────────────────────────────────────────────
//  MODELO: Notice
// ─────────────────────────────────────────────────────────
class Notice {
  final String  id;
  final String  tipo;      // "sos" | "zona_peligrosa" | "comunicado"
  final String  titulo;
  final String  mensaje;
  final DateTime? timestamp;
  final bool    leido;
  final String  icono;     // "warning" | "sos" | "shield"
  final String  color;     // "red" | "gold" | "blue"
  final String  creadoPor;

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
    final d = doc.data() as Map<String, dynamic>;
    return Notice(
      id:        doc.id,
      tipo:      d['tipo']      ?? 'comunicado',
      titulo:    d['titulo']    ?? 'Aviso',
      mensaje:   d['mensaje']   ?? '',
      timestamp: (d['timestamp'] as Timestamp?)?.toDate(),
      leido:     d['leido']     ?? false,
      icono:     d['icono']     ?? 'shield',
      color:     d['color']     ?? 'gold',
      creadoPor: d['creadoPor'] ?? '',
    );
  }
}

// ─────────────────────────────────────────────────────────
//  NOTICE SERVICE
// ─────────────────────────────────────────────────────────
class NoticeService {
  static final NoticeService _instance = NoticeService._internal();
  factory NoticeService() => _instance;
  NoticeService._internal();

  final FirebaseFirestore _db   = FirebaseFirestore.instance;
  final FirebaseAuth      _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  // ── Stream en tiempo real de mis notices ───────────────
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

  // ── Crear notice de SOS ────────────────────────────────
  /// Llama esto cuando el usuario confirma el SOS.
  /// Notifica a todos sus guardianes.
  Future<void> crearNoticeSOS({
    required double lat,
    required double lng,
  }) async {
    final uid = _uid;
    if (uid == null) return;

    // 1. Obtener datos del usuario
    final userDoc = await _db.collection('users').doc(uid).get();
    final userData = userDoc.data() ?? {};
    final nombre = userData['nombre'] ?? userData['email'] ?? 'Un aprendiz';

    // 2. Obtener lista de guardianes
    final List<dynamic> guardianes =
        userData['guardians'] ?? [];

    // Si no tiene guardianes, el notice igual se crea para él mismo
    final destinatarios = <String>[uid, ...guardianes.cast<String>()];

    // 3. Crear el notice
    await _db.collection('notices').add({
      'tipo':          'sos',
      'titulo':        '🚨 SOS Activado',
      'mensaje':
          '$nombre activó una alerta de emergencia. Ubicación: lat $lat, lng $lng',
      'timestamp':     FieldValue.serverTimestamp(),
      'destinatarios': destinatarios,
      'creadoPor':     uid,
      'leido':         false,
      'icono':         'sos',
      'color':         'red',
      'ubicacion': {
        'lat': lat,
        'lng': lng,
      },
    });
  }

  // ── Marcar notice como leído ───────────────────────────
  Future<void> marcarLeido(String noticeId) async {
    await _db.collection('notices').doc(noticeId).update({'leido': true});
  }

  // ── Marcar todos como leídos ───────────────────────────
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

  // ── Contar no leídos (para badge) ─────────────────────
  Stream<int> contadorNoLeidos() {
    final uid = _uid;
    if (uid == null) return Stream.value(0);

    return _db
        .collection('notices')
        .where('destinatarios', arrayContains: uid)
        .where('leido', isEqualTo: false)
        .snapshots()
        .map((s) => s.docs.length);
  }
}