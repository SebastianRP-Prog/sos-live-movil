// lib/services/chat_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ─── ID de chat único y consistente entre dos usuarios ───────────────────
  String getChatId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  String get currentUid => _auth.currentUser!.uid;

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
  Future<String> openOrCreateChat(String otherUid) async {
    final chatId = getChatId(currentUid, otherUid);
    final chatRef = _db.collection('chats').doc(chatId);
    final chatSnap = await chatRef.get();

    if (!chatSnap.exists) {
      await chatRef.set({
        'participants': [currentUid, otherUid],
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSenderId': '',
      });
    }
    return chatId;
  }

  // ─── Stream de todos los chats del usuario actual ─────────────────────────
  Stream<QuerySnapshot> getChatsStream() {
    return _db
        .collection('chats')
        .where('participants', arrayContains: currentUid)
        .orderBy('lastMessageTime', descending: true)
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

    final msgRef = _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc();

    final batch = _db.batch();

    // Agregar mensaje a la subcolección
    batch.set(msgRef, {
      'senderId': currentUid,
      'text': text.trim(),
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
    });

    // Actualizar último mensaje en el documento del chat
    batch.update(_db.collection('chats').doc(chatId), {
      'lastMessage': text.trim(),
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastMessageSenderId': currentUid,
    });

    await batch.commit();
  }

  // ─── Marcar mensajes como leídos ─────────────────────────────────────────
  Future<void> markAsRead(String chatId) async {
    final unread = await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('read', isEqualTo: false)
        .where('senderId', isNotEqualTo: currentUid)
        .get();

    final batch = _db.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  // ─── Obtener datos de un usuario por UID ─────────────────────────────────
  Future<Map<String, dynamic>?> getUserById(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return {'uid': doc.id, ...doc.data()!};
  }

  // ─── Contar mensajes no leídos en un chat ────────────────────────────────
  Future<int> getUnreadCount(String chatId) async {
    final snap = await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('read', isEqualTo: false)
        .where('senderId', isNotEqualTo: currentUid)
        .get();
    return snap.docs.length;
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