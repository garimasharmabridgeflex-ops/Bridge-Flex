import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Kept separate from providers.dart: this is the one remaining direct
/// Firestore SDK (gRPC) dependency in the app, used only by
/// AuthRepository's best-effort profile-doc creation on sign-up. Everything
/// else reads/writes through plain-HTTP Cloud Function endpoints — see
/// shift_repository.dart's fetchOpenShifts doc comment for why.
final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);
