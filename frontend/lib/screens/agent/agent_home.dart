// lib/screens/agent/agent_home.dart
//
// Cambios respecto a la versión anterior:
//  • Se añade un 4.º tab "Chat" que aparece cuando el agente tiene una
//    alerta aceptada.  El BottomNavigationBar pasa de 3 a 4 ítems en ese
//    momento.
//  • Al aceptar una alerta se llama a _chatService.openOrCreateChat() para
//    obtener/crear el chatId y se muestra el AgentChatScreen embebido.
//  • El ChatService ya existente se reutiliza sin cambios.

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;

import '../../services/auth_services.dart';
import '../../services/chat_service.dart';
import '../../services/device_alert_service.dart';
import 'agent_chat_screen.dart';

class AgentHomeScreen extends StatefulWidget {
  final Map<String, dynamic> agent;

  const AgentHomeScreen({super.key, required this.agent});

  @override
  State<AgentHomeScreen> createState() => _AgentHomeScreenState();
}

class _AgentHomeScreenState extends State<AgentHomeScreen> {
  static const Color darkBlue = Color(0xFF002133);
  static const Color navBlue = Color(0xFF001F3F);
  static const Color gold = Color(0xFFD4AF37);

  int _index = 0;
  final AuthService _authService = AuthService();
  Timer? _agentAlertTimer;
  final Set<String> _knownAlertIds = <String>{};
  bool _alertWatcherBusy = false;
  bool _alertWatcherPrimed = false;

  /// Datos de la alerta que el agente aceptó actualmente.
  /// null = ninguna alerta aceptada.
  Map<String, dynamic>? _acceptedAlert;

  /// chatId resuelto al aceptar la alerta (para pasarlo al AgentChatScreen).
  String? _activeChatId;
  String? _activeChatUserId;
  String? _activeChatUserName;

  String get _agentName =>
      (widget.agent['nombre'] ?? widget.agent['name'] ?? 'Agente').toString();
  String get _agentId => (widget.agent['codigo'] ??
          widget.agent['code'] ??
          widget.agent['agentId'] ??
          widget.agent['uid'] ??
          widget.agent['userId'] ??
          widget.agent['agentUid'] ??
          widget.agent['acceptedById'] ??
          widget.agent['id'] ??
          '')
      .toString();
  String get _agentCompanyId =>
      (widget.agent['companyId'] ?? widget.agent['empresaId'] ?? '')
          .toString()
          .trim();
  String get _effectiveAgentId {
    final localUid = ChatService.localSessionUid;
    if (localUid != null && localUid.trim().isNotEmpty) {
      return localUid.trim();
    }

    final agentId = _agentId.trim();
    if (agentId.isNotEmpty) {
      return agentId;
    }

    final firebaseUid = FirebaseAuth.instance.currentUser?.uid;
    if (firebaseUid != null && firebaseUid.trim().isNotEmpty) {
      return firebaseUid.trim();
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    final agentId = _effectiveAgentId;
    if (agentId.isNotEmpty) {
      ChatService.localSessionUid = agentId;
      ChatService.localSessionName = _agentName;
    }
    _checkAgentAlertsForNotification();
    _agentAlertTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _checkAgentAlertsForNotification();
    });
  }

  @override
  void dispose() {
    _agentAlertTimer?.cancel();
    super.dispose();
  }

  // ── Callback que recibe _AgentGuardianView cuando acepta/cierra una alerta ──

  void _onAlertAccepted(
    Map<String, dynamic> alert, {
    required String userId,
    required String userName,
    required String chatId,
  }) {
    setState(() {
      _acceptedAlert = alert;
      _activeChatId = chatId;
      _activeChatUserId = userId;
      _activeChatUserName = userName;
      // Saltar automáticamente al tab de chat
      _index = 2;
    });
  }

  void _onChatSelected({
    required String chatId,
    required String userId,
    required String userName,
  }) {
    setState(() {
      _activeChatId = chatId;
      _activeChatUserId = userId;
      _activeChatUserName = userName;
      _index = 2;
    });
  }

  void _showChatList() {
    setState(() {
      _activeChatId = null;
      _activeChatUserId = null;
      _activeChatUserName = null;
      _index = 2;
    });
  }

  void _onAlertClosed() {
    setState(() {
      _acceptedAlert = null;
      _activeChatId = null;
      _activeChatUserId = null;
      _activeChatUserName = null;
    });
  }

  Future<void> _checkAgentAlertsForNotification() async {
    if (_alertWatcherBusy) return;
    _alertWatcherBusy = true;
    try {
      final alerts = await _authService.fetchDashboardAlerts(
        agentName: _agentName,
        agentId: _effectiveAgentId,
        companyId: _agentCompanyId,
      );
      final currentIds =
          alerts.map(_alertNotificationId).where((id) => id.isNotEmpty).toSet();
      final newAlerts = alerts.where(
          (alert) => !_knownAlertIds.contains(_alertNotificationId(alert)));

      if (_alertWatcherPrimed) {
        for (final alert in newAlerts) {
          final person = (alert['persona'] ??
                  alert['userName'] ??
                  alert['usuario'] ??
                  'Usuario SOS')
              .toString();
          await DeviceAlertService.showSosAlert(
            title: 'Nueva alerta SOS',
            body: '$person necesita ayuda inmediata',
          );
        }
      } else if (alerts.isNotEmpty) {
        final first = alerts.first;
        final person = (first['persona'] ??
                first['userName'] ??
                first['usuario'] ??
                'Usuario SOS')
            .toString();
        await DeviceAlertService.showSosAlert(
          title: 'Alerta SOS activa',
          body: '$person necesita ayuda inmediata',
        );
      }

      _knownAlertIds
        ..clear()
        ..addAll(currentIds);
      _alertWatcherPrimed = true;
    } catch (_) {
      // El listado visible de alertas ya muestra errores; no molestamos al agente.
    } finally {
      _alertWatcherBusy = false;
    }
  }

  String _alertNotificationId(Map<String, dynamic> alert) {
    return (alert['id'] ??
            alert['dashboardAlertId'] ??
            '${alert['userId'] ?? alert['uid'] ?? ''}-${alert['createdAt'] ?? ''}')
        .toString();
  }

  // ────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final alertTitle =
        (_acceptedAlert?['title'] ?? _acceptedAlert?['titulo'] ?? 'Alerta SOS')
            .toString();

    final pages = [
      _AgentAlertsView(
        agentName: _agentName,
        agentId: _effectiveAgentId,
        companyId: _agentCompanyId,
      ),
      _AgentGuardianView(
        agentName: _agentName,
        agentId: _effectiveAgentId,
        companyId: _agentCompanyId,
        onAlertAccepted: _onAlertAccepted,
        onAlertClosed: _onAlertClosed,
      ),
      if (_activeChatUserId != null)
        AgentChatScreen(
          alertUserId: _activeChatUserId!,
          alertUserName: _activeChatUserName!,
          alertTitle: alertTitle,
          initialChatId: _activeChatId,
          onBack: _showChatList,
        )
      else
        _AgentChatsView(
          onOpenChat: _onChatSelected,
        ),
      _AgentProfileView(
        agent: widget.agent,
        onLogout: () {
          unawaited(AuthService().clearAgentSession());
          unawaited(FirebaseAuth.instance.signOut());
          ChatService.localSessionUid = null;
          ChatService.localSessionName = null;
          Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        },
      ),
    ];

    // Clamp index por seguridad
    final safeIndex = _index.clamp(0, pages.length - 1).toInt();

    return Scaffold(
      backgroundColor: darkBlue,
      body: pages[safeIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: safeIndex,
        backgroundColor: navBlue,
        selectedItemColor: gold,
        unselectedItemColor: Colors.white60,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _index = index),
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.warning_amber_rounded),
            label: 'Alertas',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.shield_outlined),
            label: 'Guardian',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Chats',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vista de alertas (sin cambios funcionales)
// ─────────────────────────────────────────────────────────────────────────────

class _AgentChatsView extends StatelessWidget {
  final void Function({
    required String chatId,
    required String userId,
    required String userName,
  }) onOpenChat;

  _AgentChatsView({required this.onOpenChat});

  static const Color gold = Color(0xFFD4AF37);
  final ChatService _chatService = ChatService();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AgentHeader(
            title: 'Chats',
            subtitle: 'Conversaciones SOS activas',
            trailing: Icon(Icons.chat_bubble_outline, color: gold),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _chatService.getChatsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: gold),
                  );
                }

                final chats = [...(snapshot.data?.docs ?? [])];
                if (chats.isEmpty) {
                  return const _EmptyState(
                    icon: Icons.chat_bubble_outline,
                    text: 'Aun no tienes chats',
                  );
                }
                chats.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aTime = (aData['updatedAt'] as Timestamp?) ??
                      (aData['lastMessageTime'] as Timestamp?);
                  final bTime = (bData['updatedAt'] as Timestamp?) ??
                      (bData['lastMessageTime'] as Timestamp?);
                  return (bTime?.toDate() ?? DateTime(0))
                      .compareTo(aTime?.toDate() ?? DateTime(0));
                });

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: chats.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final chatId = chats[index].id;
                    final chat = chats[index].data() as Map<String, dynamic>;
                    final participants =
                        List<String>.from(chat['participants'] ?? []);
                    final otherUid = participants.firstWhere(
                      (uid) => uid != _chatService.currentUid,
                      orElse: () => '',
                    );

                    return _AgentChatTile(
                      chatId: chatId,
                      otherUid: otherUid,
                      lastMessage: (chat['lastMessage'] ?? '').toString(),
                      lastMessageTime:
                          (chat['lastMessageTime'] as Timestamp?) ??
                              (chat['updatedAt'] as Timestamp?),
                      lastMessageSenderId:
                          (chat['lastMessageSenderId'] ?? '').toString(),
                      participantNames: Map<String, dynamic>.from(
                          chat['participantNames'] ?? {}),
                      chatService: _chatService,
                      onOpenChat: onOpenChat,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentChatTile extends StatelessWidget {
  static const Color gold = Color(0xFFD4AF37);

  final String chatId;
  final String otherUid;
  final String lastMessage;
  final Timestamp? lastMessageTime;
  final String lastMessageSenderId;
  final Map<String, dynamic> participantNames;
  final ChatService chatService;
  final void Function({
    required String chatId,
    required String userId,
    required String userName,
  }) onOpenChat;

  const _AgentChatTile({
    required this.chatId,
    required this.otherUid,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.lastMessageSenderId,
    required this.participantNames,
    required this.chatService,
    required this.onOpenChat,
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
    final userName = (participantNames[otherUid] ?? 'Usuario SOS').toString();
    final isMine = lastMessageSenderId == chatService.currentUid;
    final preview = lastMessage.isEmpty
        ? 'Toca para chatear'
        : isMine
            ? 'Tu: $lastMessage'
            : lastMessage;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: otherUid.isEmpty
          ? null
          : () => onOpenChat(
                chatId: chatId,
                userId: otherUid,
                userName: userName,
              ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.white12,
              child: Text(
                userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: gold,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preview,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatTime(lastMessageTime),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentAlertsView extends StatefulWidget {
  final String agentName;
  final String agentId;
  final String companyId;

  const _AgentAlertsView({
    required this.agentName,
    required this.agentId,
    required this.companyId,
  });

  @override
  State<_AgentAlertsView> createState() => _AgentAlertsViewState();
}

class _AgentAlertsViewState extends State<_AgentAlertsView> {
  static const Color gold = Color(0xFFD4AF37);
  final AuthService _authService = AuthService();
  late Future<List<Map<String, dynamic>>> _alertsFuture;

  @override
  void initState() {
    super.initState();
    _alertsFuture = _authService.fetchDashboardAlerts(
      agentName: widget.agentName,
      agentId: widget.agentId,
      companyId: widget.companyId,
    );
  }

  Future<void> _reload() async {
    setState(() {
      _alertsFuture = _authService.fetchDashboardAlerts(
        agentName: widget.agentName,
        agentId: widget.agentId,
        companyId: widget.companyId,
      );
    });
    await _alertsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AgentHeader(
            title: 'Alertas',
            subtitle: 'Casos SOS activos para revisar',
            trailing: Icon(Icons.sos_rounded, color: Colors.redAccent),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _alertsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: gold),
                  );
                }

                if (snapshot.hasError) {
                  return RefreshIndicator(
                    onRefresh: _reload,
                    color: gold,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 160),
                        _EmptyState(
                          icon: Icons.cloud_off_outlined,
                          text: 'No se pudieron cargar las alertas',
                        ),
                      ],
                    ),
                  );
                }

                final alerts = snapshot.data ?? [];
                if (alerts.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _reload,
                    color: gold,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 160),
                        _EmptyState(
                          icon: Icons.notifications_off_outlined,
                          text: 'No hay alertas por ahora',
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _reload,
                  color: gold,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: alerts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final alert = alerts[index];
                      return _AlertCard(
                        id: (alert['id'] ?? '').toString(),
                        data: alert,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;

  const _AlertCard({required this.id, required this.data});

  @override
  Widget build(BuildContext context) {
    final title =
        (data['title'] ?? data['titulo'] ?? 'SOS Activado').toString();
    final message = (data['message'] ?? data['mensaje'] ?? '').toString();
    final person =
        (data['persona'] ?? data['userName'] ?? data['nombre'] ?? 'Persona')
            .toString();
    final status = (data['status'] ?? 'active').toString();
    final assigned =
        (data['agenteAsignado'] ?? data['acceptedBy'] ?? '').toString().trim();
    final createdAt = DateTime.tryParse((data['createdAt'] ?? '').toString());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border:
            const Border(left: BorderSide(color: Colors.redAccent, width: 5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _StatusChip(status: status),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            person,
            style: const TextStyle(
              color: Color(0xFFD4AF37),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(message, style: const TextStyle(color: Colors.white70)),
          ],
          if (assigned.isNotEmpty &&
              assigned.toLowerCase() != 'sin asignar') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.badge_outlined,
                  color: Colors.white54,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Asignada a $assigned',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  createdAt == null
                      ? 'Sin fecha'
                      : '${createdAt.day}/${createdAt.month}/${createdAt.year} '
                          '${createdAt.hour.toString().padLeft(2, '0')}:'
                          '${createdAt.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              Text(
                '#${id.substring(0, id.length > 6 ? 6 : id.length)}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vista Guardian — ahora recibe callbacks para avisar al padre del cambio
// ─────────────────────────────────────────────────────────────────────────────

class _AgentGuardianView extends StatefulWidget {
  final String agentName;
  final String agentId;
  final String companyId;

  /// Llamado cuando el agente acepta una alerta.
  final void Function(
    Map<String, dynamic> alert, {
    required String userId,
    required String userName,
    required String chatId,
  }) onAlertAccepted;

  /// Llamado cuando el agente cierra la alerta.
  final VoidCallback onAlertClosed;

  const _AgentGuardianView({
    required this.agentName,
    required this.agentId,
    required this.companyId,
    required this.onAlertAccepted,
    required this.onAlertClosed,
  });

  @override
  State<_AgentGuardianView> createState() => _AgentGuardianViewState();
}

class _AgentGuardianViewState extends State<_AgentGuardianView> {
  final AuthService _authService = AuthService();
  final ChatService _chatService = ChatService();

  late Future<List<Map<String, dynamic>>> _alertsFuture;
  Timer? _refreshTimer;
  StreamSubscription<Position>? _agentGpsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _acceptedAlertSub;
  String? _acceptedAlertId;
  ll.LatLng? _lastRouteDestination;
  Map<String, dynamic>? _pendingRouteAlert;
  List<Map<String, dynamic>> _cachedAlerts = [];
  ll.LatLng? _agentPosition;
  List<ll.LatLng> _routePoints = [];
  String _routeInfo = '';
  bool _calculatingRoute = false;
  bool _isActionBusy = false;
  bool _agentLocationUpdateBusy = false;

  @override
  void initState() {
    super.initState();
    _alertsFuture = _authService.fetchDashboardAlerts(
      agentName: widget.agentName,
      agentId: widget.agentId,
      companyId: widget.companyId,
    );
    _alertsFuture.then((alerts) {
      if (!mounted) return;
      setState(() => _cachedAlerts = alerts);
      _syncAcceptedAlertListener(alerts);
    }).catchError((_) {});
    _loadAgentPosition();
    _startAgentLocationTracking();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_isActionBusy && !_calculatingRoute) {
        _reload(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _agentGpsSub?.cancel();
    _acceptedAlertSub?.cancel();
    super.dispose();
  }

  Future<void> _reload({bool silent = false}) async {
    final nextFuture = _authService.fetchDashboardAlerts(
      agentName: widget.agentName,
      agentId: widget.agentId,
      companyId: widget.companyId,
    );
    setState(() {
      _alertsFuture = nextFuture;
    });
    try {
      final alerts = await nextFuture;
      if (mounted) {
        setState(() => _cachedAlerts = alerts);
        _syncAcceptedAlertListener(alerts);
      }
    } catch (_) {
      if (!silent) rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const _AgentHeader(
            title: 'Guardian',
            subtitle: 'Mapa de alertas',
            trailing: Icon(Icons.shield_outlined, color: Color(0xFFD4AF37)),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _alertsFuture,
              initialData: _cachedAlerts,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    _cachedAlerts.isEmpty) {
                  return const _AgentMapLoading(expanded: true);
                }

                final alerts = _cachedAlerts.isNotEmpty
                    ? _cachedAlerts
                    : snapshot.data ?? const <Map<String, dynamic>>[];
                final points = alerts
                    .map(_AlertMapPoint.fromAlert)
                    .whereType<_AlertMapPoint>()
                    .toList();

                return _AgentAlertsMap(
                  points: points,
                  agentPosition: _agentPosition,
                  routePoints: _routePoints,
                  routeInfo: _routeInfo,
                );
              },
            ),
          ),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _alertsFuture,
            initialData: _cachedAlerts,
            builder: (context, snapshot) {
              final alerts = _cachedAlerts.isNotEmpty
                  ? _cachedAlerts
                  : snapshot.data ?? const <Map<String, dynamic>>[];
              final currentAlert = _firstActionableAlert(alerts);

              return _GuardianAcceptPanel(
                alert: currentAlert,
                isLoading: _isActionBusy ||
                    (snapshot.connectionState == ConnectionState.waiting &&
                        _cachedAlerts.isEmpty),
                onRefresh: () => unawaited(_reload()),
                routeInfo: _routeInfo,
                isCalculatingRoute: _calculatingRoute,
                onAccept: _isActionBusy ||
                        currentAlert == null ||
                        _isAcceptedByMe(currentAlert)
                    ? null
                    : () => _acceptAlert(currentAlert),
                onClose: null,
              );
            },
          ),
        ],
      ),
    );
  }

  Map<String, dynamic>? _firstActionableAlert(
      List<Map<String, dynamic>> alerts) {
    for (final alert in alerts) {
      if (_isAcceptedByMe(alert)) return alert;
    }
    for (final alert in alerts) {
      final status = (alert['status'] ?? alert['estado'] ?? '').toString();
      final assigned = (alert['agenteAsignado'] ?? '').toString().trim();
      final normalized = status.toLowerCase();
      if ((normalized.isEmpty ||
              normalized == 'active' ||
              normalized == 'activa') &&
          (assigned.isEmpty || assigned.toLowerCase() == 'sin asignar')) {
        return alert;
      }
    }
    return null;
  }

  bool _isAcceptedByMe(Map<String, dynamic> alert) {
    final status = (alert['status'] ?? alert['estado'] ?? '').toString();
    final assigned = (alert['agenteAsignado'] ?? alert['acceptedBy'] ?? '')
        .toString()
        .trim();
    final normalized = status.toLowerCase();
    return (normalized == 'accepted' ||
            normalized == 'aceptada' ||
            normalized == 'aceptado') &&
        assigned.toLowerCase() == widget.agentName.trim().toLowerCase();
  }

  void _syncAcceptedAlertListener(List<Map<String, dynamic>> alerts) {
    Map<String, dynamic>? acceptedAlert;
    for (final alert in alerts) {
      if (_isAcceptedByMe(alert)) {
        acceptedAlert = alert;
        break;
      }
    }
    _watchAcceptedAlert(acceptedAlert);
  }

  void _watchAcceptedAlert(Map<String, dynamic>? alert) {
    final alertId = (alert?['id'] ?? '').toString();
    if (alertId.isEmpty) {
      _acceptedAlertSub?.cancel();
      _acceptedAlertSub = null;
      _acceptedAlertId = null;
      _lastRouteDestination = null;
      _pendingRouteAlert = null;
      return;
    }
    if (alertId == _acceptedAlertId) return;

    _acceptedAlertSub?.cancel();
    _acceptedAlertId = alertId;
    _lastRouteDestination = _AlertMapPoint.fromAlert(alert!)?.position;
    if (_routePoints.isEmpty && !_calculatingRoute) {
      unawaited(_calculateFastRoute(alert));
    }
    _acceptedAlertSub = FirebaseFirestore.instance
        .collection('dashboard_alerts')
        .doc(alertId)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      if (data == null || !mounted) return;

      final updatedAlert = {'id': snapshot.id, ...data};
      if (!_isAcceptedByMe(updatedAlert)) return;

      setState(() {
        final index =
            _cachedAlerts.indexWhere((item) => item['id'] == snapshot.id);
        if (index >= 0) {
          _cachedAlerts[index] = updatedAlert;
        } else {
          _cachedAlerts = [updatedAlert, ..._cachedAlerts];
        }
      });

      final destination = _AlertMapPoint.fromAlert(updatedAlert)?.position;
      if (destination == null || !_destinationMoved(destination)) return;
      if (_calculatingRoute) {
        _pendingRouteAlert = updatedAlert;
        return;
      }
      _lastRouteDestination = destination;
      unawaited(_calculateFastRoute(updatedAlert));
    });
  }

  bool _destinationMoved(ll.LatLng destination) {
    final previous = _lastRouteDestination;
    if (previous == null) return true;
    return Geolocator.distanceBetween(
          previous.latitude,
          previous.longitude,
          destination.latitude,
          destination.longitude,
        ) >=
        8;
  }

  Future<void> _loadAgentPosition() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() =>
          _agentPosition = ll.LatLng(position.latitude, position.longitude));
      unawaited(_publishAgentLocation(position));
      Map<String, dynamic>? acceptedAlert;
      for (final alert in _cachedAlerts) {
        if (_isAcceptedByMe(alert)) {
          acceptedAlert = alert;
          break;
        }
      }
      if (acceptedAlert != null && _routePoints.isEmpty && !_calculatingRoute) {
        unawaited(_calculateFastRoute(acceptedAlert));
      }
    } catch (_) {}
  }

  Future<void> _startAgentLocationTracking() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      await _agentGpsSub?.cancel();
      _agentGpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((position) {
        if (!mounted) return;
        setState(() {
          _agentPosition = ll.LatLng(position.latitude, position.longitude);
        });
        unawaited(_publishAgentLocation(position));
      });
    } catch (_) {}
  }

  Future<void> _publishAgentLocation(Position position) async {
    await _publishAgentCoordinates(
      lat: position.latitude,
      lng: position.longitude,
      heading: position.heading,
      speed: position.speed,
      accuracy: position.accuracy,
    );
  }

  Future<void> _publishAgentCoordinates({
    required double lat,
    required double lng,
    double? heading,
    double? speed,
    double? accuracy,
  }) async {
    if (_agentLocationUpdateBusy) return;

    final agentId = widget.agentId.trim();
    if (agentId.isEmpty) return;

    final alertId = _acceptedAlertId ?? _acceptedAlertIdFromCache();

    _agentLocationUpdateBusy = true;
    final location = {
      'lat': lat,
      'lng': lng,
      if (heading != null) 'heading': heading,
      if (speed != null) 'speed': speed,
      if (accuracy != null) 'accuracy': accuracy,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final locationLabel = 'lat $lat, lng $lng';
    final agentUpdate = {
      'location': location,
      'mapa': {
        ...location,
        'label': locationLabel,
        'query': '$lat,$lng',
        'source': 'device',
        'precision': 'exact',
      },
      'ubicacionExacta': locationLabel,
      'ultimaUbicacionTexto': locationLabel,
      'ultimaConexionAt': DateTime.now().toIso8601String(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (widget.companyId.trim().isNotEmpty) ...{
        'companyId': widget.companyId.trim(),
        'companyUid': widget.companyId.trim(),
      },
    };
    final update = {
      'agentLocation': location,
      'guardianLocation': location,
      'agentId': agentId,
      'agentName': widget.agentName,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      final db = FirebaseFirestore.instance;
      for (final collectionName in ['dashboard_agents', 'Agentes']) {
        try {
          await db
              .collection(collectionName)
              .doc(agentId)
              .set(agentUpdate, SetOptions(merge: true));
        } catch (_) {}
      }

      if (alertId != null && alertId.isNotEmpty) {
        await db
            .collection('dashboard_alerts')
            .doc(alertId)
            .set(update, SetOptions(merge: true));
        for (final collectionName in ['sos_alerts', 'alertas_activas']) {
          try {
            await db
                .collection(collectionName)
                .doc(alertId)
                .set(update, SetOptions(merge: true));
          } catch (_) {}
        }
      }
    } catch (_) {
      // La ruta local sigue funcionando aunque Firestore rechace un pulso GPS.
    } finally {
      _agentLocationUpdateBusy = false;
    }
  }

  String? _acceptedAlertIdFromCache() {
    for (final alert in _cachedAlerts) {
      if (_isAcceptedByMe(alert)) {
        final id = (alert['id'] ?? '').toString();
        if (id.isNotEmpty) return id;
      }
    }
    return null;
  }

  Future<void> _acceptAlert(Map<String, dynamic> alert) async {
    final alertId = (alert['id'] ?? '').toString();
    if (alertId.isEmpty) return;

    setState(() => _isActionBusy = true);
    try {
      await _loadAgentPosition();
      await _authService.acceptDashboardAlert(
        alertId: alertId,
        agentName: widget.agentName,
        agentId: widget.agentId,
        companyId: widget.companyId,
      );
      _acceptedAlertId = alertId;
      final currentPosition = _agentPosition;
      if (currentPosition != null) {
        unawaited(_publishAgentCoordinates(
          lat: currentPosition.latitude,
          lng: currentPosition.longitude,
        ));
      }
      await _calculateFastRoute(alert);
      await _reload();

      // ── NUEVO: resolver uid/nombre del usuario y abrir/crear chat ────────
      final userId =
          (alert['userId'] ?? alert['uid'] ?? alert['senderId'] ?? '')
              .toString()
              .trim();

      if (userId.isNotEmpty) {
        final userName = (alert['persona'] ??
                alert['userName'] ??
                alert['usuario'] ??
                'Usuario SOS')
            .toString();
        final chatId = await _chatService.openOrCreateChat(
          userId,
          otherName: userName,
          currentName: widget.agentName,
        );
        final acceptedAlert = {
          ...alert,
          'status': 'accepted',
          'estado': 'accepted',
          'agenteAsignado': widget.agentName,
          'acceptedBy': widget.agentName,
          if (widget.agentId.trim().isNotEmpty) ...{
            'agentId': widget.agentId.trim(),
            'agentUid': widget.agentId.trim(),
            'acceptedById': widget.agentId.trim(),
            'guardianId': widget.agentId.trim(),
          },
        };

        if (!mounted) return;
        widget.onAlertAccepted(
          acceptedAlert,
          userId: userId,
          userName: userName,
          chatId: chatId,
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Alerta aceptada, pero no se encontro el usuario para chat'),
          ),
        );
      }
      // ─────────────────────────────────────────────────────────────────────

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alerta aceptada')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo aceptar la alerta')),
      );
    } finally {
      if (mounted) setState(() => _isActionBusy = false);
    }
  }

  Future<void> _closeAlert(Map<String, dynamic> alert) async {
    final alertId = (alert['id'] ?? '').toString();
    if (alertId.isEmpty) return;

    setState(() => _isActionBusy = true);
    try {
      await _authService.closeDashboardAlert(
        alertId: alertId,
        agentName: widget.agentName,
      );
      if (!mounted) return;
      setState(() {
        _routePoints = [];
        _routeInfo = '';
      });
      await _reload();
      widget.onAlertClosed(); // ← notifica al padre
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alerta cerrada')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cerrar la alerta')),
      );
    } finally {
      if (mounted) setState(() => _isActionBusy = false);
    }
  }

  Future<void> _calculateFastRoute(Map<String, dynamic> alert) async {
    final origin = _agentPosition;
    final destination = _AlertMapPoint.fromAlert(alert)?.position;
    if (origin == null || destination == null) return;

    setState(() {
      _calculatingRoute = true;
      _routePoints = [];
      _routeInfo = 'Calculando ruta...';
    });

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      final routes = decoded['routes'] as List? ?? [];
      if (routes.isEmpty) return;

      final route = routes.first as Map<String, dynamic>;
      final coords = route['geometry']['coordinates'] as List? ?? [];
      final distance = (route['distance'] as num?)?.toDouble() ?? 0;
      final duration = (route['duration'] as num?)?.toDouble() ?? 0;
      final points = coords
          .whereType<List>()
          .map((coord) => ll.LatLng(
                (coord[1] as num).toDouble(),
                (coord[0] as num).toDouble(),
              ))
          .toList();

      if (!mounted) return;
      setState(() {
        _routePoints = points;
        _routeInfo =
            '${(distance / 1000).toStringAsFixed(1)} km • ${(duration / 60).round()} min';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _routeInfo = 'No se pudo calcular ruta');
    } finally {
      Map<String, dynamic>? pendingAlert;
      if (mounted) {
        setState(() => _calculatingRoute = false);
        pendingAlert = _pendingRouteAlert;
        _pendingRouteAlert = null;
      }
      final pendingDestination = pendingAlert == null
          ? null
          : _AlertMapPoint.fromAlert(pendingAlert)?.position;
      if (mounted &&
          pendingAlert != null &&
          pendingDestination != null &&
          _destinationMoved(pendingDestination)) {
        _lastRouteDestination = pendingDestination;
        unawaited(_calculateFastRoute(pendingAlert));
      }
    }
  }
}

// ─── Widgets de mapa y panel (sin cambios) ────────────────────────────────────

class _AgentMapLoading extends StatelessWidget {
  final bool expanded;
  const _AgentMapLoading({this.expanded = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: expanded ? double.infinity : 260,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const CircularProgressIndicator(color: Color(0xFFD4AF37)),
    );
  }
}

class _AgentAlertsMap extends StatefulWidget {
  final List<_AlertMapPoint> points;
  final ll.LatLng? agentPosition;
  final List<ll.LatLng> routePoints;
  final String routeInfo;

  const _AgentAlertsMap({
    required this.points,
    required this.agentPosition,
    required this.routePoints,
    required this.routeInfo,
  });

  @override
  State<_AgentAlertsMap> createState() => _AgentAlertsMapState();
}

class _AgentAlertsMapState extends State<_AgentAlertsMap> {
  final MapController _mapController = MapController();
  ll.LatLng? _lastCenteredPoint;

  @override
  void didUpdateWidget(covariant _AgentAlertsMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextCenter = _mapCenter();
    final previous = _lastCenteredPoint;
    if (previous == null || _movedEnough(previous, nextCenter)) {
      _lastCenteredPoint = nextCenter;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.move(nextCenter, widget.points.isNotEmpty ? 14 : 11);
      });
    }
  }

  ll.LatLng _mapCenter() {
    if (widget.points.isNotEmpty) return widget.points.first.position;
    return const ll.LatLng(4.7110, -74.0721);
  }

  bool _movedEnough(ll.LatLng previous, ll.LatLng next) {
    return Geolocator.distanceBetween(
          previous.latitude,
          previous.longitude,
          next.latitude,
          next.longitude,
        ) >=
        8;
  }

  @override
  Widget build(BuildContext context) {
    final center = _mapCenter();
    _lastCenteredPoint ??= center;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: widget.points.isNotEmpty ? 13 : 11,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.sosLive.app',
              ),
              if (widget.routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: widget.routePoints,
                      color: const Color(0xFFD4AF37),
                      strokeWidth: 5,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  ...widget.points.map(
                    (point) => Marker(
                      point: point.position,
                      width: 46,
                      height: 46,
                      child: Tooltip(
                        message: point.title,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.redAccent,
                          size: 42,
                        ),
                      ),
                    ),
                  ),
                  if (widget.agentPosition != null)
                    Marker(
                      point: widget.agentPosition!,
                      width: 42,
                      height: 42,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF002133),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFD4AF37),
                            width: 3,
                          ),
                        ),
                        child: const Icon(
                          Icons.navigation_rounded,
                          color: Color(0xFFD4AF37),
                          size: 24,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF002133).withOpacity(0.86),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.points.isEmpty
                    ? 'Sin alertas con ubicacion'
                    : widget.routeInfo.isNotEmpty
                        ? 'Ruta rapida: ${widget.routeInfo}'
                        : '${widget.points.length} alertas en mapa',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuardianAcceptPanel extends StatelessWidget {
  final Map<String, dynamic>? alert;
  final bool isLoading;
  final bool isCalculatingRoute;
  final String routeInfo;
  final VoidCallback onRefresh;
  final VoidCallback? onAccept;
  final VoidCallback? onClose;

  const _GuardianAcceptPanel({
    required this.alert,
    required this.isLoading,
    required this.isCalculatingRoute,
    required this.routeInfo,
    required this.onRefresh,
    required this.onAccept,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final hasAlert = alert != null;
    final person =
        (alert?['persona'] ?? alert?['userName'] ?? alert?['usuario'] ?? '')
            .toString();
    final title =
        (alert?['title'] ?? alert?['titulo'] ?? 'Alerta pendiente').toString();
    final status = (alert?['status'] ?? alert?['estado'] ?? '').toString();
    final isAccepted = status.toLowerCase() == 'accepted' ||
        status.toLowerCase() == 'aceptada' ||
        status.toLowerCase() == 'aceptado';

    return Container(
      height: 96,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF001F3F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasAlert ? Colors.redAccent : Colors.white12,
          width: hasAlert ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasAlert
                ? Icons.warning_amber_rounded
                : Icons.notifications_none_rounded,
            color: hasAlert ? Colors.redAccent : Colors.white54,
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLoading
                      ? 'Cargando alertas'
                      : hasAlert
                          ? title
                          : 'Espacio para aceptar alertas',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasAlert
                      ? isAccepted
                          ? 'En atención: ${person.isEmpty ? 'persona SOS' : person}'
                          : (person.isEmpty ? 'Alerta sin asignar' : person)
                      : routeInfo.isNotEmpty
                          ? 'Ruta activa: $routeInfo'
                          : 'Cuando llegue una alerta aparecerá aquí',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (hasAlert)
            ElevatedButton(
              onPressed: isCalculatingRoute
                  ? null
                  : isAccepted
                      ? onClose
                      : onAccept,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isAccepted ? Colors.greenAccent : const Color(0xFFD4AF37),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                isCalculatingRoute
                    ? 'Ruta...'
                    : isAccepted
                        ? 'En atención'
                        : 'Aceptar',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            )
          else
            IconButton(
              onPressed: onRefresh,
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh, color: Color(0xFFD4AF37)),
            ),
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _AlertMapPoint {
  final ll.LatLng position;
  final String title;

  const _AlertMapPoint({required this.position, required this.title});

  static _AlertMapPoint? fromAlert(Map<String, dynamic> alert) {
    final ubicacionActiva =
        alert['ubicacionActiva'] is Map ? alert['ubicacionActiva'] : null;
    final lat = _readDouble(ubicacionActiva?['lat']) ??
        _readDouble(alert['lat']) ??
        _readDouble(
            (alert['location'] is Map) ? alert['location']['lat'] : null);
    final lng = _readDouble(ubicacionActiva?['lng']) ??
        _readDouble(alert['lng']) ??
        _readDouble(
            (alert['location'] is Map) ? alert['location']['lng'] : null);

    if (lat == null || lng == null) return null;

    final title =
        (alert['persona'] ?? alert['userName'] ?? alert['usuario'] ?? 'Alerta')
            .toString();

    return _AlertMapPoint(position: ll.LatLng(lat, lng), title: title);
  }

  static double? _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

class _AgentProfileView extends StatelessWidget {
  final Map<String, dynamic> agent;
  final VoidCallback onLogout;

  const _AgentProfileView({required this.agent, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final name = (agent['nombre'] ?? agent['name'] ?? 'Agente').toString();
    final code = (agent['codigo'] ?? agent['code'] ?? '').toString();
    final email = (agent['email'] ?? agent['correo'] ?? '').toString();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _AgentHeader(
            title: 'Perfil',
            subtitle: 'Sesión de agente',
            trailing: Icon(Icons.badge_outlined, color: Color(0xFFD4AF37)),
          ),
          _InfoPanel(icon: Icons.person_outline, title: 'Nombre', text: name),
          if (code.isNotEmpty)
            _InfoPanel(icon: Icons.pin_outlined, title: 'Código', text: code),
          if (email.isNotEmpty)
            _InfoPanel(
                icon: Icons.email_outlined, title: 'Correo', text: email),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout, color: Colors.black),
              label: const Text(
                'Cerrar sesión',
                style:
                    TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget trailing;

  const _AgentHeader({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.white54)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _InfoPanel({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFD4AF37)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(text, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final isActive = normalized == 'active' || normalized == 'activa';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isActive ? Colors.redAccent : Colors.green).withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isActive ? 'ACTIVA' : status.toUpperCase(),
        style: TextStyle(
          color: isActive ? Colors.redAccent : Colors.greenAccent,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white24, size: 58),
          const SizedBox(height: 14),
          Text(text, style: const TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }
}
