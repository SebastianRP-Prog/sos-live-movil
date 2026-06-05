import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../services/auth_services.dart';
import '../../services/chat_service.dart';

enum _LoginRole { persona, agente }

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
  _LoginRole _selectedRole = _LoginRole.persona;

  Future<void> loginSelectedRole() async {
    if (emailController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty) {
      _showSnack(_selectedRole == _LoginRole.persona
          ? 'Completa correo y contrasena'
          : 'Completa nombre y codigo');
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_selectedRole == _LoginRole.agente) {
        final agent = await _authService.loginAgent(
          name: emailController.text.trim(),
          code: passwordController.text.trim(),
        );

        if (!mounted) return;
        if (agent == null) {
          _showSnack('Nombre o codigo de agente incorrectos');
          return;
        }

        final customToken = agent['customToken']?.toString();
        if (customToken != null && customToken.isNotEmpty) {
          final credential =
              await FirebaseAuth.instance.signInWithCustomToken(customToken);
          final uid = credential.user?.uid;
          if (uid != null && uid.isNotEmpty) {
            final agentId = (agent['codigo'] ??
                    agent['code'] ??
                    agent['agentId'] ??
                    uid)
                .toString()
                .trim();
            agent['uid'] = agentId;
            agent['authUid'] = uid;
            agent['agentId'] = agentId;
            ChatService.localSessionUid = agentId;
            ChatService.localSessionName =
                (agent['nombre'] ?? agent['name'] ?? emailController.text.trim())
                    .toString();
          }
        } else {
          final agentId = (agent['codigo'] ??
                  agent['code'] ??
                  agent['agentId'] ??
                  agent['uid'] ??
                  agent['authUid'] ??
                  agent['id'] ??
                  emailController.text.trim())
              .toString()
              .trim();
          agent['uid'] = agentId;
          agent['authUid'] = agentId;
          agent['agentId'] = agentId;
          agent['isLocalAgentSession'] = true;
          ChatService.localSessionUid = agentId;
          ChatService.localSessionName =
              (agent['nombre'] ?? agent['name'] ?? emailController.text.trim())
                  .toString();
        }

        await _authService.saveAgentSession(agent);

        if (!mounted) return;
        Navigator.pushReplacementNamed(
          context,
          '/agent-home',
          arguments: agent,
        );
        return;
      }

      await _authService.login(
        email: emailController.text,
        password: passwordController.text.trim(),
      );
      await _authService.clearAgentSession();
      ChatService.localSessionUid = null;
      ChatService.localSessionName = null;

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/profile');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showSnack(_loginErrorMessage(e.code));
    } catch (e) {
      if (!mounted) return;
      // Muestra el mensaje real del error para facilitar el diagnóstico
      final msg = e.toString().toLowerCase().contains('agente')
          ? e.toString().replaceFirst('Exception: ', '')
          : 'No se pudo iniciar sesion';
      _showSnack(msg);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Restablecer contraseña vía Firebase ─────────────────
  Future<void> _forgotPassword() async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      _showSnack('Escribe tu correo para restablecer la contrasena');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      _showSnack(
          'Correo de restablecimiento enviado. Revisa tu bandeja de entrada');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      switch (e.code) {
        case 'user-not-found':
          _showSnack('No existe una cuenta con ese correo');
          break;
        case 'invalid-email':
          _showSnack('Ingresa un correo valido');
          break;
        case 'too-many-requests':
          _showSnack('Demasiados intentos. Intenta mas tarde');
          break;
        default:
          _showSnack('No se pudo enviar el correo. Intenta de nuevo');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Google Sign-In ───────────────────────────────────────
  // IMPORTANTE: Reemplaza el valor de webClientId con el tuyo.
  // Lo encuentras en: Firebase Console → tu proyecto (sos.live)
  // → Configuración del proyecto → Cuentas de servicio / General
  // → sección "Tus apps" → app Web → "ID de cliente web OAuth 2.0"
  // También está en google-services.json bajo la clave
  // "client" → "oauth_client" → tipo 3 → "client_id"
  static const String _googleWebClientId =
      '1043689888340-gloegn7pedftv4j0ktjevpoomq6kriqr.apps.googleusercontent.com';

  Future<void> signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      // 1. Inicialización limpia usando el Web Client ID correcto
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: _googleWebClientId,
        scopes: ['email', 'profile'],
      );

      // Cierra cualquier sesión previa para forzar el selector de cuenta
      await googleSignIn.signOut();

      // 2. Intentar iniciar sesión
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        // El usuario canceló la selección de cuenta
        setState(() => _isLoading = false);
        return;
      }

      // 3. Obtener la autenticación
      final googleAuth = await googleUser.authentication;

      if (googleAuth.idToken == null || googleAuth.accessToken == null) {
        if (!mounted) return;
        _showSnack('No se pudieron obtener las credenciales de Google.');
        return;
      }

      // 4. Crear la credencial para Firebase
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 5. Autenticar en Firebase
      await FirebaseAuth.instance.signInWithCredential(credential);
      await _authService.clearAgentSession();

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/profile');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showSnack(_loginErrorMessage(e.code));
    } catch (e) {
      if (!mounted) return;
      // IMPORTANTE: Esto imprimirá el error real en tu terminal de VS Code
      // para saber si es un problema de API, de Keystore o de red.
      debugPrint('Error detallado de Google Sign-In: $e');

      _showSnack('No se pudo iniciar con Google. Verifica tu configuracion');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> signInWithFacebook() async {
    setState(() => _isLoading = true);
    try {
      final result = await FacebookAuth.instance.login();

      if (result.status == LoginStatus.success) {
        final accessToken = result.accessToken;
        final credential = FacebookAuthProvider.credential(
          accessToken!.tokenString,
        );

        await FirebaseAuth.instance.signInWithCredential(credential);
        await _authService.clearAgentSession();

        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/profile');
      } else if (result.status == LoginStatus.cancelled) {
        // El usuario canceló, no mostrar error
      } else {
        if (!mounted) return;
        _showSnack('No se pudo iniciar con Facebook');
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('Facebook Sign-In error: $e');
      _showSnack('No se pudo iniciar con Facebook');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _loginErrorMessage(String code) {
    switch (code) {
      case 'email-not-verified':
        return 'Primero verifica tu correo. Abre el enlace y vuelve a iniciar sesion';
      case 'invalid-email':
        return 'Ingresa un correo valido';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Correo o contrasena incorrectos';
      case 'too-many-requests':
        return 'Demasiados intentos. Intenta mas tarde';
      case 'network-request-failed':
        return 'Sin conexion a internet';
      case 'account-exists-with-different-credential':
        return 'Ya existe una cuenta con ese correo. Intenta con otro metodo';
      case 'operation-not-allowed':
        return 'Activa el inicio anonimo en Firebase o levanta el backend con firebase-key.json';
      case 'agent-auth-failed':
        return 'No se pudo crear sesion para el agente';
      default:
        return 'No se pudo iniciar sesion';
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
    final isPersona = _selectedRole == _LoginRole.persona;

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
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            const Text(
              'Vamos\na Iniciar Sesion',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            _buildRoleSelector(),
            const SizedBox(height: 18),
            _buildTextField(
              isPersona ? Icons.email : Icons.badge_outlined,
              isPersona ? 'Email' : 'Nombre del agente',
              false,
              emailController,
            ),
            const SizedBox(height: 15),
            _buildTextField(
              isPersona ? Icons.lock : Icons.pin_outlined,
              isPersona ? 'Contrasena' : 'Codigo',
              true,
              passwordController,
            ),

            // ── Olvidé mi contraseña (solo modo persona) ───
            if (isPersona)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isLoading ? null : _forgotPassword,
                  child: const Text(
                    '¿Olvidaste tu contrasena?',
                    style: TextStyle(
                      color: gold,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 10),
            _isLoading
                ? const CircularProgressIndicator(color: gold)
                : ElevatedButton(
                    onPressed: loginSelectedRole,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: gold,
                      minimumSize: const Size(180, 45),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Text(
                      'Iniciar sesion',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

            if (isPersona) ...[
              const SizedBox(height: 20),
              const Text('o con', style: TextStyle(color: Colors.white)),
              const Divider(color: Colors.white54, indent: 50, endIndent: 50),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _isLoading ? null : signInWithFacebook,
                child: _socialButton(
                  'Continua con Facebook',
                  Icons.facebook,
                  Colors.blue,
                ),
              ),
              const SizedBox(height: 15),
              GestureDetector(
                onTap: _isLoading ? null : signInWithGoogle,
                child: _socialButton(
                  'Continua con Google',
                  Icons.g_mobiledata,
                  Colors.red,
                ),
              ),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'No tienes cuenta? ',
                    style: TextStyle(color: Colors.white),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/register'),
                    child: const Text(
                      'Registrate',
                      style:
                          TextStyle(color: gold, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleSelector() {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          _roleButton('Persona', Icons.person_outline, _LoginRole.persona),
          _roleButton('Agente', Icons.security_outlined, _LoginRole.agente),
        ],
      ),
    );
  }

  Widget _roleButton(String label, IconData icon, _LoginRole role) {
    final selected = _selectedRole == role;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _isLoading
            ? null
            : () {
                setState(() {
                  _selectedRole = role;
                  emailController.clear();
                  passwordController.clear();
                });
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: selected ? gold : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected ? Colors.black : Colors.white70,
                size: 19,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
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
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF101820),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
