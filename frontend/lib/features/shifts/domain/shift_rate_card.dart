/// Nursery-facing slice of the platform rate card returned by the
/// `GetActiveRateCard` endpoint.
///
/// A nursery is quoted the staffing charge and nothing else: practitioner pay
/// is set by K Flex admin (owner brief §3) and is deliberately not modelled
/// here, so there is no way to leak it into the posting flow. Both rates are
/// snapshotted onto the shift server-side, so what is displayed before
/// publishing is exactly what the invoice will use.
class ShiftRateCard {
  const ShiftRateCard({
    required this.id,
    required this.version,
    required this.chargesPencePerHour,
  });

  final String id;
  final int version;

  /// Qualification level (`none`, `level_2`, `level_3`, `level_4_plus`) to the
  /// hourly staffing charge in pence.
  final Map<String, int> chargesPencePerHour;

  factory ShiftRateCard.fromJson(Map<String, dynamic> json) {
    final rates = (json['rates'] as Map?)?.cast<String, dynamic>() ?? const {};
    final charges = <String, int>{};
    rates.forEach((qualification, raw) {
      final row = (raw as Map?)?.cast<String, dynamic>();
      final charge = (row?['nurseryChargePencePerHour'] as num?)?.toInt() ?? 0;
      if (charge > 0) charges[qualification] = charge;
    });
    return ShiftRateCard(
      id: (json['id'] as String?) ?? '',
      version: (json['version'] as num?)?.toInt() ?? 0,
      chargesPencePerHour: charges,
    );
  }

  /// Charge for a qualification band. Matches the backend's fallback: an
  /// unknown band is priced at the unqualified rate rather than free.
  int? chargePenceFor(String qualification) =>
      chargesPencePerHour[qualification] ?? chargesPencePerHour['none'];
}
