import 'package:rainbow_app/core/models/app_user.dart';

class MockDataGenerator {
  static AppUser createMockCitizen() {
    return const AppUser(
      uid: 'mock-citizen-001',
      email: 'citizen-mock@rainbow.gov.ng',
      displayName: 'Test Citizen',
      geoLgas: ['JOS SOUTH'],
      geoWards: ['BUKURU WARD'],
    );
  }

  static AppUser createMockPuResponder() {
    return const AppUser(
      uid: 'mock-pu-001',
      email: 'pu-001@operationrainbow.plateau.gov.ng',
      displayName: 'Officer PU-001',
      role: 'UNIT_COMMAND',
      geoLgas: ['JOS SOUTH'],
      geoWards: ['BUKURU WARD'],
    );
  }

  static AppUser createMockWardCommander() {
    return const AppUser(
      uid: 'mock-ward-001',
      email: 'ward-001@operationrainbow.plateau.gov.ng',
      displayName: 'Commander WARD-001',
      role: 'WARD_COMMAND',
      geoLgas: ['JOS SOUTH'],
      geoWards: ['BUKURU WARD'],
    );
  }
}
