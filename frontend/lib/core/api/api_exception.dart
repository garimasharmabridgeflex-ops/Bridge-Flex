/// Mirrors the backend's JSON error envelope (ARCHITECTURE.md v2 §1a):
/// `{ "error": { "code": "SHIFT_ALREADY_BOOKED", "message": "..." } }`.
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  bool get isShiftAlreadyBooked => code == 'SHIFT_ALREADY_BOOKED';
  bool get isNotAuthenticated => code == 'NOT_AUTHENTICATED';

  @override
  String toString() => 'ApiException($statusCode, $code, $message)';
}
