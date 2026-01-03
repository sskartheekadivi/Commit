import 'package:drift/drift.dart';
import 'package:commit/database/database.dart';
import 'package:commit/models/habit_type.dart';

// Simple data class to decouple UI from the database companions
class EnumOptionData {
  final String value;
  final int color;
  EnumOptionData({required this.value, required this.color});
}

class HabitRepository {
  final AppDatabase _db;

  HabitRepository(this._db);

  // GETTERS

  Stream<List<Habit>> watchAllHabits() {
    return (_db.select(_db.habits)
          ..where((h) => h.archived.equals(false))
          ..orderBy([(h) => OrderingTerm(expression: h.orderIndex)]))
        .watch();
  }

  Stream<List<Habit>> watchAllArchivedHabits() {
    return (_db.select(_db.habits)
          ..where((h) => h.archived.equals(true))
          ..orderBy([(h) => OrderingTerm(expression: h.orderIndex)]))
        .watch();
  }

  Stream<Habit> watchHabit(int id) {
    return (_db.select(_db.habits)..where((h) => h.id.equals(id))).watchSingle();
  }

  Stream<List<Log>> watchLogsForHabit(int habitId) {
    return (_db.select(_db.logs)
          ..where((l) => l.habitId.equals(habitId))
          ..orderBy([(l) => OrderingTerm(expression: l.date, mode: OrderingMode.desc)]))
        .watch();
  }
  
  Stream<List<Log>> watchLogsForHabitLast7Days(int habitId, DateTime today) {
    final sevenDaysAgo = today.subtract(const Duration(days: 6));
    final startOfToday = DateTime(today.year, today.month, today.day);
    final startOfSevenDaysAgo = DateTime(sevenDaysAgo.year, sevenDaysAgo.month, sevenDaysAgo.day);

    return (_db.select(_db.logs)
          ..where((l) => l.habitId.equals(habitId) & l.date.isBetween(Constant(startOfSevenDaysAgo), Constant(startOfToday)))
          ..orderBy([(l) => OrderingTerm(expression: l.date, mode: OrderingMode.desc)]))
        .watch();
  }

  Stream<Log?> watchLogForHabitOnDate(int habitId, DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    return (_db.select(_db.logs)
          ..where((l) => l.habitId.equals(habitId) & l.date.equals(startOfDay)))
        .watchSingleOrNull();
  }

  Stream<List<EnumOption>> watchEnumOptions(int habitId) {
    return (_db.select(_db.enumOptions)..where((o) => o.habitId.equals(habitId))).watch();
  }

  Future<List<EnumOption>> getEnumOptionsForHabit(int habitId) {
    return (_db.select(_db.enumOptions)..where((o) => o.habitId.equals(habitId))).get();
  }

  // MODIFIERS

  Future<void> createLog(int habitId, DateTime date, String value) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final companion = LogsCompanion.insert(
      habitId: habitId,
      date: startOfDay,
      value: value,
    );
    return _db.into(_db.logs).insertOnConflictUpdate(companion);
  }

  Future<void> updateLog(Log log, String newValue) {
    final companion = log.copyWith(value: newValue);
    return (_db.update(_db.logs)..where((l) => l.id.equals(log.id))).write(companion);
  }

  Future<void> clearHabitLog(int habitId, DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    return (_db.delete(_db.logs)..where((l) => l.habitId.equals(habitId) & l.date.equals(startOfDay))).go();
  }

  Future<int> createHabit({
    required String name,
    required HabitType type,
    int? color,
    String? notificationText,
    double? targetValue,
    String? unit,
    List<EnumOptionData> enumOptions = const [],
  }) async {
    final existing = await (_db.select(_db.habits)..where((h) => h.name.lower().equals(name.toLowerCase()))).getSingleOrNull();
    if (existing != null) {
      throw Exception('A habit with this name already exists.');
    }

    return _db.transaction(() async {
      final maxOrderResult = await (_db.selectOnly(_db.habits)..addColumns([_db.habits.orderIndex.max()])).getSingle();
      final maxOrder = maxOrderResult.read(_db.habits.orderIndex.max()) ?? 0;

      final habitId = await _db.into(_db.habits).insert(
            HabitsCompanion.insert(
              name: name,
              type: type.value,
              color: Value(color),
              notificationText: Value(notificationText),
              targetValue: Value(targetValue),
              unit: Value(unit),
              createdAt: DateTime.now(),
              orderIndex: Value(maxOrder + 1),
            ),
          );

      if (type == HabitType.enumType) {
        for (final option in enumOptions) {
          await _db.into(_db.enumOptions).insert(EnumOptionsCompanion.insert(
            habitId: habitId,
            value: option.value,
            color: option.color,
          ));
        }
      }
      return habitId;
    });
  }

  Future<bool> updateHabit({
    required Habit habit,
    List<EnumOptionData> enumOptions = const [],
  }) {
    return _db.transaction(() async {
      if (HabitType.fromString(habit.type) == HabitType.enumType) {
        await (_db.delete(_db.enumOptions)..where((o) => o.habitId.equals(habit.id))).go();
        for (final option in enumOptions) {
           await _db.into(_db.enumOptions).insert(EnumOptionsCompanion.insert(
            habitId: habit.id,
            value: option.value,
            color: option.color,
          ));
        }
      }
      return _db.update(_db.habits).replace(habit);
    });
  }
  
  Future<void> updateHabitOrder(List<Habit> habits) {
    return _db.transaction(() async {
      for (int i = 0; i < habits.length; i++) {
        final habit = habits[i];
        final companion = habit.copyWith(orderIndex: i);
        await (_db.update(_db.habits)..where((h) => h.id.equals(habit.id))).write(companion);
      }
    });
  }

  Future<void> archiveHabit(int habitId) {
    return (_db.update(_db.habits)..where((h) => h.id.equals(habitId))).write(const HabitsCompanion(archived: Value(true)));
  }

  Future<void> unarchiveHabit(int habitId) {
    return (_db.update(_db.habits)..where((h) => h.id.equals(habitId))).write(const HabitsCompanion(archived: Value(false)));
  }

  Future<void> deleteHabit(int habitId) {
    return _db.transaction(() async {
      await (_db.delete(_db.logs)..where((l) => l.habitId.equals(habitId))).go();
      await (_db.delete(_db.enumOptions)..where((o) => o.habitId.equals(habitId))).go();
      await (_db.delete(_db.habits)..where((h) => h.id.equals(habitId))).go();
    });
  }
}
