import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_services.dart';
import '../../services/chat_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  Future<void> _startTimer() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    final savedAgent = await _authService.getSavedAgentSession();
    if (!mounted) return;

    if (savedAgent != null) {
      final agentId = (savedAgent['codigo'] ??
              savedAgent['code'] ??
              savedAgent['agentId'] ??
              savedAgent['uid'] ??
              savedAgent['authUid'] ??
              savedAgent['id'] ??
              '')
          .toString()
          .trim();
      if (agentId.isNotEmpty) {
        ChatService.localSessionUid = agentId;
        ChatService.localSessionName =
            (savedAgent['nombre'] ?? savedAgent['name'] ?? 'Agente').toString();
      }

      Navigator.pushReplacementNamed(
        context,
        '/agent-home',
        arguments: savedAgent,
      );
      return;
    }

    if (FirebaseAuth.instance.currentUser != null) {
      Navigator.pushReplacementNamed(context, '/profile');
      return;
    }

    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF083B4C),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.network(
              'https://i.ibb.co/H67HDR4/4418fbb8f92cde89a97eee446ab6a01d07cc34d5-removebg-preview.png',
              width: 120,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.error,
                color: Colors.white,
                size: 50,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Cargando...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(
              color: Colors.white70,
              strokeWidth: 3,
            ),
          ],
        ),
      ),
    );
  }
}
