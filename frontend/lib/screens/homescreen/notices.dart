import 'package:flutter/material.dart';
import '/services/notice_service.dart'; // ajusta el import a tu estructura

class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key});

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  final Color azulFondo = const Color(0xFF002133);
  final Color doradoSOS = const Color(0xFFD4AF37);
  final Color azulNav   = const Color(0xFF001F3F);

  final NoticeService _noticeService = NoticeService();

  @override
  void initState() {
    super.initState();
    // Marcar todos como leídos al abrir la pantalla
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _noticeService.marcarTodosLeidos();
    });
  }

  // ── Mapear color string → Color ────────────────────────
  Color _resolverColor(String color) {
    switch (color) {
      case 'red':
        return Colors.redAccent;
      case 'gold':
        return const Color(0xFFD4AF37);
      case 'blue':
        return Colors.blueAccent;
      case 'green':
        return const Color(0xFF2ECC71);
      default:
        return Colors.white54;
    }
  }

  // ── Mapear icono string → IconData ─────────────────────
  IconData _resolverIcono(String icono) {
    switch (icono) {
      case 'sos':
        return Icons.sos_rounded;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'shield':
        return Icons.shield_outlined;
      case 'location':
        return Icons.location_on_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  // ── Formatear timestamp relativo ───────────────────────
  String _formatearHora(DateTime? ts) {
    if (ts == null) return 'ahora';
    final diff = DateTime.now().difference(ts);

    if (diff.inSeconds < 60)  return 'ahora';
    if (diff.inMinutes < 60)  return '${diff.inMinutes} min';
    if (diff.inHours < 24)    return '${diff.inHours} h';
    if (diff.inDays < 7)      return '${diff.inDays} d';
    return '${ts.day}/${ts.month}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: azulFondo,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 25, vertical: 25),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Notices',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Alertas y Comunicados',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Badge contador no leídos en tiempo real
                  StreamBuilder<int>(
                    stream: _noticeService.contadorNoLeidos(),
                    builder: (context, snap) {
                      final count = snap.data ?? 0;
                      if (count == 0) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$count nuevos',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // ── Lista en tiempo real ─────────────────────
            Expanded(
              child: StreamBuilder<List<Notice>>(
                stream: _noticeService.misNotices(),
                builder: (context, snapshot) {
                  // Estado de carga
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(
                        color: doradoSOS,
                        strokeWidth: 2,
                      ),
                    );
                  }

                  // Error
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error al cargar avisos\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.4)),
                      ),
                    );
                  }

                  // Sin notices
                  final notices = snapshot.data ?? [];
                  if (notices.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notifications_off_outlined,
                            color: Colors.white.withOpacity(0.2),
                            size: 60,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Sin avisos por ahora',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.3),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Lista de notices
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: notices.length,
                    itemBuilder: (context, index) {
                      final notice = notices[index];
                      return _buildNoticeCard(notice);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  // ── Card de notice ──────────────────────────────────────
  Widget _buildNoticeCard(Notice notice) {
    final color = _resolverColor(notice.color);
    final icono = _resolverIcono(notice.icono);
    final hora  = _formatearHora(notice.timestamp);

    return GestureDetector(
      onTap: () => _noticeService.marcarLeido(notice.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: notice.leido
              ? Colors.white.withOpacity(0.04)
              : Colors.white.withOpacity(0.09),
          borderRadius: BorderRadius.circular(20),
          border: Border(
            left: BorderSide(color: color, width: 6),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ícono
              CircleAvatar(
                backgroundColor: color.withOpacity(0.15),
                child: Icon(icono, color: color, size: 22),
              ),
              const SizedBox(width: 15),

              // Contenido
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            notice.titulo,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: notice.leido
                                  ? FontWeight.w500
                                  : FontWeight.bold,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 5),
                        // Punto rojo si no leído
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!notice.leido)
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: const BoxDecoration(
                                  color: Colors.redAccent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            Text(
                              hora,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      notice.mensaje,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                      softWrap: true,
                    ),
                    // Chip de tipo
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _etiquetaTipo(notice.tipo),
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _etiquetaTipo(String tipo) {
    switch (tipo) {
      case 'sos':
        return 'ALERTA SOS';
      case 'zona_peligrosa':
        return 'ZONA PELIGROSA';
      case 'comunicado':
        return 'COMUNICADO';
      default:
        return tipo.toUpperCase();
    }
  }

  // ── Bottom Nav ──────────────────────────────────────────
  Widget _buildBottomNav(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 4,
      backgroundColor: azulNav,
      selectedItemColor: doradoSOS,
      unselectedItemColor: Colors.white60,
      type: BottomNavigationBarType.fixed,
      onTap: (index) {
        if (index == 0) Navigator.pushReplacementNamed(context, '/profile');
        if (index == 1) Navigator.pushReplacementNamed(context, '/guardian');
        if (index == 2) Navigator.pushReplacementNamed(context, '/maps');
        if (index == 3) Navigator.pushReplacementNamed(context, '/chats');
      },
      items: const [
        BottomNavigationBarItem(
            icon: Icon(Icons.person_outline), label: 'Perfil'),
        BottomNavigationBarItem(
            icon: Icon(Icons.shield_outlined), label: 'Guardian'),
        BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined), label: 'Mapa'),
        BottomNavigationBarItem(
            icon: Icon(Icons.chat_outlined), label: 'Chats'),
        BottomNavigationBarItem(
            icon: Icon(Icons.notifications), label: 'Avisos'),
      ],
    );
  }
}