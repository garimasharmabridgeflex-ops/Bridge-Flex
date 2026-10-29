import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/live/live_refresh.dart';
import '../domain/shift.dart';
import 'shift_repository.dart';

class BookmarkedShiftsNotifier extends StateNotifier<Set<String>> {
  BookmarkedShiftsNotifier() : super(const <String>{});

  void toggle(String shiftId) {
    if (state.contains(shiftId)) {
      state = Set<String>.from(state)..remove(shiftId);
    } else {
      state = Set<String>.from(state)..add(shiftId);
    }
  }

  bool isBookmarked(String shiftId) => state.contains(shiftId);
}

final bookmarkedShiftIdsProvider =
    StateNotifierProvider<BookmarkedShiftsNotifier, Set<String>>((ref) {
  return BookmarkedShiftsNotifier();
});

/// Returns full Shift models for all bookmarked shift IDs
final savedShiftsListProvider = FutureProvider.autoDispose<List<Shift>>((ref) async {
  // Rides the live heartbeat so a saved shift that has since been filled or
  // cancelled stops looking available.
  ref.watch(liveTickProvider);
  final ids = ref.watch(bookmarkedShiftIdsProvider);
  if (ids.isEmpty) return const [];

  final shiftRepo = ref.watch(shiftRepositoryProvider);
  final allOpen = await shiftRepo.fetchOpenShifts().catchError((_) => <Shift>[]);
  final myShifts = await shiftRepo.fetchMyShifts().catchError((_) => <Shift>[]);

  final combined = <String, Shift>{};
  for (final s in [...allOpen, ...myShifts]) {
    combined[s.id] = s;
  }

  final result = <Shift>[];
  for (final id in ids) {
    if (combined.containsKey(id)) {
      result.add(combined[id]!);
    }
  }
  return result;
});
