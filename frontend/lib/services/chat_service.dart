// lib/services/chat_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static String? localSessionUid;
  static String? localSessionName;

  // ─── ID de chat único y consistente entre dos usuarios ───────────────────
  String getChatId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  User? get _firebaseUser => _auth.currentUser;

  User get _currentUser {
    final user = _firebaseUser;
    if (user == null) {
      throw StateError(
        'No hay una sesion Firebase activa. Vuelve a iniciar sesion.',
      );
    }
    return user;
  }

  String get currentUid {
    final localUid = localSessionUid;
    if (localUid != null && localUid.trim().isNotEmpty) {
      return localUid.trim();
    }

    final firebaseUid = _firebaseUser?.uid;
    if (firebaseUid != null && firebaseUid.trim().isNotEmpty) {
      return firebaseUid.trim();
    }

    return _currentUser.uid;
  }

  // ─── Buscar usuario por correo ────────────────────────────────────────────
  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final query = await _db
        .collection('users')
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;
    return {'uid': query.docs.first.id, ...query.docs.first.data()};
  }

  // ─── Crear o abrir un chat con otro usuario ───────────────────────────────
  Future<String> openOrCreateChat(
    String otherUid, {
    String? otherName,
    String? currentName,
  }) async {
    final chatId = getChatId(currentUid, otherUid);
    final chatRef = _db.collection('chats').doc(chatId);
    final participantNames = <String, String>{
      if ((currentName ?? localSessionName)?.trim().isNotEmpty ?? false)
        currentUid: (currentName ?? localSessionName)!.trim(),
      if (otherName != null && otherName.trim().isNotEmpty)
        otherUid: otherName.trim(),
    };

    await chatRef.set({
      'participants': [currentUid, otherUid],
      if (participantNames.isNotEmpty) 'participantNames': participantNames,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return chatId;
  }

  // ─── Stream de todos los chats del usuario actual ─────────────────────────
  Stream<QuerySnapshot> getChatsStream() {
    return _db
        .collection('chats')
        .where('participants', arrayContains: currentUid)
        .snapshots();
  }

  // ─── Stream de mensajes de un chat ───────────────────────────────────────
  Stream<QuerySnapshot> getMessagesStream(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  // ─── Enviar mensaje ───────────────────────────────────────────────────────
  Future<void> sendMessage(String chatId, String text) async {
    if (text.trim().isEmpty) return;

    final msgRef =
        _db.collection('chats').doc(chatId).collection('messages').doc();

    final batch = _db.batch();

    // Agregar mensaje a la subcolección
    batch.set(msgRef, {
      'senderId': currentUid,
      'text': text.trim(),
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
    });

    // Actualizar último mensaje en el documento del chat
    batch.set(
        _db.collection('chats').doc(chatId),
        {
          'lastMessage': text.trim(),
          'lastMessageTime': FieldValue.serverTimestamp(),
          'lastMessageSenderId': currentUid,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));

    await batch.commit();
  }

  // ─── Marcar mensajes como leídos ─────────────────────────────────────────
  Future<void> markAsRead(String chatId) async {
    final unread = await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('read', isEqualTo: false)
        .get();

    final batch = _db.batch();
    for (final doc in unread.docs) {
      final data = doc.data();
      if (data['senderId'] != currentUid) {
        batch.update(doc.reference, {'read': true});
      }
    }
    await batch.commit();
  }

  // ─── Obtener datos de un usuario por UID ─────────────────────────────────
  Future<Map<String, dynamic>?> getUserById(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (doc.exists) return {'uid': doc.id, ...doc.data()!};

    for (final collection in ['dashboard_agents', 'Agentes']) {
      final agentDoc = await _db.collection(collection).doc(uid).get();
      if (agentDoc.exists) {
        return {'uid': agentDoc.id, ...agentDoc.data()!};
      }
    }

    return null;
  }

  Future<Map<String, dynamic>?> getAgentByName(String name) async {
    final normalizedName = _normalizeText(name);
    if (normalizedName.isEmpty) return null;

    for (final collection in ['dashboard_agents', 'Agentes']) {
      final snap = await _db.collection(collection).limit(150).get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final agentName = (data['nombre'] ?? data['name'] ?? '').toString();
        if (_normalizeText(agentName) == normalizedName) {
          final uid = (data['codigo'] ??
                  data['code'] ??
                  data['agentId'] ??
                  data['uid'] ??
                  data['authUid'] ??
                  data['firebaseUid'] ??
                  doc.id)
              .toString()
              .trim();
          return {'uid': uid, 'docId': doc.id, ...data};
        }
      }
    }

    return null;
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

  // ─── Contar mensajes no leídos en un chat ────────────────────────────────
  Future<int> getUnreadCount(String chatId) async {
    final snap = await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('read', isEqualTo: false)
        .get();
    return snap.docs
        .where((doc) => doc.data()['senderId'] != currentUid)
        .length;
  }

  // ─── [FCM - PREPARADO PARA DESPUÉS] ──────────────────────────────────────
  // Cuando actives notificaciones, guarda el token así en users/{uid}:
  //
  // Future<void> saveFCMToken(String token) async {
  //   await _db.collection('users').doc(currentUid).update({
  //     'fcmToken': token,
  //   });
  // }
  //
  // Y desde Cloud Functions escucha onCreate en chats/{chatId}/messages
  // para enviar la notificación al otro participante.
}
