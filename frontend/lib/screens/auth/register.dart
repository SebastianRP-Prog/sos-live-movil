import 'package:flutter/material.dart';

import '../../services/auth_services.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const Color darkBlue = Color(0xFF002B36);
  static const Color snackBlue = Color(0xFF1A3A45);
  static const Color gold = Color(0xFFD4AF37);

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final ageController = TextEditingController();
  final AuthService _authService = AuthService();

  final List<String> sexoOpciones = ['Masculino', 'Femenino', 'Otro'];
  final List<String> sangreOpciones = [
    'O+',
    'O-',
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
  ];

  String? sexoSeleccionado;
  String? sangreSeleccionada;
  bool obscurePassword = true;
  bool isLoading = false;

  Future<void> handleRegister() async {
    if (nameController.text.trim().isEmpty ||
        emailController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty ||
        ageController.text.trim().isEmpty ||
        sexoSeleccionado == null ||
        sangreSeleccionada == null) {
      showSnack('Por favor, completa todos los campos');
      return;
    }

    if (!emailController.text.contains('@') ||
        !emailController.text.contains('.')) {
      showSnack('Ingresa un correo válido');
      return;
    }

    if (passwordController.text.trim().length < 6) {
      showSnack('La contraseña debe tener al menos 6 caracteres');
      return;
    }

    final edad = int.tryParse(ageController.text.trim());
    if (edad == null || edad <= 0 || edad > 120) {
      showSnack('Ingresa una edad válida');
      return;
    }

    setState(() => isLoading = true);

    final error = await _authService.register(
      email: emailController.text,
      password: passwordController.text.trim(),
      name: nameController.text,
      age: edad,
      gender: sexoSeleccionado,
      bloodType: sangreSeleccionada,
    );

    if (!mounted) return;

    if (error != null) {
      showSnack(error);
      setState(() => isLoading = false);
      return;
    }

    setState(() => isLoading = false);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: darkBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: gold, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.mark_email_read, color: gold),
            SizedBox(width: 10),
            Text(
              'Cuenta creada',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'Te enviamos un correo de verificación.\n\n'
          'Revisa tu bandeja de entrada y verifica '
          'tu cuenta antes de iniciar sesión.',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: gold,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text(
              'Ir al Login',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        duration: const Duration(seconds: 4),
        backgroundColor: snackBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    ageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBlue,
      appBar: AppBar(
        backgroundColor: darkBlue,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Volver al Login',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
              child: Column(
                children: [
                  const Text(
                    'Cree Su\nCuenta',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Recibirás un correo de verificación',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 30),
                  buildField(Icons.person, 'Nombre Completo', nameController),
                  buildField(
                    Icons.email,
                    'Email',
                    emailController,
                    inputType: TextInputType.emailAddress,
                  ),
                  buildPassword(),
                  buildField(
                    Icons.cake,
                    'Edad',
                    ageController,
                    inputType: TextInputType.number,
                  ),
                  buildDropdown(
                    Icons.wc,
                    'Sexo',
                    sexoOpciones,
                    sexoSeleccionado,
                    (v) => setState(() => sexoSeleccionado = v),
                  ),
                  buildDropdown(
                    Icons.bloodtype,
                    'Tipo de sangre',
                    sangreOpciones,
                    sangreSeleccionada,
                    (v) => setState(() => sangreSeleccionada = v),
                  ),
                  const SizedBox(height: 30),
                  isLoading
                      ? const CircularProgressIndicator(color: gold)
                      : ElevatedButton(
                          onPressed: handleRegister,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: gold,
                            minimumSize: const Size(double.infinity, 55),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Registrarse',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text(
                      '¿Ya tienes cuenta? Inicia Sesión',
                      style: TextStyle(
                        color: gold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildField(
    IconData icon,
    String hint,
    TextEditingController controller, {
    TextInputType inputType = TextInputType.text,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        keyboardType: inputType,
        style: const TextStyle(
          color: Color(0xFF101820),
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: gold),
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF4B5563)),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget buildPassword() {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: passwordController,
        obscureText: obscurePassword,
        style: const TextStyle(
          color: Color(0xFF101820),
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.lock, color: gold),
          hintText: 'Contraseña (mínimo 6 caracteres)',
          hintStyle: const TextStyle(color: Color(0xFF4B5563)),
          border: InputBorder.none,
          suffixIcon: IconButton(
            icon: Icon(
              obscurePassword ? Icons.visibility_off : Icons.visibility,
              color: const Color(0xFF374151),
            ),
            onPressed: () => setState(() => obscurePassword = !obscurePassword),
          ),
        ),
      ),
    );
  }

  Widget buildDropdown(
    IconData icon,
    String hint,
    List<String> items,
    String? value,
    Function(String?) onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        dropdownColor: Colors.white,
        style: const TextStyle(
          color: Color(0xFF101820),
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: gold),
          border: InputBorder.none,
        ),
        hint: Text(hint, style: const TextStyle(color: Color(0xFF4B5563))),
        items: items
            .map(
              (e) => DropdownMenuItem(
                value: e,
                child: Text(e),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}
