import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────
//  Opciones de avatar predefinidas por SOS.LIVE
// ─────────────────────────────────────────────────────────
class _AvatarOption {
  final String id;
  final IconData icon;
  final Color bg;
  const _AvatarOption(this.id, this.icon, this.bg);
}

const List<_AvatarOption> _kAvatars = [
  // ── Personas ────────────────────────────────────────────
  _AvatarOption('person_blue', Icons.person_rounded, Color(0xFF1565C0)),
  _AvatarOption('person_gold', Icons.person_rounded, Color(0xFFD4AF37)),
  _AvatarOption('shield_green', Icons.shield_rounded, Color(0xFF2ECC71)),
  _AvatarOption('shield_red', Icons.shield_rounded, Color(0xFFE53935)),
  _AvatarOption('face_purple', Icons.face_rounded, Color(0xFF7B1FA2)),
  _AvatarOption('face_teal', Icons.face_rounded, Color(0xFF00897B)),
  _AvatarOption('star_orange', Icons.star_rounded, Color(0xFFF57C00)),
  _AvatarOption('bolt_red', Icons.bolt_rounded, Color(0xFFD32F2F)),

  // ── Animales ─────────────────────────────────────────────
  _AvatarOption('pet_brown', Icons.pets_rounded, Color(0xFF6D4C41)),
  _AvatarOption('cat_pink', Icons.catching_pokemon, Color(0xFFEC407A)),
  _AvatarOption('rabbit_lavender', Icons.cruelty_free, Color(0xFF9575CD)),
  _AvatarOption('bird_sky', Icons.air, Color(0xFF29B6F6)),
  _AvatarOption(
      'butterfly_pink', Icons.filter_vintage_rounded, Color(0xFFE91E63)),
  _AvatarOption('bug_green', Icons.bug_report_rounded, Color(0xFF43A047)),
  _AvatarOption('fish_blue', Icons.water, Color(0xFF0288D1)),
  _AvatarOption('horse_brown', Icons.agriculture_rounded, Color(0xFF8D6E63)),

  // ── Naturaleza y cosas bonitas ────────────────────────────
  _AvatarOption('nature_green', Icons.eco_rounded, Color(0xFF388E3C)),
  _AvatarOption('flower_red', Icons.local_florist_rounded, Color(0xFFD32F2F)),
  _AvatarOption('sun_yellow', Icons.wb_sunny_rounded, Color(0xFFFFB300)),
  _AvatarOption('moon_indigo', Icons.nightlight_round, Color(0xFF3949AB)),
  _AvatarOption('snowflake_cyan', Icons.ac_unit_rounded, Color(0xFF00BCD4)),
  _AvatarOption(
      'fire_deep', Icons.local_fire_department_rounded, Color(0xFFBF360C)),
  _AvatarOption('leaf_lime', Icons.spa_rounded, Color(0xFF7CB342)),
  _AvatarOption('diamond_blue', Icons.diamond_rounded, Color(0xFF1976D2)),

  // ── Hobbies y deportes ────────────────────────────────────
  _AvatarOption('sports_blue', Icons.sports_soccer_rounded, Color(0xFF0288D1)),
  _AvatarOption(
      'basketball_orng', Icons.sports_basketball_rounded, Color(0xFFE65100)),
  _AvatarOption('music_pink', Icons.music_note_rounded, Color(0xFFC2185B)),
  _AvatarOption('headphones_deep', Icons.headphones_rounded, Color(0xFF4527A0)),
  _AvatarOption('camera_gray', Icons.camera_alt_rounded, Color(0xFF546E7A)),
  _AvatarOption('book_teal', Icons.menu_book_rounded, Color(0xFF00695C)),
  _AvatarOption(
      'rocket_purple', Icons.rocket_launch_rounded, Color(0xFF6A1B9A)),
  _AvatarOption('game_cyan', Icons.sports_esports_rounded, Color(0xFF00838F)),

  // ── Especiales SOS ───────────────────────────────────────
  _AvatarOption('sos_red', Icons.sos_rounded, Color(0xFFC62828)),
  _AvatarOption('heart_red', Icons.favorite_rounded, Color(0xFFE53935)),
  _AvatarOption(
      'crown_gold', Icons.workspace_premium_rounded, Color(0xFFF9A825)),
  _AvatarOption('ghost_purple', Icons.hive_rounded, Color(0xFF5E35B1)),
];

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  static const Color darkBlue = Color(0xFF002133);
  static const Color gold = Color(0xFFD4AF37);
  static const Color lightGray = Color(0xFFD9D9D9);

  String name = '';
  String email = '';
  String age = '';
  String gender = '';
  String bloodType = '';
  String avatarId = 'person_blue';
  bool isLoading = true;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

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

  Future<void> _loadUserData() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() => isLoading = false);
        return;
      }
      final user = FirebaseAuth.instance.currentUser;
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final doc = await userRef.get();
      Map<String, dynamic> data = doc.data() ?? {};

      if (!doc.exists) {
        data = {
          'name': user?.displayName ?? 'Usuario',
          'email': user?.email ?? '',
          'age': null,
          'gender': null,
          'bloodType': null,
          'avatarId': 'person_blue',
          'role': 'persona',
          'type': 'persona',
          'guardians': <String>[],
          'createdAt': FieldValue.serverTimestamp(),
        };
        await userRef.set(data, SetOptions(merge: true));
      }

      setState(() {
        name = data['name'] ?? data['nombre'] ?? 'Usuario';
        email = data['email'] ?? user?.email ?? '';
        age = data['age']?.toString() ?? data['edad']?.toString() ?? '--';
        gender = data['gender'] ?? data['sexo'] ?? '--';
        bloodType = data['bloodType'] ?? data['tipoSangre'] ?? '--';
        avatarId = data['avatarId'] ?? 'person_blue';
        isLoading = false;
      });
      _animController.forward();
    } catch (e) {
      setState(() {
        email = FirebaseAuth.instance.currentUser?.email ?? '';
        name = 'Usuario';
        isLoading = false;
      });
      _animController.forward();
      _showSnack('Error de conexión: ¿El servidor está activo?');
    }
  }

  _AvatarOption _getAvatar(String id) {
    return _kAvatars.firstWhere(
      (a) => a.id == id,
      orElse: () => _kAvatars.first,
    );
  }

  // ── Selector de avatar ───────────────────────────────────
  Future<void> _handleChangeAvatar() async {
    String tempId = avatarId;

    // Categorías para organizar avatares en el selector
    final categories = [
      ('Personas', _kAvatars.sublist(0, 8)),
      ('Animales', _kAvatars.sublist(8, 16)),
      ('Naturaleza', _kAvatars.sublist(16, 24)),
      ('Hobbies', _kAvatars.sublist(24, 32)),
      ('Especiales', _kAvatars.sublist(32)),
    ];

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          backgroundColor: const Color(0xFF002B36),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: gold, width: 1.5),
          ),
          title: const Text(
            'Elige tu avatar',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: categories.map((cat) {
                  final (catName, opts) = cat;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          catName,
                          style: const TextStyle(
                            color: gold,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: opts.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                        ),
                        itemBuilder: (_, i) {
                          final opt = opts[i];
                          final isActive = tempId == opt.id;
                          return GestureDetector(
                            onTap: () => setS(() => tempId = opt.id),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: opt.bg,
                                border: Border.all(
                                  color: isActive ? gold : Colors.transparent,
                                  width: 3,
                                ),
                                boxShadow: isActive
                                    ? [
                                        BoxShadow(
                                          color: gold.withOpacity(0.5),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        )
                                      ]
                                    : [],
                              ),
                              child: Icon(opt.icon,
                                  color: Colors.white,
                                  size: isActive ? 30 : 26),
                            ),
                          );
                        },
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancelar',
                  style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: gold,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(ctx, tempId),
              child: const Text('Guardar',
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (selected == null || selected == avatarId) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'avatarId': selected});
      setState(() => avatarId = selected);
      _showSnack('Avatar actualizado');
    } catch (_) {
      _showSnack('Error al guardar el avatar');
    }
  }

  // ── Logout ───────────────────────────────────────────────
  Future<void> _handleLogout() async {
    final confirmed = await _showConfirmDialog(
      title: 'Cerrar Sesión',
      message: '¿Estás seguro de que deseas cerrar sesión?',
      confirmLabel: 'Salir',
      confirmColor: Colors.redAccent,
    );
    if (!confirmed) return;
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  // ── Editar perfil con validaciones ───────────────────────
  Future<void> _handleEditProfile() async {
    final nameCtrl = TextEditingController(text: name);
    final ageCtrl = TextEditingController(text: age == '--' ? '' : age);
    String? newGender = gender == '--' ? null : gender;
    String? newBlood = bloodType == '--' ? null : bloodType;

    // Para mostrar errores dentro del dialog
    String? nameError;
    String? ageError;
    String? genderError;
    String? bloodError;

    const genderOpts = ['Masculino', 'Femenino', 'Otro'];
    const bloodOpts = ['O+', 'O-', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-'];

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) {
          // Función de validación interna del diálogo
          bool _validate() {
            bool ok = true;
            nameError = null;
            ageError = null;
            genderError = null;
            bloodError = null;

            final trimmedName = nameCtrl.text.trim();
            final trimmedAge = ageCtrl.text.trim();

            if (trimmedName.isEmpty) {
              nameError = 'El nombre es obligatorio';
              ok = false;
            } else if (trimmedName.length < 3) {
              nameError = 'Ingresa un nombre válido';
              ok = false;
            }
            if (trimmedAge.isEmpty) {
              ageError = 'La edad es obligatoria';
              ok = false;
            } else {
              final parsed = int.tryParse(trimmedAge);
              if (parsed == null || parsed <= 0 || parsed > 120) {
                ageError = 'Ingresa una edad válida (1-120)';
                ok = false;
              }
            }
            if (newGender == null) {
              genderError = 'Selecciona tu sexo';
              ok = false;
            }
            if (newBlood == null) {
              bloodError = 'Selecciona tu tipo de sangre';
              ok = false;
            }

            setS(() {});
            return ok;
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF002B36),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: gold, width: 1.5),
            ),
            title: const Text('Editar Perfil',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Campo Nombre
                  _dialogField(
                    nameCtrl,
                    Icons.person,
                    'Nombre Completo',
                    errorText: nameError,
                    onChanged: (_) => setS(() => nameError = null),
                  ),
                  const SizedBox(height: 12),

                  // Campo Edad
                  _dialogField(
                    ageCtrl,
                    Icons.cake,
                    'Edad',
                    inputType: TextInputType.number,
                    errorText: ageError,
                    onChanged: (_) => setS(() => ageError = null),
                  ),
                  const SizedBox(height: 12),

                  // Dropdown Sexo
                  _dialogDropdown(
                    icon: Icons.wc,
                    hint: 'Sexo *',
                    items: genderOpts,
                    value: newGender,
                    errorText: genderError,
                    onChanged: (v) => setS(() {
                      newGender = v;
                      genderError = null;
                    }),
                  ),
                  const SizedBox(height: 12),

                  // Dropdown Tipo de sangre
                  _dialogDropdown(
                    icon: Icons.bloodtype,
                    hint: 'Tipo de sangre *',
                    items: bloodOpts,
                    value: newBlood,
                    errorText: bloodError,
                    onChanged: (v) => setS(() {
                      newBlood = v;
                      bloodError = null;
                    }),
                  ),

                  const SizedBox(height: 8),
                  Text(
                    '* Todos los campos son obligatorios',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.4), fontSize: 11),
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
                onPressed: () {
                  if (_validate()) Navigator.pop(ctx, true);
                },
                child: const Text('Guardar',
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (saved != true) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final trimmedName = nameCtrl.text.trim();
    final trimmedAge = ageCtrl.text.trim();
    final edad = int.tryParse(trimmedAge);
    if (uid == null) return;

    if (trimmedName.isEmpty ||
        trimmedName.length < 3 ||
        trimmedAge.isEmpty ||
        edad == null ||
        edad <= 0 ||
        edad > 120 ||
        newGender == null ||
        newBlood == null) {
      _showSnack('Completa todos los campos antes de guardar');
      return;
    }

    setState(() => isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'name': trimmedName,
        'email': FirebaseAuth.instance.currentUser?.email,
        'age': edad,
        'gender': newGender,
        'bloodType': newBlood,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _showSnack('Perfil actualizado correctamente');
      await _loadUserData();
    } catch (e) {
      _showSnack('Error de conexión al actualizar');
      setState(() => isLoading = false);
    }
  }

  // ── Cambiar contraseña ───────────────────────────────────
  Future<void> _handleChangePassword() async {
    final confirmed = await _showConfirmDialog(
      title: 'Cambiar Contraseña',
      message:
          'Te enviaremos un correo a\n$email\npara restablecer tu contraseña.',
      confirmLabel: 'Enviar correo',
      confirmColor: gold,
    );
    if (!confirmed) return;

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showSnack('Correo de restablecimiento enviado a $email');
    } catch (e) {
      _showSnack('Error al enviar el correo: $e');
    }
  }

  void _handleHistory() => Navigator.pushNamed(context, '/historial');
  void _handleSimulation() => Navigator.pushNamed(context, '/simulacion');

  Future<void> _handleVerifyEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (user.emailVerified) {
      _showSnack('Tu correo ya está verificado');
      return;
    }
    await user.sendEmailVerification();
    _showSnack('Correo de verificación enviado');
  }

  Future<void> _handleDeleteAccount() async {
    final confirmed = await _showConfirmDialog(
      title: 'Eliminar Cuenta',
      message:
          'Esta acción es IRREVERSIBLE.\nSe eliminarán todos tus datos.\n\n¿Deseas continuar?',
      confirmLabel: 'Eliminar',
      confirmColor: Colors.red,
    );
    if (!confirmed) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      await FirebaseAuth.instance.currentUser?.delete();
      if (mounted)
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } catch (e) {
      setState(() => isLoading = false);
      _showSnack('Error al eliminar la cuenta: $e');
    }
  }

  // ── Helpers UI ───────────────────────────────────────────
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
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    final formatters = inputType == TextInputType.number
        ? <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly]
        : <TextInputFormatter>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: errorText != null
                ? Colors.red.withOpacity(0.1)
                : Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
            border: errorText != null
                ? Border.all(color: Colors.redAccent, width: 1.5)
                : null,
          ),
          child: TextField(
            controller: ctrl,
            keyboardType: inputType,
            inputFormatters: formatters,
            onChanged: onChanged,
            style: const TextStyle(color: Colors.black),
            decoration: InputDecoration(
              prefixIcon: Icon(icon,
                  color: errorText != null ? Colors.redAccent : gold),
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.black54),
              border: InputBorder.none,
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Text(
              errorText,
              style: const TextStyle(color: Colors.redAccent, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _dialogDropdown({
    required IconData icon,
    required String hint,
    required List<String> items,
    required String? value,
    required Function(String?) onChanged,
    String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: errorText != null
                ? Colors.red.withOpacity(0.1)
                : Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
            border: errorText != null
                ? Border.all(color: Colors.redAccent, width: 1.5)
                : null,
          ),
          child: DropdownButtonFormField<String>(
            value: value,
            isExpanded: true,
            dropdownColor: Colors.white,
            decoration: InputDecoration(
              prefixIcon: Icon(icon,
                  color: errorText != null ? Colors.redAccent : gold),
              border: InputBorder.none,
            ),
            hint: Text(hint, style: const TextStyle(color: Colors.black54)),
            items: items
                .map((e) => DropdownMenuItem(
                      value: e,
                      child:
                          Text(e, style: const TextStyle(color: Colors.black)),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Text(
              errorText,
              style: const TextStyle(color: Colors.redAccent, fontSize: 11),
            ),
          ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isVerified = user?.emailVerified ?? false;
    final avatar = _getAvatar(avatarId);

    return Scaffold(
      backgroundColor: darkBlue,

      // ── DRAWER ───────────────────────────────────────────
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
                    'SOS.LIVE',
                    style: TextStyle(
                        color: gold, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              _buildDrawerItem(
                  icon: Icons.policy_outlined,
                  title: 'Políticas de la Empresa',
                  onTap: () => Navigator.pop(context)),
              _buildDrawerItem(
                  icon: Icons.gavel_outlined,
                  title: 'Términos y Condiciones',
                  onTap: () => Navigator.pop(context)),
              _buildDrawerItem(
                  icon: Icons.help_outline,
                  title: 'Centro de Ayuda',
                  onTap: () => Navigator.pop(context)),
              _buildDrawerItem(
                  icon: Icons.lock_reset,
                  title: 'Cambiar Contraseña',
                  onTap: () {
                    Navigator.pop(context);
                    _handleChangePassword();
                  }),
              if (!isVerified)
                _buildDrawerItem(
                  icon: Icons.mark_email_unread_outlined,
                  title: 'Verificar Email',
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
                title: 'Eliminar Cuenta',
                color: Colors.red,
                onTap: () {
                  Navigator.pop(context);
                  _handleDeleteAccount();
                },
              ),
              _buildDrawerItem(
                  icon: Icons.logout,
                  title: 'Cerrar Sesión',
                  color: Colors.redAccent,
                  onTap: _handleLogout),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),

      // ── BODY ─────────────────────────────────────────────
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: gold))
          : FadeTransition(
              opacity: _fadeAnim,
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    height: MediaQuery.of(context).size.height * 0.28,
                    color: lightGray,
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: ProfileWavePainter(
                        color: darkBlue,
                        waveHeight: MediaQuery.of(context).size.height * 0.32,
                      ),
                    ),
                  ),
                  SafeArea(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: [
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

                          // Avatar
                          Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Container(
                                width: 160,
                                height: 160,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: avatar.bg,
                                  border: Border.all(color: gold, width: 3),
                                  boxShadow: [
                                    BoxShadow(
                                        color: avatar.bg.withOpacity(0.4),
                                        blurRadius: 20,
                                        spreadRadius: 4),
                                  ],
                                ),
                                child: Icon(avatar.icon,
                                    size: 90, color: Colors.white),
                              ),
                              if (isVerified)
                                Positioned(
                                  bottom: 12,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle),
                                    child: const Icon(Icons.verified,
                                        color: Colors.white, size: 18),
                                  ),
                                ),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                child: GestureDetector(
                                  onTap: _handleChangeAvatar,
                                  child: Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: gold,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: lightGray, width: 2),
                                    ),
                                    child: const Icon(Icons.color_lens_rounded,
                                        color: Colors.black, size: 18),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 15),
                          Text(name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.email_outlined,
                                  color: gold, size: 16),
                              const SizedBox(width: 6),
                              Text(email,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 14)),
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
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                              border:
                                  Border.all(color: Colors.redAccent, width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.bloodtype,
                                    color: Colors.redAccent, size: 16),
                                const SizedBox(width: 5),
                                Text('Tipo de sangre: $bloodType',
                                    style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),

                          const SizedBox(height: 30),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildStatBox('Edad', age),
                              const SizedBox(width: 60),
                              _buildStatBox('Sexo', gender),
                            ],
                          ),

                          const SizedBox(height: 40),
                          _buildMenuOption(Icons.edit, 'Editar Perfil',
                              onTap: _handleEditProfile),
                          _buildMenuOption(
                              Icons.color_lens_rounded, 'Cambiar Avatar',
                              onTap: _handleChangeAvatar),
                          _buildMenuOption(
                              Icons.lock_reset, 'Cambiar Contraseña',
                              onTap: _handleChangePassword),
                          _buildMenuOption(
                              Icons.payments_outlined, 'Pagar Empresa',
                              onTap: () => Navigator.pushNamed(
                                  context, '/company-payment')),
                          _buildMenuOption(
                              Icons.play_circle_outline, 'Simulación SOS',
                              onTap: _handleSimulation),
                          _buildMenuOption(Icons.history, 'Historial',
                              onTap: _handleHistory),
                          if (!isVerified)
                            _buildMenuOption(Icons.mark_email_unread_outlined,
                                'Verificar Email',
                                onTap: _handleVerifyEmail,
                                iconColor: Colors.orangeAccent),

                          const SizedBox(height: 50),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

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
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
          BottomNavigationBarItem(icon: Icon(Icons.shield), label: 'Guardian'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Mapa'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chats'),
          BottomNavigationBarItem(
              icon: Icon(Icons.notifications), label: 'Avisos'),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  WIDGETS AUXILIARES
  // ════════════════════════════════════════════════════════
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
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
                  borderRadius: BorderRadius.circular(15)),
              child: Icon(icon, color: iconColor, size: 30),
            ),
            const SizedBox(width: 20),
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// ── WAVE PAINTER ─────────────────────────────────────────
class ProfileWavePainter extends CustomPainter {
  final Color color;
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
