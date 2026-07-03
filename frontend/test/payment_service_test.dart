import 'package:flutter_test/flutter_test.dart';
import 'package:sos_live/services/payment_service.dart';

void main() {
  test('CompanyPlan accepts Spanish company fields', () {
    final company = CompanyPlan.fromJson({
      'empresaId': 'empresa-uno',
      'nombre': 'Empresa Uno',
      'descripcion': 'Seguridad privada',
      'precio': '50000',
      'diasPlan': 30,
    });

    expect(company.id, 'empresa-uno');
    expect(company.name, 'Empresa Uno');
    expect(company.price, 50000);
    expect(company.planDays, 30);
  });

  test('CompanyPlan keeps registered companies without a configured price', () {
    final company = CompanyPlan.fromJson({
      'companyId': 'empresa-dos',
      'companyName': 'Empresa Dos',
    });

    expect(company.id, 'empresa-dos');
    expect(company.name, 'Empresa Dos');
    expect(company.price, 0);
  });

  test('CompanyPlan reads common registered company name fields', () {
    final company = CompanyPlan.fromJson({
      'id': 'firebase-company-id',
      'razonSocial': 'Seguridad Central SAS',
    });

    expect(company.name, 'Seguridad Central SAS');
  });

  test('CompanyPlan reads nested company data', () {
    final company = CompanyPlan.fromJson({
      'id': 'firebase-company-id',
      'company': {'nombre': 'Proteccion del Norte'},
    });

    expect(company.name, 'Proteccion del Norte');
  });
}
