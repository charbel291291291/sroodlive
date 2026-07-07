import 'package:flutter_test/flutter_test.dart';
import 'package:srood_live/features/profile_hub/models/profile_hub_models.dart';

void main() {
  group('AgencyApplication', () {
    test('parses creation details and review outcome', () {
      final application = AgencyApplication.fromJson(const {
        'id': 'application-1',
        'application_type': 'create_agency',
        'status': 'approved',
        'agency_name': 'Srood Stars',
        'message': 'Ready to build a team',
        'admin_reply': 'Approved',
        'created_at': '2026-07-01T10:00:00Z',
        'reviewed_at': '2026-07-02T10:00:00Z',
      });

      expect(application.applicationType, 'create_agency');
      expect(application.agencyName, 'Srood Stars');
      expect(application.adminReply, 'Approved');
      expect(application.reviewedAt, isNotNull);
    });
  });

  group('AgencyMembership', () {
    test('parses authoritative agency-host membership payload', () {
      final membership = AgencyMembership.fromJson(const {
        'role': 'host',
        'status': 'active',
        'agencies': {
          'name': 'Srood Stars',
          'country': 'LB',
          'commission_rate': 0.075,
          'monthly_target_coins': 500000,
          'monthly_target_hours': 40,
        },
      });

      expect(membership.agencyName, 'Srood Stars');
      expect(membership.status, 'active');
      expect(membership.commissionRate, 0.075);
      expect(membership.monthlyTargetCoins, 500000);
      expect(membership.monthlyTargetHours, 40);
    });
  });
}
