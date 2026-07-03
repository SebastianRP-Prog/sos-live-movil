import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class CompanyPlan {
  final String id;
  final String name;
  final String description;
  final double price;
  final String currency;
  final int planDays;

  const CompanyPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.currency,
    required this.planDays,
  });

  factory CompanyPlan.fromJson(Map<String, dynamic> json) {
    final nestedCompany = json['company'] is Map
        ? Map<String, dynamic>.from(json['company'] as Map)
        : json['empresaData'] is Map
            ? Map<String, dynamic>.from(json['empresaData'] as Map)
            : const <String, dynamic>{};
    return CompanyPlan(
      id: (json['id'] ??
              json['companyId'] ??
              json['empresaId'] ??
              json['uid'] ??
              '')
          .toString()
          .trim(),
      name: (json['name'] ??
              json['nombre'] ??
              json['displayName'] ??
              json['nombreEmpresa'] ??
              json['nombre_empresa'] ??
              json['nombreCompania'] ??
              json['nombre_compania'] ??
              json['razonSocial'] ??
              json['razon_social'] ??
              json['businessName'] ??
              json['organizationName'] ??
              json['companyName'] ??
              json['empresaNombre'] ??
              nestedCompany['name'] ??
              nestedCompany['nombre'] ??
              nestedCompany['razonSocial'] ??
              'Empresa')
          .toString()
          .trim(),
      description:
          (json['description'] ?? json['descripcion'] ?? '').toString().trim(),
      price: _number(json['price'] ?? json['precio']),
      currency: (json['currency'] ?? json['moneda'] ?? 'COP').toString(),
      planDays: _integer(json['planDays'] ?? json['diasPlan'], 30),
    );
  }

  static double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _integer(dynamic value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

class CompanyAccessStatus {
  final String? companyId;
  final String? companyName;
  final String status;
  final DateTime? expiresAt;

  const CompanyAccessStatus({
    required this.companyId,
    required this.companyName,
    required this.status,
    required this.expiresAt,
  });

  bool get isActive =>
      status == 'active' &&
      (expiresAt == null || expiresAt!.isAfter(DateTime.now()));

  factory CompanyAccessStatus.fromJson(Map<String, dynamic> json) {
    final rawExpiresAt = json['companyAccessExpiresAt'];
    final expiresAt = rawExpiresAt is Timestamp
        ? rawExpiresAt.toDate()
        : DateTime.tryParse(rawExpiresAt?.toString() ?? '');
    return CompanyAccessStatus(
      companyId: json['companyId']?.toString(),
      companyName: json['companyName']?.toString(),
      status: (json['companyAccessStatus'] ?? 'inactive').toString(),
      expiresAt: expiresAt,
    );
  }
}

class PaymentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<String> get _backendBaseUrls {
    const configuredUrl = String.fromEnvironment('API_BASE_URL');
    return <String>{
      if (configuredUrl.trim().isNotEmpty) configuredUrl.trim(),
      'https://backend-movil.web.app',
      'http://192.168.101.12:3000',
      'http://10.0.2.2:3000',
      'http://127.0.0.1:3000',
      'http://localhost:3000',
    }.toList(growable: false);
  }

  Future<List<CompanyPlan>> listCompanies() async {
    final companies = <String, CompanyPlan>{};
    Object? lastError;

    try {
      final decoded = await _request('GET', '/api/auth/companies');
      final rawCompanies = decoded['companies'];
      if (rawCompanies is List) {
        for (final rawCompany in rawCompanies) {
          if (rawCompany is Map) {
            _addCompany(
              companies,
              CompanyPlan.fromJson(Map<String, dynamic>.from(rawCompany)),
            );
          }
        }
      }
    } catch (error) {
      lastError = error;
    }

    if (companies.isEmpty) {
      try {
        await _loadCompanyCollections(companies);
      } catch (error) {
        lastError = error;
      }
    }

    final result = companies.values
        .where(
          (company) =>
              !_looksLikeFirebaseId(company.name) &&
              company.name != 'Empresa' &&
              !company.name.startsWith('Empresa registrada '),
        )
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (result.isEmpty && lastError is FirebaseException) {
      throw PaymentException(_firestorePermissionMessage(lastError));
    }
    return result;
  }

  Future<CompanyAccessStatus> companyStatus() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const PaymentException('Inicia sesion para pagar');
    }

    try {
      final decoded = await _request(
        'GET',
        '/api/auth/payments/company-status',
        authenticated: true,
      );
      return CompanyAccessStatus.fromJson(decoded);
    } catch (_) {}

    late final DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await _firestore.collection('users').doc(user.uid).get();
    } on FirebaseException catch (error) {
      throw PaymentException(_firestorePermissionMessage(error));
    }
    final status = CompanyAccessStatus.fromJson(doc.data() ?? const {});
    final companyId = status.companyId?.trim() ?? '';
    final currentName = status.companyName?.trim() ?? '';
    if (companyId.isEmpty ||
        (currentName.isNotEmpty && !_looksLikeFirebaseId(currentName))) {
      return status;
    }

    final resolvedName = await _findCompanyNameById(companyId);
    if (resolvedName == null) return status;

    try {
      await doc.reference.set({
        'companyName': resolvedName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}

    return CompanyAccessStatus(
      companyId: status.companyId,
      companyName: resolvedName,
      status: status.status,
      expiresAt: status.expiresAt,
    );
  }

  Future<String?> _findCompanyNameById(String companyId) async {
    try {
      final doc = await _firestore.collection('Empresas').doc(companyId).get();
      final data = doc.data();
      if (data != null) {
        final name = (data['nombre'] ?? '').toString().trim();
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}
    return null;
  }

  Future<Uri> createCheckout(String companyId) async {
    final decoded = await _request(
      'POST',
      '/api/auth/payments/company-preference',
      authenticated: true,
      body: {'companyId': companyId},
    );
    final rawUrl =
        (decoded['checkoutUrl'] ?? decoded['initPoint'] ?? '').toString();
    final url = Uri.tryParse(rawUrl);
    if (url == null || !url.hasScheme) {
      throw const PaymentException('Mercado Pago no devolvio un enlace valido');
    }
    return url;
  }

  Future<CompanyAccessStatus> simulateApprovedPayment(
    CompanyPlan company,
  ) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const PaymentException('Inicia sesion para simular el pago');
    }

    final now = DateTime.now();
    final expiresAt = now.add(Duration(days: company.planDays));
    final paymentRef = _firestore.collection('company_payments').doc();
    final userRef = _firestore.collection('users').doc(user.uid);

    await userRef.set({
      'companyId': company.id,
      'companyName': company.name,
      'companyAccessStatus': 'active',
      'companyAccessPaymentId': paymentRef.id,
      'companyPaidAt': Timestamp.fromDate(now),
      'companyAccessExpiresAt': Timestamp.fromDate(expiresAt),
      'paymentSimulation': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    try {
      await paymentRef.set({
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'companyId': company.id,
        'companyName': company.name,
        'amount': company.price,
        'currency': company.currency,
        'status': 'approved',
        'provider': 'simulation',
        'simulation': true,
        'createdAt': FieldValue.serverTimestamp(),
        'paidAt': Timestamp.fromDate(now),
      });
    } catch (_) {
      // The user association is the required result for local simulation.
    }

    return CompanyAccessStatus(
      companyId: company.id,
      companyName: company.name,
      status: 'active',
      expiresAt: expiresAt,
    );
  }

  Future<void> _loadCompanyCollections(
    Map<String, CompanyPlan> companies,
  ) async {
    final snap = await _firestore.collection('Empresas').limit(200).get();
    for (final doc in snap.docs) {
      final data = doc.data();
      final status = (data['estado'] ?? '').toString().trim().toLowerCase();
      if (status.isNotEmpty && status != 'aprobada' && status != 'aprobado') {
        continue;
      }
      final name = (data['nombre'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      _addCompany(
        companies,
        CompanyPlan.fromJson({
          'id': doc.id,
          ...data,
          'name': name,
          'description': data['descripcion'] ?? data['plan'] ?? '',
        }),
      );
    }
  }

  Future<void> _resolveCompanyIds(
    Map<String, CompanyPlan> companies,
  ) async {
    const collectionNames = [
      'companies',
      'empresas',
      'Empresas',
      'dashboard_companies',
      'businesses',
      'organizations',
      'organizaciones',
      'dashboard_users',
      'company_users',
      'users',
    ];

    for (final entry in companies.entries.toList()) {
      if (!_looksLikeFirebaseId(entry.value.name)) continue;
      for (final collectionName in collectionNames) {
        try {
          final doc =
              await _firestore.collection(collectionName).doc(entry.key).get();
          if (!doc.exists) continue;
          final resolved = CompanyPlan.fromJson({
            'id': entry.key,
            ...?doc.data(),
          });
          if (!_looksLikeFirebaseId(resolved.name) &&
              resolved.name != 'Empresa') {
            companies[entry.key] = resolved;
            break;
          }
        } catch (_) {}
      }
    }
  }

  Future<Map<String, Map<String, dynamic>>> _loadRegisteredCompanyUsers(
    Map<String, CompanyPlan> companies,
  ) async {
    final usersById = <String, Map<String, dynamic>>{};
    try {
      final snap = await _firestore.collection('users').limit(500).get();
      for (final doc in snap.docs) {
        final data = doc.data();
        usersById[doc.id] = data;
        if (!_isCompanyProfile(data)) continue;

        _addCompany(
          companies,
          CompanyPlan.fromJson({
            'id': doc.id,
            ...data,
            'description': data['description'] ??
                data['descripcion'] ??
                'Empresa registrada en SOS LIVE',
          }),
        );
      }
    } catch (_) {}
    return usersById;
  }

  Future<void> _loadCompaniesFromAgents(
    Map<String, CompanyPlan> companies,
    Map<String, Map<String, dynamic>> registeredUsers,
  ) async {
    for (final collectionName in ['dashboard_agents', 'Agentes']) {
      try {
        final snap =
            await _firestore.collection(collectionName).limit(300).get();
        for (final doc in snap.docs) {
          final data = doc.data();
          final companyId = (data['companyId'] ??
                  data['empresaId'] ??
                  data['companyUid'] ??
                  data['empresaUid'] ??
                  '')
              .toString()
              .trim();
          final companyName = (data['companyName'] ??
                  data['empresaNombre'] ??
                  data['empresa'] ??
                  data['nombreEmpresa'] ??
                  '')
              .toString()
              .trim();
          if (companyId.isEmpty && companyName.isEmpty) continue;

          final registeredCompany = registeredUsers[companyId];
          if (registeredCompany != null) {
            _addCompany(
              companies,
              CompanyPlan.fromJson({
                'id': companyId,
                ...registeredCompany,
                'description': registeredCompany['description'] ??
                    registeredCompany['descripcion'] ??
                    'Servicio de seguridad de la empresa',
              }),
            );
            continue;
          }

          _addCompany(
            companies,
            CompanyPlan.fromJson({
              'id': companyId.isNotEmpty
                  ? companyId
                  : _companyIdFromName(companyName),
              'name': companyName.isNotEmpty ? companyName : companyId,
              'description': 'Servicio de seguridad de la empresa',
              'price': data['companyPrice'] ?? data['precioEmpresa'] ?? 0,
              'planDays': data['companyPlanDays'] ?? 30,
            }),
          );
        }
      } catch (_) {}
    }
  }

  void _addCompany(
    Map<String, CompanyPlan> companies,
    CompanyPlan company,
  ) {
    if (company.id.isEmpty || company.name.isEmpty) return;
    final previous = companies[company.id];
    if (previous == null || _companyScore(company) > _companyScore(previous)) {
      companies[company.id] = company;
    }
  }

  bool _isCompanyProfile(Map<String, dynamic> data) {
    final role = (data['role'] ??
            data['type'] ??
            data['tipo'] ??
            data['userType'] ??
            data['accountType'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    const companyRoles = {
      'empresa',
      'company',
      'compania',
      'compañia',
      'corporativo',
    };
    if (companyRoles.contains(role)) return true;

    return [
      data['nombreEmpresa'],
      data['razonSocial'],
      data['businessName'],
    ].any((value) => value?.toString().trim().isNotEmpty == true);
  }

  int _companyScore(CompanyPlan company) {
    var score = 0;
    if (!_looksLikeFirebaseId(company.name) && company.name != 'Empresa') {
      score += 10;
    }
    if (company.description.isNotEmpty) score += 2;
    if (company.price > 0) score += 3;
    return score;
  }

  bool _looksLikeFirebaseId(String value) {
    final clean = value.trim();
    return clean.length >= 20 &&
        !clean.contains(' ') &&
        RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(clean);
  }

  String _companyIdFromName(String name) {
    return name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  String _firestorePermissionMessage(FirebaseException error) {
    if (error.code == 'permission-denied') {
      return 'Firestore denego la lectura. Publica las reglas incluidas con "firebase deploy --only firestore:rules" o inicia el backend para usar Firebase Admin.';
    }
    return error.message ?? error.toString();
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    bool authenticated = false,
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (authenticated) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw const PaymentException('Inicia sesion para pagar');
      }
      final token = await user.getIdToken();
      headers['Authorization'] = 'Bearer $token';
    }

    Object? lastError;
    for (final baseUrl in _backendBaseUrls) {
      try {
        final uri = Uri.parse('$baseUrl$path');
        final response = method == 'POST'
            ? await http
                .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
                .timeout(timeout)
            : await http.get(uri, headers: headers).timeout(timeout);

        Map<String, dynamic> decoded = {};
        try {
          final value = jsonDecode(response.body);
          if (value is Map) decoded = Map<String, dynamic>.from(value);
        } catch (_) {}

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return decoded;
        }
        lastError = decoded['error'] ?? 'Error ${response.statusCode}';
      } catch (error) {
        lastError = error;
      }
    }

    throw PaymentException(
      lastError?.toString() ?? 'No se pudo conectar con el servidor',
    );
  }
}

class PaymentException implements Exception {
  final String message;

  const PaymentException(this.message);

  @override
  String toString() => message;
}
