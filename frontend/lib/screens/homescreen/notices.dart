import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────
//  Modelo local de Notice (sin Firestore)
// ─────────────────────────────────────────────────────────
class NoticeItem {
  final String id;
  final String tipo;
  final String titulo;
  final String mensaje;
  final DateTime timestamp;
  bool leido;
  final String icono;
  final String color;

  NoticeItem({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.mensaje,
    required this.timestamp,
    this.leido = false,
    required this.icono,
    required this.color,
  });
}

// ─────────────────────────────────────────────────────────
//  Datos de ejemplo (reemplaza con tu fuente real sin índices)
// ─────────────────────────────────────────────────────────
final List<NoticeItem> _mockNotices = [
  NoticeItem(
    id: '1',
    tipo: 'zona_peligrosa',
    titulo: 'Zona de alto riesgo detectada',
    mensaje: 'Se reportaron incidentes en el sector norte de la ciudad. Evita circular por esta área durante la noche.',
    timestamp: DateTime.now().subtract(const Duration(minutes: 15)),
    icono: 'zone',
    color: 'red',
  ),
  NoticeItem(
    id: '2',
    tipo: 'zona_vigilada',
    titulo: 'Zona bajo vigilancia activa',
    mensaje: 'Autoridades mantienen presencia en el centro comercial Plaza Mayor y alrededores.',
    timestamp: DateTime.now().subtract(const Duration(hours: 1)),
    icono: 'shield',
    color: 'blue',
    leido: true,
  ),
  NoticeItem(
    id: '3',
    tipo: 'noticia',
    titulo: 'Operativo policial exitoso',
    mensaje: 'La policía metropolitana desarticuló una banda de hurtos en el barrio La Candelaria. Tres detenidos.',
    timestamp: DateTime.now().subtract(const Duration(hours: 3)),
    icono: 'news',
    color: 'green',
  ),
  NoticeItem(
    id: '4',
    tipo: 'alerta_ciudad',
    titulo: 'Alerta por manifestación',
    mensaje: 'Se reportan cierres viales en la Carrera 7ª entre calles 26 y 32 por marcha ciudadana. Planifica rutas alternas.',
    timestamp: DateTime.now().subtract(const Duration(hours: 5)),
    icono: 'warning',
    color: 'orange',
  ),
  NoticeItem(
    id: '5',
    tipo: 'comunicado',
    titulo: 'Comunicado oficial — Alcaldía',
    mensaje: 'La Alcaldía Mayor informa sobre el nuevo plan de seguridad ciudadana "Bogotá Segura 2025". Más patrullajes y cámaras.',
    timestamp: DateTime.now().subtract(const Duration(hours: 8)),
    icono: 'megaphone',
    color: 'gold',
    leido: true,
  ),
  NoticeItem(
    id: '6',
    tipo: 'evento_seguridad',
    titulo: 'Simulacro de evacuación',
    mensaje: 'El próximo sábado se realizará un simulacro de evacuación en el sector Chapinero. Participa y aprende qué hacer en emergencias.',
    timestamp: DateTime.now().subtract(const Duration(days: 1)),
    icono: 'shield',
    color: 'blue',
    leido: true,
  ),
  NoticeItem(
    id: '7',
    tipo: 'zona_peligrosa',
    titulo: 'Reporte ciudadano — Hurtos',
    mensaje: 'Usuarios reportaron hurtos a motociclistas en la Av. Primero de Mayo entre carrera 50 y 68. Ten precaución.',
    timestamp: DateTime.now().subtract(const Duration(days: 1, hours: 4)),
    icono: 'zone',
    color: 'red',
  ),
  NoticeItem(
    id: '8',
    tipo: 'noticia',
    titulo: 'Nuevo CAI inaugurado',
    mensaje: 'Se inauguró un nuevo Centro de Atención Inmediata (CAI) en el barrio Bosa Centro para reforzar la seguridad del sector.',
    timestamp: DateTime.now().subtract(const Duration(days: 2)),
    icono: 'news',
    color: 'green',
    leido: true,
  ),
];

// ─────────────────────────────────────────────────────────
//  Enum de categorías
// ─────────────────────────────────────────────────────────
enum _FeedCategory { todos, zonas, noticias, comunicados }

class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key});

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  final Color azulFondo = const Color(0xFF002133);
  final Color doradoSOS = const Color(0xFFD4AF37);
  final Color azulNav   = const Color(0xFF001F3F);

  _FeedCategory _categoriaActiva = _FeedCategory.todos;

  // Lista local mutable (copia del mock para poder marcar leídos)
  late List<NoticeItem> _notices;

  @override
  void initState() {
    super.initState();
    // Copia mutable de los datos de ejemplo
    _notices = List.from(_mockNotices);
    // Marca todos como leídos al abrir (simulando el comportamiento original)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _marcarTodosLeidos();
    });
  }

  void _marcarTodosLeidos() {
    setState(() {
      for (final n in _notices) {
        n.leido = true;
      }
    });
  }

  void _marcarLeido(String id) {
    setState(() {
      final idx = _notices.indexWhere((n) => n.id == id);
      if (idx != -1) _notices[idx].leido = true;
    });
  }

  int get _noLeidos => _notices.where((n) => !n.leido).length;

  // ── Helpers de estilo ───────────────────────────────────
  Color _resolverColor(String color) {
    switch (color) {
      case 'red':    return Colors.redAccent;
      case 'gold':   return const Color(0xFFD4AF37);
      case 'blue':   return Colors.blueAccent;
      case 'green':  return const Color(0xFF2ECC71);
      case 'orange': return Colors.orangeAccent;
      default:       return Colors.white54;
    }
  }

  IconData _resolverIcono(String icono) {
    switch (icono) {
      case 'sos':       return Icons.sos_rounded;
      case 'warning':   return Icons.warning_amber_rounded;
      case 'shield':    return Icons.shield_outlined;
      case 'location':  return Icons.location_on_rounded;
      case 'zone':      return Icons.dangerous_rounded;
      case 'news':      return Icons.article_rounded;
      case 'megaphone': return Icons.campaign_rounded;
      default:          return Icons.notifications_rounded;
    }
  }

  String _formatearHora(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 60) return 'ahora';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24)   return '${diff.inHours} h';
    if (diff.inDays < 7)     return '${diff.inDays} d';
    return '${ts.day}/${ts.month}';
  }

  String _etiquetaTipo(String tipo) {
    switch (tipo) {
      case 'zona_peligrosa':   return 'ZONA PELIGROSA';
      case 'zona_vigilada':    return 'ZONA VIGILADA';
      case 'noticia':          return 'NOTICIA';
      case 'alerta_ciudad':    return 'ALERTA';
      case 'comunicado':       return 'COMUNICADO OFICIAL';
      case 'evento_seguridad': return 'EVENTO';
      default:                 return tipo.toUpperCase();
    }
  }

  List<NoticeItem> _filtrar(List<NoticeItem> all) {
    switch (_categoriaActiva) {
      case _FeedCategory.zonas:
        return all.where((n) => n.tipo == 'zona_peligrosa' || n.tipo == 'zona_vigilada').toList();
      case _FeedCategory.noticias:
        return all.where((n) => n.tipo == 'noticia' || n.tipo == 'alerta_ciudad').toList();
      case _FeedCategory.comunicados:
        return all.where((n) => n.tipo == 'comunicado' || n.tipo == 'evento_seguridad').toList();
      case _FeedCategory.todos:
      default:
        return all;
    }
  }

  // ════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final notices = _filtrar(_notices);

    return Scaffold(
      backgroundColor: azulFondo,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Header ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(25, 25, 25, 0),
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
                          'Seguridad y Noticias en tu ciudad',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.35),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Badge no leídos
                  if (_noLeidos > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$_noLeidos nuevos',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Chips de filtro ─────────────────────────────
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _filterChip('Todos',       Icons.grid_view_rounded,  _FeedCategory.todos),
                  _filterChip('Zonas',       Icons.dangerous_rounded,  _FeedCategory.zonas),
                  _filterChip('Noticias',    Icons.article_rounded,    _FeedCategory.noticias),
                  _filterChip('Comunicados', Icons.campaign_rounded,   _FeedCategory.comunicados),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Lista ───────────────────────────────────────
            Expanded(
              child: notices.isEmpty
                  ? _emptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      itemCount: notices.length,
                      itemBuilder: (context, index) =>
                          _buildNoticeCard(notices[index]),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  // ── Chip de filtro ──────────────────────────────────────
  Widget _filterChip(String label, IconData icon, _FeedCategory cat) {
    final active = _categoriaActiva == cat;
    return GestureDetector(
      onTap: () => setState(() => _categoriaActiva = cat),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? doradoSOS : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? doradoSOS : Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: active ? Colors.black : Colors.white60),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.black : Colors.white60,
                fontSize: 12,
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Estado vacío ────────────────────────────────────────
  Widget _emptyState() {
    final messages = {
      _FeedCategory.todos:       ('Sin avisos por ahora',     Icons.notifications_off_outlined),
      _FeedCategory.zonas:       ('No hay zonas reportadas',   Icons.location_off_outlined),
      _FeedCategory.noticias:    ('No hay noticias recientes', Icons.newspaper_outlined),
      _FeedCategory.comunicados: ('Sin comunicados oficiales', Icons.campaign_outlined),
    };
    final (msg, icon) = messages[_categoriaActiva]!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.2), size: 60),
          const SizedBox(height: 16),
          Text(msg, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 16)),
        ],
      ),
    );
  }

  // ── Card de notice ──────────────────────────────────────
  Widget _buildNoticeCard(NoticeItem notice) {
    final color = _resolverColor(notice.color);
    final icono = _resolverIcono(notice.icono);
    final hora  = _formatearHora(notice.timestamp);

    return GestureDetector(
      onTap: () => _marcarLeido(notice.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: notice.leido
              ? Colors.white.withOpacity(0.04)
              : Colors.white.withOpacity(0.09),
          borderRadius: BorderRadius.circular(20),
          border: Border(left: BorderSide(color: color, width: 6)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: color.withOpacity(0.15),
                child: Icon(icono, color: color, size: 22),
              ),
              const SizedBox(width: 15),
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
                              fontWeight: notice.leido ? FontWeight.w500 : FontWeight.bold,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 5),
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
                              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      notice.mensaje,
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
        BottomNavigationBarItem(icon: Icon(Icons.person_outline),       label: 'Perfil'),
        BottomNavigationBarItem(icon: Icon(Icons.shield_outlined),      label: 'Guardian'),
        BottomNavigationBarItem(icon: Icon(Icons.map_outlined),         label: 'Mapa'),
        BottomNavigationBarItem(icon: Icon(Icons.chat_outlined),        label: 'Chats'),
        BottomNavigationBarItem(icon: Icon(Icons.notifications),        label: 'Avisos'),
      ],
    );
  }
}