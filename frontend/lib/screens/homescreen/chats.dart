// lib/screens/homescreen/chats.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/chat_service.dart';
import 'chat_detail.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final Color azulFondo    = const Color(0xFF002133);
  final Color doradoSOS    = const Color(0xFFD4AF37);
  final Color blancoTexto  = Colors.white;

  final ChatService _chatService = ChatService();
  final TextEditingController _emailController = TextEditingController();

  // ─── Diálogo para agregar nuevo chat por correo ──────────────────────────
  void _mostrarDialogoNuevoChat() {
    _emailController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF002133),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Nuevo chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ingresa el correo del contacto:', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'correo@ejemplo.com',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFFD4AF37)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37)),
            onPressed: () => _abrirChatPorCorreo(ctx),
            child: const Text('Iniciar chat', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirChatPorCorreo(BuildContext dialogCtx) async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    // No chatear con uno mismo
    final myEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    if (email.toLowerCase() == myEmail.toLowerCase()) {
      Navigator.pop(dialogCtx);
      _showSnack('No puedes chatear contigo mismo 😅');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37))),
    );

    final user = await _chatService.getUserByEmail(email);
    Navigator.pop(context); // cierra loading

    if (user == null) {
      Navigator.pop(dialogCtx);
      _showSnack('No se encontró ningún usuario con ese correo');
      return;
    }

    final chatId = await _chatService.openOrCreateChat(user['uid']);
    Navigator.pop(dialogCtx);

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          chatId: chatId,
          otherUserId: user['uid'],
          otherUserName: user['name'] ?? user['email'],
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF001F3F)),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: azulFondo,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── CABECERA ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Messages', style: TextStyle(color: blancoTexto, fontSize: 32, fontWeight: FontWeight.bold)),
                      const Text('Chats', style: TextStyle(color: Colors.white24, fontSize: 16)),
                    ],
                  ),
                  Icon(Icons.search, color: blancoTexto, size: 30),
                ],
              ),
            ),

            // ── LISTA DE CHATS EN TIEMPO REAL ─────────────────────────────
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _chatService.getChatsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, color: Colors.white24, size: 64),
                          const SizedBox(height: 16),
                          const Text('Aún no tienes chats', style: TextStyle(color: Colors.white38, fontSize: 16)),
                          const SizedBox(height: 8),
                          const Text('Toca + para iniciar una conversación', style: TextStyle(color: Colors.white24, fontSize: 13)),
                        ],
                      ),
                    );
                  }

                  final chats = snapshot.data!.docs;
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemCount: chats.length,
                    itemBuilder: (context, index) {
                      final chat = chats[index].data() as Map<String, dynamic>;
                      final chatId = chats[index].id;
                      final participants = List<String>.from(chat['participants'] ?? []);
                      final otherUid = participants.firstWhere(
                        (uid) => uid != _chatService.currentUid,
                        orElse: () => '',
                      );
                      return _ChatTile(
                        chatId: chatId,
                        otherUid: otherUid,
                        lastMessage: chat['lastMessage'] ?? '',
                        lastMessageTime: chat['lastMessageTime'] as Timestamp?,
                        lastMessageSenderId: chat['lastMessageSenderId'] ?? '',
                        chatService: _chatService,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),

      // ── FAB DORADO ────────────────────────────────────────────────────────
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: FloatingActionButton(
          backgroundColor: doradoSOS,
          onPressed: _mostrarDialogoNuevoChat,
          child: const Icon(Icons.chat_bubble_outline, color: Colors.black, size: 28),
        ),
      ),

      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 3,
      backgroundColor: const Color(0xFF001F3F),
      selectedItemColor: doradoSOS,
      unselectedItemColor: Colors.white60,
      type: BottomNavigationBarType.fixed,
      onTap: (index) {
        if (index == 0) Navigator.pushReplacementNamed(context, '/profile');
        if (index == 1) Navigator.pushReplacementNamed(context, '/guardian');
        if (index == 2) Navigator.pushReplacementNamed(context, '/maps');
        if (index == 4) Navigator.pushReplacementNamed(context, '/notices');
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
        BottomNavigationBarItem(icon: Icon(Icons.shield), label: 'Guardian'),
        BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Mapa'),
        BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chats'),
        BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Avisos'),
      ],
    );
  }
}

// ─── Widget de cada fila de chat ─────────────────────────────────────────────
class _ChatTile extends StatelessWidget {
  final String chatId;
  final String otherUid;
  final String lastMessage;
  final Timestamp? lastMessageTime;
  final String lastMessageSenderId;
  final ChatService chatService;

  const _ChatTile({
    required this.chatId,
    required this.otherUid,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.lastMessageSenderId,
    required this.chatService,
  });

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${dt.day}/${dt.month}';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: chatService.getUserById(otherUid),
      builder: (context, userSnap) {
        final userName  = userSnap.data?['name'] ?? userSnap.data?['email'] ?? '...';
        final isMine    = lastMessageSenderId == chatService.currentUid;
        final preview   = lastMessage.isEmpty
            ? 'Toca para chatear'
            : isMine ? 'Tú: $lastMessage' : lastMessage;

        return InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatDetailScreen(
                chatId: chatId,
                otherUserId: otherUid,
                otherUserName: userName,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white12,
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                    style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 14),
                // Nombre + último mensaje
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(userName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        preview,
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Hora
                Text(_formatTime(lastMessageTime), style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
        );
      },
    );
  }
}