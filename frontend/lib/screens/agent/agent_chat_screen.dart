// lib/screens/agent/agent_chat_screen.dart
//
// Pantalla de chat dedicada para el agente.
// Se abre automáticamente al aceptar una alerta; permite comunicarse
// con el usuario que la envió en tiempo real usando el mismo ChatService
// que ya existe en la app.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/chat_service.dart';

class AgentChatScreen extends StatefulWidget {
  /// UID de Firestore del usuario que envió la alerta.
  final String alertUserId;

  /// Nombre para mostrar en el AppBar (nombre o email del usuario).
  final String alertUserName;

  /// Título de la alerta, se muestra como subtítulo.
  final String alertTitle;
  final String? initialChatId;
  final VoidCallback? onBack;

  const AgentChatScreen({
    super.key,
    required this.alertUserId,
    required this.alertUserName,
    required this.alertTitle,
    this.initialChatId,
    this.onBack,
  });

  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen> {
  static const Color _azulFondo = Color(0xFF002133);
  static const Color _navBlue = Color(0xFF001F3F);
  static const Color _gold = Color(0xFFD4AF37);

  final ChatService _chatService = ChatService();
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// chatId se resuelve de forma asíncrona al abrir la pantalla.
  String? _chatId;
  bool _loadingChat = true;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  /// Crea o recupera el chat entre el agente (currentUser) y el usuario de la alerta.
  Future<void> _initChat() async {
    try {
      final id = widget.initialChatId ??
          await _chatService.openOrCreateChat(
            widget.alertUserId,
            otherName: widget.alertUserName,
          );
      await _chatService.markAsRead(id);
      if (!mounted) return;
      setState(() {
        _chatId = id;
        _loadingChat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = 'No se pudo abrir el chat: $e';
        _loadingChat = false;
      });
    }
  }

  @override
  void dispose() {
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _chatId == null) return;
    _msgController.clear();
    await _chatService.sendMessage(_chatId!, text);
    _scrollToBottom();
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _azulFondo,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: _navBlue,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
        onPressed: widget.onBack ?? () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white12,
            child: Text(
              widget.alertUserName.isNotEmpty
                  ? widget.alertUserName[0].toUpperCase()
                  : '?',
              style: const TextStyle(color: _gold, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.alertUserName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.alertTitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.redAccent.withOpacity(0.18),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(Icons.sos_rounded, color: Colors.redAccent, size: 16),
              SizedBox(width: 4),
              Text('SOS',
                  style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loadingChat) {
      return const Center(child: CircularProgressIndicator(color: _gold));
    }

    if (_errorMsg != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_outlined,
                  color: Colors.white24, size: 56),
              const SizedBox(height: 16),
              Text(_errorMsg!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _loadingChat = true;
                    _errorMsg = null;
                  });
                  _initChat();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _gold, foregroundColor: Colors.black),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // ── Banda de alerta activa ──────────────────────────────────────────
        Container(
          width: double.infinity,
          color: Colors.redAccent.withOpacity(0.12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.redAccent, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Alerta activa · ${widget.alertTitle}',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        // ── Lista de mensajes ───────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _chatService.getMessagesStream(_chatId!),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: _gold));
              }

              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.waving_hand,
                          color: Colors.white24, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Comunícate con ${widget.alertUserName}',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 15),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Este chat es privado entre tú y la persona en emergencia.',
                        style: TextStyle(color: Colors.white24, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              _scrollToBottom();

              return ListView.builder(
                controller: _scrollController,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final isMe = data['senderId'] == _chatService.currentUid;
                  final ts = data['timestamp'] as Timestamp?;

                  final showDate = index == 0 ||
                      _isDifferentDay(
                        (docs[index - 1].data()
                            as Map<String, dynamic>)['timestamp'] as Timestamp?,
                        ts,
                      );

                  return Column(
                    children: [
                      if (showDate) _AgentDateSeparator(timestamp: ts),
                      _AgentMessageBubble(
                        text: data['text'] ?? '',
                        isMe: isMe,
                        timestamp: ts,
                        read: data['read'] ?? false,
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),

        // ── Barra de escritura ──────────────────────────────────────────────
        Container(
          color: _navBlue,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _msgController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 4,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Mensaje al usuario en emergencia...',
                        hintStyle: TextStyle(color: Colors.white38),
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: _gold,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded,
                        color: Colors.black, size: 22),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool _isDifferentDay(Timestamp? a, Timestamp? b) {
    if (a == null || b == null) return false;
    final da = a.toDate();
    final db = b.toDate();
    return da.day != db.day || da.month != db.month || da.year != db.year;
  }
}

// ─── Burbuja de mensaje (copia estilizada para el agente) ─────────────────────
class _AgentMessageBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final Timestamp? timestamp;
  final bool read;

  const _AgentMessageBubble({
    required this.text,
    required this.isMe,
    required this.timestamp,
    required this.read,
  });

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 3,
          bottom: 3,
          left: isMe ? 60 : 0,
          right: isMe ? 0 : 60,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color:
              isMe ? const Color(0xFFD4AF37).withOpacity(0.92) : Colors.white12,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: TextStyle(
                  color: isMe ? Colors.black : Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(timestamp),
                  style: TextStyle(
                      color: isMe ? Colors.black54 : Colors.white38,
                      fontSize: 10),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    read ? Icons.done_all : Icons.done,
                    size: 13,
                    color: read ? Colors.blue[300] : Colors.black45,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Separador de fecha ───────────────────────────────────────────────────────
class _AgentDateSeparator extends StatelessWidget {
  final Timestamp? timestamp;
  const _AgentDateSeparator({this.timestamp});

  String _label() {
    if (timestamp == null) return '';
    final dt = timestamp!.toDate();
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return 'Hoy';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.day == yesterday.day && dt.month == yesterday.month) return 'Ayer';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
              color: Colors.white10, borderRadius: BorderRadius.circular(20)),
          child: Text(_label(),
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ),
      ),
    );
  }
}
