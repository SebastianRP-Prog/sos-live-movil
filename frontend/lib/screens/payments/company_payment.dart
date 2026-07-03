import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs.dart';

import '../../services/payment_service.dart';

class CompanyPaymentScreen extends StatefulWidget {
  const CompanyPaymentScreen({super.key});

  @override
  State<CompanyPaymentScreen> createState() => _CompanyPaymentScreenState();
}

class _CompanyPaymentScreenState extends State<CompanyPaymentScreen>
    with WidgetsBindingObserver {
  static const Color darkBlue = Color(0xFF002133);
  static const Color gold = Color(0xFFD4AF37);

  final PaymentService _paymentService = PaymentService();
  List<CompanyPlan> _companies = const [];
  CompanyAccessStatus? _access;
  bool _loading = true;
  String? _payingCompanyId;
  String? _error;
  bool _checkoutOpened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _checkoutOpened) {
      _refreshStatus();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _paymentService.listCompanies(),
        _paymentService.companyStatus(),
      ]);
      if (!mounted) return;
      final companies = results[0] as List<CompanyPlan>;
      final access = _resolveCompanyName(
        results[1] as CompanyAccessStatus,
        companies,
      );
      setState(() {
        _companies = companies;
        _access = access;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshStatus() async {
    try {
      final rawStatus = await _paymentService.companyStatus();
      if (!mounted) return;
      final status = _resolveCompanyName(rawStatus, _companies);
      setState(() => _access = status);
      if (status.isActive) {
        _showMessage(
          'Pago aprobado. ${status.companyName ?? 'Tu empresa'} ya esta activa.',
        );
      } else if (_checkoutOpened) {
        _showMessage('El pago sigue pendiente. Actualiza en unos segundos.');
      }
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<void> _pay(CompanyPlan company) async {
    setState(() {
      _payingCompanyId = company.id;
      _error = null;
    });
    try {
      final checkoutUrl = await _paymentService.createCheckout(company.id);
      _checkoutOpened = true;
      await launchUrl(
        checkoutUrl,
        customTabsOptions: CustomTabsOptions(
          colorSchemes: CustomTabsColorSchemes.defaults(
            toolbarColor: darkBlue,
          ),
          showTitle: true,
          urlBarHidingEnabled: true,
          closeButton: CustomTabsCloseButton(
            icon: CustomTabsCloseButtonIcons.back,
          ),
        ),
      );
      await _refreshStatus();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _payingCompanyId = null);
    }
  }

  Future<void> _simulatePayment(CompanyPlan company) async {
    final cardHolderController = TextEditingController();
    final cardNumberController = TextEditingController();
    final expiryController = TextEditingController();
    final cvvController = TextEditingController();
    final documentController = TextEditingController();
    String? validationError;

    String? validateForm() {
      final cardDigits =
          cardNumberController.text.replaceAll(RegExp(r'\D'), '');
      final documentDigits =
          documentController.text.replaceAll(RegExp(r'\D'), '');
      final cvvDigits = cvvController.text.replaceAll(RegExp(r'\D'), '');
      final expiry = expiryController.text.trim();

      if (cardHolderController.text.trim().length < 3) {
        return 'Ingresa el nombre del titular ficticio.';
      }
      if (documentDigits.length < 6) {
        return 'Ingresa un documento ficticio de minimo 6 digitos.';
      }
      if (cardDigits.length < 12 || cardDigits.length > 19) {
        return 'Ingresa una tarjeta ficticia de 12 a 19 digitos.';
      }
      if (!RegExp(r'^\d{2}/?\d{2}$').hasMatch(expiry)) {
        return 'Ingresa el vencimiento ficticio en formato MM/AA.';
      }
      if (cvvDigits.length < 3 || cvvDigits.length > 4) {
        return 'Ingresa un CVV ficticio de 3 o 4 digitos.';
      }
      return null;
    }

    void revalidateIfNeeded(StateSetter setDialogState) {
      if (validationError == null) return;
      setDialogState(() => validationError = validateForm());
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Simulacion de pago'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Usa datos ficticios. No se realiza ningun cobro y no guardamos tarjeta ni CVV.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: cardHolderController,
                  decoration:
                      const InputDecoration(labelText: 'Nombre del titular'),
                  onChanged: (_) => revalidateIfNeeded(setDialogState),
                ),
                TextField(
                  controller: documentController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration:
                      const InputDecoration(labelText: 'Documento ficticio'),
                  onChanged: (_) => revalidateIfNeeded(setDialogState),
                ),
                TextField(
                  controller: cardNumberController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 19,
                  decoration: const InputDecoration(
                    labelText: 'Tarjeta ficticia',
                    hintText: '4509953566233704',
                  ),
                  onChanged: (_) => revalidateIfNeeded(setDialogState),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: expiryController,
                        keyboardType: TextInputType.datetime,
                        decoration:
                            const InputDecoration(labelText: 'Vence MM/AA'),
                        onChanged: (_) => revalidateIfNeeded(setDialogState),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: cvvController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        obscureText: true,
                        maxLength: 4,
                        decoration:
                            const InputDecoration(labelText: 'CVV ficticio'),
                        onChanged: (_) => revalidateIfNeeded(setDialogState),
                      ),
                    ),
                  ],
                ),
                if (validationError != null)
                  Text(
                    validationError!,
                    style: const TextStyle(color: Colors.red),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final error = validateForm();
                if (error != null) {
                  setDialogState(() => validationError = error);
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Simular aprobacion'),
            ),
          ],
        ),
      ),
    );
    cardHolderController.dispose();
    cardNumberController.dispose();
    expiryController.dispose();
    cvvController.dispose();
    documentController.dispose();
    if (confirmed != true) return;

    setState(() {
      _payingCompanyId = company.id;
      _error = null;
    });
    try {
      final status = await _paymentService.simulateApprovedPayment(company);
      if (!mounted) return;
      setState(() => _access = status);
      _showMessage(
        'Pago simulado aprobado. Las alertas iran a ${company.name}.',
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _payingCompanyId = null);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF1A3A45),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _money(CompanyPlan company) {
    final amount = company.price.toStringAsFixed(
      company.price == company.price.roundToDouble() ? 0 : 2,
    );
    return '${company.currency} $amount';
  }

  CompanyAccessStatus _resolveCompanyName(
    CompanyAccessStatus access,
    List<CompanyPlan> companies,
  ) {
    for (final company in companies) {
      if (company.id == access.companyId) {
        return CompanyAccessStatus(
          companyId: access.companyId,
          companyName: company.name,
          status: access.status,
          expiresAt: access.expiresAt,
        );
      }
    }
    return CompanyAccessStatus(
      companyId: access.companyId,
      companyName: null,
      status: access.status,
      expiresAt: access.expiresAt,
    );
  }

  bool get _hasRegisteredActiveCompany =>
      _access?.isActive == true && _activeCompany != null;

  CompanyPlan? get _activeCompany {
    final companyId = _access?.companyId;
    if (companyId == null || companyId.isEmpty) return null;
    for (final company in _companies) {
      if (company.id == companyId) return company;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBlue,
      appBar: AppBar(
        backgroundColor: darkBlue,
        foregroundColor: Colors.white,
        title: const Text('Pago a empresa'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: gold))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _statusCard(),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                  if (_hasRegisteredActiveCompany) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Empresa contratada',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _activeCompanyCard(),
                  ] else ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Selecciona la empresa',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Elige una empresa. Puedes simular el pago o usar Mercado Pago cuando la API publica este configurada.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    if (_companies.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'No se encontraron empresas con nombre publico. Agrega nombreEmpresa o razonSocial en Firestore, o inicia el backend Firebase Admin para leer displayName de Authentication.',
                          ),
                        ),
                      )
                    else
                      ..._companies.map(_companyCard),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _statusCard() {
    final active = _hasRegisteredActiveCompany;
    final expiresAt = _access?.expiresAt;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: active
            ? Colors.green.withOpacity(0.15)
            : Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: active ? Colors.green : Colors.white24),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.verified_rounded : Icons.lock_clock_outlined,
            color: active ? Colors.greenAccent : gold,
            size: 34,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active
                      ? 'Acceso activo: ${_access?.companyName ?? 'Empresa'}'
                      : 'Sin empresa activa',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (active && expiresAt != null)
                  Text(
                    'Vence: ${expiresAt.toLocal().toString().split(' ').first}',
                    style: const TextStyle(color: Colors.white70),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _activeCompanyCard() {
    final company = _activeCompany;
    final companyName = (_access?.companyName?.trim().isNotEmpty ?? false)
        ? _access!.companyName!.trim()
        : company?.name ?? 'Empresa contratada';

    return Card(
      color: const Color(0xFF083245),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: Color(0x2632CD32),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.business_rounded,
                color: Colors.greenAccent,
                size: 30,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    companyName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (company?.description.isNotEmpty ?? false) ...[
                    const SizedBox(height: 5),
                    Text(
                      company!.description,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                  const SizedBox(height: 6),
                  const Text(
                    'Plan activo',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _companyCard(CompanyPlan company) {
    final paying = _payingCompanyId == company.id;
    final alreadyActive =
        _access?.isActive == true && _access?.companyId == company.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      color: const Color(0xFF083245),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              company.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (company.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                company.description,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
            const SizedBox(height: 12),
            if (company.price > 0)
              Text(
                '${_money(company)} por ${company.planDays} dias',
                style: const TextStyle(
                  color: gold,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              )
            else
              Text(
                'Precio pendiente - simulacion disponible',
                style: TextStyle(
                  color: Colors.orange.shade200,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: paying || alreadyActive
                    ? null
                    : () => _simulatePayment(company),
                style: ElevatedButton.styleFrom(
                  backgroundColor: gold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                icon: paying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.science_outlined),
                label: Text(
                  alreadyActive
                      ? 'Plan activo'
                      : paying
                          ? 'Procesando'
                          : 'Simular pago aprobado',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            if (!alreadyActive) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: paying
                      ? null
                      : () {
                          if (company.price <= 0) {
                            _showMessage(
                              'La empresa debe configurar un precio para usar Mercado Pago.',
                            );
                            return;
                          }
                          _pay(company);
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Pagar con Mercado Pago'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
