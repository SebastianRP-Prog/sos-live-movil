import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/device_alert_service.dart';

import 'screens/splash/splash.dart';
import 'screens/auth/login.dart';
import 'screens/auth/register.dart';
import 'screens/agent/agent_home.dart';

import 'screens/homescreen/profile.dart';
import 'screens/homescreen/guardian.dart';
import 'screens/homescreen/maps.dart';
import 'screens/homescreen/chats.dart';
import 'screens/homescreen/notices.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // 👈 FIX
  );

  await DeviceAlertService.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SOS LIVE',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFD4AF37),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/agent-home': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          return AgentHomeScreen(
            agent: args is Map<String, dynamic> ? args : const {},
          );
        },
        '/profile': (context) => const ProfileScreen(),
        '/guardian': (context) => const GuardianScreen(),
        '/maps': (context) => const MapsScreen(),
        '/chats': (context) => const ChatsScreen(),
        '/notices': (context) => const NoticesScreen(),
      },
    );
  }
}
