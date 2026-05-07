import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../services/auth_services.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  // â”€â”€ Colores â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static const Color darkBlue  = Color(0xFF002133);
  static const Color gold      = Color(0xFFD4AF37);
  static const Color lightGray = Color(0xFFD9D9D9);

  // â”€â”€ Datos del usuario â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  String name      = '';
  String email     = '';
  String age       = '';
  String gender    = '';
  String bloodType = '';
  bool   isLoading = true;
  final AuthService _authService = AuthService();

  late AnimationController _animController;
  late Animation<double>    _fadeAnim;

  // â”€â”€ URL base igual que register.dart â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _loadUserData();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // â”€â”€ Carga datos desde el backend Node.js â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _loadUserData() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() => isLoading = false);
        return;
      }

      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data() ?? {};
      setState(() {
        name = data['name'] ?? data['nombre'] ?? 'Usuario';
        email = data['email'] ?? FirebaseAuth.instance.currentUser?.email ?? '';
        age = data['age']?.toString() ?? data['edad']?.toString() ?? '--';
        gender = data['gender'] ?? data['sexo'] ?? '--';
        bloodType = data['bloodType'] ?? data['tipoSangre'] ?? '--';
        isLoading = false;
      });
      _animController.forward();
    } catch (e) {
      setState(() {
        email     = FirebaseAuth.instance.currentUser?.email ?? '';
        name      = 'Usuario';
        isLoading = false;
      });
      _showSnack('Error de conexiÃ³n: Â¿El servidor estÃ¡ activo?');
    }
  }

  // â”€â”€ Logout â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _handleLogout() async {
    final confirmed = await _showConfirmDialog(
      title: 'Cerrar SesiÃ³n',
      message: 'Â¿EstÃ¡s seguro de que deseas cerrar sesiÃ³n?',
      confirmLabel: 'Salir',
      confirmColor: Colors.redAccent,
    );
    if (!confirmed) return;

    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  // â”€â”€ Editar perfil â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _handleEditProfile() async {
    final nameCtrl      = TextEditingController(text: name);
    final ageCtrl       = TextEditingController(text: age == '--' ? '' : age);
    String? newGender   = gender   == '--' ? null : gender;
    String? newBlood    = bloodType == '--' ? null : bloodType;

    final List<String> genderOpts = ['Masculino', 'Femenino', 'Otro'];
    final List<String> bloodOpts  = ['O+','O-','A+','A-','B+','B-','AB+','AB-'];

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          backgroundColor: const Color(0xFF002B36),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: gold, width: 1.5),
          ),
          title: const Text('Editar Perfil',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogField(nameCtrl, Icons.person, 'Nombre Completo'),
                const SizedBox(height: 12),
                _dialogField(ageCtrl,  Icons.cake,   'Edad',
                    inputType: TextInputType.number),
                const SizedBox(height: 12),
                _dialogDropdown(
                  icon: Icons.wc, hint: 'Sexo',
                  items: genderOpts, value: newGender,
                  onChanged: (v) => setS(() => newGender = v),
                ),
                const SizedBox(height: 12),
                _dialogDropdown(
                  icon: Icons.bloodtype, hint: 'Tipo de sangre',
                  items: bloodOpts, value: newBlood,
                  onChanged: (v) => setS(() => newBlood = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar',
                  style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: gold,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar',
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;

    final uid  = FirebaseAuth.instance.currentUser?.uid;
    final edad = int.tryParse(ageCtrl.text.trim());

    if (nameCtrl.text.trim().isEmpty) {
      _showSnack('El nombre no puede estar vacÃ­o');
      return;
    }
    if (uid == null) return;

    setState(() => isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        "name": nameCtrl.text.trim(),
        "email": FirebaseAuth.instance.currentUser?.email,
        "age": edad,
        "gender": newGender,
        "bloodType": newBlood,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _showSnack('Perfil actualizado correctamente');
      await _loadUserData();
    } catch (e) {
      _showSnack('Error de conexiÃ³n al actualizar');
      setState(() => isLoading = false);
    }
  }

  // â”€â”€ Cambiar contraseÃ±a (envÃ­a email de reset) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _handleChangePassword() async {
    final confirmed = await _showConfirmDialog(
      title: 'Cambiar ContraseÃ±a',
      message:
          'Te enviaremos un correo a\n$email\npara restablecer tu contraseÃ±a.',
      confirmLabel: 'Enviar correo',
      confirmColor: gold,
    );
    if (!confirmed) return;

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showSnack('ðŸ“§ Correo de restablecimiento enviado a $email');
    } catch (e) {
      _showSnack('Error al enviar el correo: $e');
    }
  }

  // â”€â”€ Historial â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _handleHistory() {
    Navigator.pushNamed(context, '/historial');
  }

  // â”€â”€ SimulaciÃ³n de SOS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _handleSimulation() {
    Navigator.pushNamed(context, '/simulacion');
  }

  // â”€â”€ Ajustes de alerta â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _handleAlertSettings() {
    Navigator.pushNamed(context, '/ajustes-alerta');
  }

  // â”€â”€ Verificar email (si aÃºn no verificÃ³) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _handleVerifyEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (user.emailVerified) {
      _showSnack('âœ… Tu correo ya estÃ¡ verificado');
      return;
    }
    try {
      await _authService.sendVerificationEmailToCurrentUser();
      _showSnack('ðŸ“§ Correo de verificaciÃ³n enviado');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'too-many-requests') {
        _showSnack('Demasiados intentos. Intenta mas tarde');
        return;
      }
      _showSnack('No se pudo enviar el correo de verificaciÃ³n');
    } catch (_) {
      _showSnack('No se pudo enviar el correo de verificaciÃ³n');
    }
  }

  // â”€â”€ Eliminar cuenta â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _handleDeleteAccount() async {
    final confirmed = await _showConfirmDialog(
      title: 'âš ï¸ Eliminar Cuenta',
      message:
          'Esta acciÃ³n es IRREVERSIBLE.\nSe eliminarÃ¡n todos tus datos.\n\nÂ¿Deseas continuar?',
      confirmLabel: 'Eliminar',
      confirmColor: Colors.red,
    );
    if (!confirmed) return;

    final uid  = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      await FirebaseAuth.instance.currentUser?.delete();

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      }
    } catch (e) {
      setState(() => isLoading = false);
      _showSnack('Error al eliminar la cuenta: $e');
    }
  }

  // â”€â”€ Helpers UI â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFF1A3A45),
      duration: const Duration(seconds: 4),
    ));
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF002B36),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: gold, width: 1.5),
            ),
            title: Text(title,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            content: Text(message,
                style: const TextStyle(color: Colors.white70, height: 1.5)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar',
                    style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: confirmColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel,
                    style: const TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _dialogField(
    TextEditingController ctrl,
    IconData icon,
    String hint, {
    TextInputType inputType = TextInputType.text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: ctrl,
        keyboardType: inputType,
        style: const TextStyle(color: Colors.black),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: gold),
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.black54),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _dialogDropdown({
    required IconData icon,
    required String hint,
    required List<String> items,
    required String? value,
    required Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        dropdownColor: Colors.white,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: gold),
          border: InputBorder.none,
        ),
        hint: Text(hint, style: const TextStyle(color: Colors.black54)),
        items: items
            .map((e) => DropdownMenuItem(
                  value: e,
                  child: Text(e, style: const TextStyle(color: Colors.black)),
                ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  // â”€â”€ BUILD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isVerified = user?.emailVerified ?? false;

    return Scaffold(
      backgroundColor: darkBlue,

      // â”€â”€ DRAWER â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      drawer: Drawer(
        child: Container(
          color: darkBlue,
          child: Column(
            children: [
              const DrawerHeader(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white10)),
                ),
                child: Center(
                  child: Text(
                    "SOS.LIVE",
                    style: TextStyle(
                        color: gold,
                        fontSize: 28,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              _buildDrawerItem(
                icon: Icons.policy_outlined,
                title: "PolÃ­ticas de la Empresa",
                onTap: () => Navigator.pop(context),
              ),
              _buildDrawerItem(
                icon: Icons.gavel_outlined,
                title: "TÃ©rminos y Condiciones",
                onTap: () => Navigator.pop(context),
              ),
              _buildDrawerItem(
                icon: Icons.help_outline,
                title: "Centro de Ayuda",
                onTap: () => Navigator.pop(context),
              ),
              _buildDrawerItem(
                icon: Icons.notifications_active_outlined,
                title: "Ajustes de Alerta",
                onTap: () {
                  Navigator.pop(context);
                  _handleAlertSettings();
                },
              ),
              _buildDrawerItem(
                icon: Icons.lock_reset,
                title: "Cambiar ContraseÃ±a",
                onTap: () {
                  Navigator.pop(context);
                  _handleChangePassword();
                },
              ),
              if (!isVerified)
                _buildDrawerItem(
                  icon: Icons.mark_email_unread_outlined,
                  title: "Verificar Email",
                  color: Colors.orangeAccent,
                  onTap: () {
                    Navigator.pop(context);
                    _handleVerifyEmail();
                  },
                ),
              const Spacer(),
              const Divider(color: Colors.white10),
              _buildDrawerItem(
                icon: Icons.delete_forever_outlined,
                title: "Eliminar Cuenta",
                color: Colors.red,
                onTap: () {
                  Navigator.pop(context);
                  _handleDeleteAccount();
                },
              ),
              _buildDrawerItem(
                icon: Icons.logout,
                title: "Cerrar SesiÃ³n",
                color: Colors.redAccent,
                onTap: _handleLogout,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),

      // â”€â”€ BODY â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: gold))
          : FadeTransition(
              opacity: _fadeAnim,
              child: Stack(
                children: [
                  // Fondo gris superior
                  Container(
                    width: double.infinity,
                    height: MediaQuery.of(context).size.height * 0.4,
                    color: lightGray,
                  ),

                  // Ola decorativa
                  Positioned.fill(
                    child: CustomPaint(
                      painter: ProfileWavePainter(
                        color: darkBlue,
                        waveHeight:
                            MediaQuery.of(context).size.height * 0.32,
                      ),
                    ),
                  ),

                  SafeArea(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: [
                          // BotÃ³n menÃº
                          Align(
                            alignment: Alignment.topLeft,
                            child: Builder(
                              builder: (context) => IconButton(
                                icon: const Icon(Icons.menu,
                                    size: 35, color: darkBlue),
                                onPressed: () =>
                                    Scaffold.of(context).openDrawer(),
                              ),
                            ),
                          ),

                          // Avatar con badge de verificaciÃ³n
                          Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              const CircleAvatar(
                                radius: 80,
                                backgroundColor: gold,
                                child: Icon(Icons.person,
                                    size: 100, color: lightGray),
                              ),
                              if (isVerified)
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.verified,
                                      color: Colors.white, size: 20),
                                ),
                            ],
                          ),

                          const SizedBox(height: 15),

                          // Nombre
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 6),

                          // Email + estado verificaciÃ³n
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.email_outlined,
                                  color: gold, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                email,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 14),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                isVerified
                                    ? Icons.check_circle
                                    : Icons.warning_amber_rounded,
                                color: isVerified
                                    ? Colors.green
                                    : Colors.orangeAccent,
                                size: 16,
                              ),
                            ],
                          ),

                          const SizedBox(height: 6),

                          // Tipo de sangre
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.redAccent, width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.bloodtype,
                                    color: Colors.redAccent, size: 16),
                                const SizedBox(width: 5),
                                Text(
                                  "Tipo de sangre: $bloodType",
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 30),

                          // Edad y Sexo
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildStatBox("Edad", age),
                              const SizedBox(width: 60),
                              _buildStatBox("Sexo", gender),
                            ],
                          ),

                          const SizedBox(height: 40),

                          // Opciones
                          _buildMenuOption(
                            Icons.edit,
                            "Editar Perfil",
                            onTap: _handleEditProfile,
                          ),
                          _buildMenuOption(
                            Icons.lock_reset,
                            "Cambiar ContraseÃ±a",
                            onTap: _handleChangePassword,
                          ),
                          _buildMenuOption(
                            Icons.play_circle_outline,
                            "SimulaciÃ³n SOS",
                            onTap: _handleSimulation,
                          ),
                          _buildMenuOption(
                            Icons.history,
                            "Historial",
                            onTap: _handleHistory,
                          ),
                          _buildMenuOption(
                            Icons.notifications_active_outlined,
                            "Ajustes de Alerta",
                            onTap: _handleAlertSettings,
                          ),
                          if (!isVerified)
                            _buildMenuOption(
                              Icons.mark_email_unread_outlined,
                              "Verificar Email",
                              onTap: _handleVerifyEmail,
                              iconColor: Colors.orangeAccent,
                            ),

                          const SizedBox(height: 50),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

      // â”€â”€ BOTTOM NAV â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        onTap: (index) {
          if (index == 0) return;
          const routes = ['', '/guardian', '/maps', '/chats', '/notices'];
          Navigator.pushReplacementNamed(context, routes[index]);
        },
        backgroundColor: darkBlue,
        selectedItemColor: gold,
        unselectedItemColor: Colors.white60,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.person), label: 'Perfil'),
          BottomNavigationBarItem(
              icon: Icon(Icons.shield), label: 'Guardian'),
          BottomNavigationBarItem(
              icon: Icon(Icons.map), label: 'Mapa'),
          BottomNavigationBarItem(
              icon: Icon(Icons.chat), label: 'Chats'),
          BottomNavigationBarItem(
              icon: Icon(Icons.notifications), label: 'Avisos'),
        ],
      ),
    );
  }

  // â”€â”€ WIDGETS AUXILIARES â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color, fontSize: 16)),
      onTap: onTap,
    );
  }

  Widget _buildStatBox(String label, String value) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 8),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuOption(
    IconData icon,
    String title, {
    required VoidCallback onTap,
    Color iconColor = darkBlue,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: iconColor, size: 30),
            ),
            const SizedBox(width: 20),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ WAVE PAINTER â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class ProfileWavePainter extends CustomPainter {
  final Color  color;
  final double waveHeight;

  ProfileWavePainter({required this.color, required this.waveHeight});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    path.moveTo(0, waveHeight);
    path.quadraticBezierTo(
        size.width * 0.25, waveHeight - 45, size.width * 0.5, waveHeight);
    path.quadraticBezierTo(
        size.width * 0.75, waveHeight + 45, size.width, waveHeight);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
