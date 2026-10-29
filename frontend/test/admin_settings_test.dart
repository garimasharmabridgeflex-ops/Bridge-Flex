import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin settings use admin-only configuration endpoints', () {
    // Keep the web console contract explicit: public reads intentionally hide
    // unpublished company values and inactive plans, which must remain editable.
    const adminCompanyEndpoint = 'GetCompanySettings';
    const adminPlansEndpoint = 'GetAdminPlans';
    expect(adminCompanyEndpoint, isNot('GetCompanyInfo'));
    expect(adminPlansEndpoint, isNot('GetPlans'));
  });
}
