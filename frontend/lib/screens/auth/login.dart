import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../services/auth_services.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const Color darkBlue = Color(0xFF002133);
  static const Color snackBlue = Color(0xFF1A3A45);
  static const Color gold = Color(0xFFD4AF37);

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _obscurePassword = true;
  bool _isLoading = false;

  Future<void> loginFirebase() async {
    if (emailController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty) {
      _showSnack('Completa correo y contraseña');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _authService.login(
        email: emailController.text,
        password: passwordController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/profile');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showSnack(_loginErrorMessage(e.code));
    } catch (_) {
      if (!mounted) return;
      _showSnack('No se pudo iniciar sesión');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> resendVerificationEmail() async {
    if (emailController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty) {
      _showSnack('Escribe tu correo y contraseña para reenviar el enlace');
      return;
    }

    setState(() => _isLoading = true);
    final message = await _authService.resendVerificationEmail(
      email: emailController.text,
      password: passwordController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);
    _showSnack(message ?? 'Tu correo ya está verificado. Intenta ingresar');
  }

  Future<void> signInWithGoogle() async {
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/profile');
    } catch (_) {
      if (!mounted) return;
      _showSnack('No se pudo iniciar con Google');
    }
  }

  Future<void> signInWithFacebook() async {
    try {
      final result = await FacebookAuth.instance.login();

      if (result.status == LoginStatus.success) {
        final accessToken = result.accessToken;
        final credential = FacebookAuthProvider.credential(
          accessToken!.tokenString,
        );

        await FirebaseAuth.instance.signInWithCredential(credential);

        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/profile');
      } else {
        _showSnack('Inicio con Facebook cancelado');
      }
    } catch (_) {
      if (!mounted) return;
      _showSnack('No se pudo iniciar con Facebook');
    }
  }

  String _loginErrorMessage(String code) {
    switch (code) {
      case 'email-not-verified':
        return 'Primero verifica tu correo. Abre el enlace y vuelve a iniciar sesión';
      case 'invalid-email':
        return 'Ingresa un correo válido';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Correo o contraseña incorrectos';
      case 'too-many-requests':
        return 'Demasiados intentos. Intenta más tarde';
      case 'network-request-failed':
        return 'Sin conexión a internet';
      default:
        return 'No se pudo iniciar sesión';
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        duration: const Duration(seconds: 5),
        backgroundColor: snackBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBlue,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          children: [
            const SizedBox(height: 60),
            Image.network(
              'https://i.ibb.co/H67HDR4/4418fbb8f92cde89a97eee446ab6a01d07cc34d5-removebg-preview.png',
              width: 80,
            ),
            const Text(
              'Seguridad a tu alcance',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            const Text(
              'Vamos\na Iniciar Sesión',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 40),
            _buildTextField(Icons.email, 'Email', false, emailController),
            const SizedBox(height: 15),
            _buildTextField(
              Icons.lock,
              'Contraseña',
              true,
              passwordController,
            ),
            const SizedBox(height: 25),
            _isLoading
                ? const CircularProgressIndicator(color: gold)
                : ElevatedButton(
                    onPressed: loginFirebase,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: gold,
                      minimumSize: const Size(180, 45),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Text(
                      'Iniciar sesión',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
            TextButton(
              onPressed: _isLoading ? null : resendVerificationEmail,
              child: const Text(
                'Reenviar correo de verificación',
                style: TextStyle(color: gold, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 20),
            const Text('o con', style: TextStyle(color: Colors.white)),
            const Divider(color: Colors.white54, indent: 50, endIndent: 50),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: signInWithFacebook,
              child: _socialButton(
                'Continúa con Facebook',
                Icons.facebook,
                Colors.blue,
              ),
            ),
            const SizedBox(height: 15),
            GestureDetector(
              onTap: signInWithGoogle,
              child: _socialButton(
                'Continúa con Google',
                Icons.g_mobiledata,
                Colors.red,
              ),
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '¿No tienes cuenta? ',
                  style: TextStyle(color: Colors.white),
                ),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/register'),
                  child: const Text(
                    'Regístrate',
                    style: TextStyle(color: gold, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    IconData icon,
    String hint,
    bool isPass,
    TextEditingController controller,
  ) {
    return TextField(
      controller: controller,
      obscureText: isPass ? _obscurePassword : false,
      style: const TextStyle(
        color: Color(0xFF101820),
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: gold),
        suffixIcon: isPass
            ? IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: const Color(0xFF374151),
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              )
            : null,
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF4B5563)),
        filled: true,
        fillColor: const Color(0xFFF7F7F7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _socialButton(String text, IconData icon, Color color) {
    return Container(
      width: double.infinity,
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF101820),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
