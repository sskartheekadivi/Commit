import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  // --- HABIT WATCHERS ---

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
  
  Stream<List<Habit>> watchHabitsForCategory(int categoryId) {
    return (_db.select(_db.habits)
          ..where((h) => h.categoryId.equals(categoryId) & h.archived.equals(false))
          ..orderBy([(h) => OrderingTerm(expression: h.orderIndex)]))
        .watch();
  }
  
  Stream<List<Habit>> watchUncategorizedHabits() {
    return (_db.select(_db.habits)
          ..where((h) => h.categoryId.isNull() & h.archived.equals(false))
          ..orderBy([(h) => OrderingTerm(expression: h.orderIndex)]))
        .watch();
  }

  Stream<List<Habit>> watchAllHabitsForCategoryIncludingArchived(int categoryId) {
    return (_db.select(_db.habits)
          ..where((h) => h.categoryId.equals(categoryId))
          ..orderBy([(h) => OrderingTerm(expression: h.orderIndex)]))
        .watch();
  }

  Stream<Habit> watchHabit(int id) {
    return (_db.select(_db.habits)..where((h) => h.id.equals(id))).watchSingle();
  }

  Future<Habit> getHabit(int id) {
    return (_db.select(_db.habits)..where((h) => h.id.equals(id))).getSingle();
  }

  // --- LOG WATCHERS ---

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
  
  Future<bool> isHabitLoggedOnDate(int habitId, DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final count = await (_db.select(_db.logs)
          ..where((l) => l.habitId.equals(habitId) & l.date.equals(startOfDay)))
        .getSingleOrNull();
    return count != null;
  }

  // --- ENUM OPTIONS ---

  Stream<List<EnumOption>> watchEnumOptions(int habitId) {
    return (_db.select(_db.enumOptions)..where((o) => o.habitId.equals(habitId))).watch();
  }

  Future<List<EnumOption>> getEnumOptionsForHabit(int habitId) {
    return (_db.select(_db.enumOptions)..where((o) => o.habitId.equals(habitId))).get();
  }

  // --- CATEGORY WATCHERS ---

  Stream<List<Category>> watchAllCategories() {
    return (_db.select(_db.categories)
          ..where((c) => c.archived.equals(false)) 
          ..orderBy([
            (t) => OrderingTerm(expression: t.orderIndex),
          ]))
        .watch();
  }

  Stream<List<Category>> watchArchivedCategories() {
    return (_db.select(_db.categories)
          ..where((c) => c.archived.equals(true))
          ..orderBy([
            (t) => OrderingTerm(expression: t.orderIndex),
          ]))
        .watch();
  }

  Stream<List<Category>> watchCategoriesIncludingArchived() {
    return (_db.select(_db.categories)
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .watch();
  }

  // --- MODIFIERS (Habits & Logs) ---

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

  // RULE 3: New habit brings category back to life
  Future<int> createHabit({
    required String name,
    required HabitType type,
    int? color,
    String? notificationText,
    double? targetValue,
    String? unit,
    List<EnumOptionData> enumOptions = const [],
    int? reminderHour,
    int? reminderMinute,
    String? reminderDays,
    int? categoryId,
  }) async {
    final existing = await (_db.select(_db.habits)..where((h) => h.name.lower().equals(name.toLowerCase()))).getSingleOrNull();
    if (existing != null) {
      throw Exception('A habit with this name already exists.');
    }

    return _db.transaction(() async {
      // 1. Determine Category ID (Default to General if null)
      int finalCategoryId;
      if (categoryId != null) {
        finalCategoryId = categoryId;
      } else {
        final generalCat = await (_db.select(_db.categories)..where((c) => c.name.equals('General'))).getSingle();
        finalCategoryId = generalCat.id;
      }

      // 2. RULE 3: Check if Category is archived. If so, unarchive it.
      final category = await (_db.select(_db.categories)..where((c) => c.id.equals(finalCategoryId))).getSingle();
      if (category.archived) {
        await (_db.update(_db.categories)..where((c) => c.id.equals(finalCategoryId)))
            .write(const CategoriesCompanion(archived: Value(false)));
      }

      // 3. Create Habit
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
              reminderHour: Value(reminderHour),
              reminderMinute: Value(reminderMinute),
              reminderDays: Value(reminderDays),
              categoryId: Value(finalCategoryId),
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
    required HabitsCompanion companion,
    List<EnumOptionData> enumOptions = const [],
  }) {
    return _db.transaction(() async {
      if (companion.type.value == HabitType.enumType.value) {
        await (_db.delete(_db.enumOptions)..where((o) => o.habitId.equals(companion.id.value))).go();
        for (final option in enumOptions) {
           await _db.into(_db.enumOptions).insert(EnumOptionsCompanion.insert(
            habitId: companion.id.value,
            value: option.value,
            color: option.color,
          ));
        }
      }
      final updatedRows = await (_db.update(_db.habits)..where((h) => h.id.equals(companion.id.value))).write(companion);
      return updatedRows > 0;
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

  // RULE 2: Archive habit -> Check if Category needs archiving
  Future<void> archiveHabit(int habitId) {
    return _db.transaction(() async {
      // 1. Archive the habit
      await (_db.update(_db.habits)..where((h) => h.id.equals(habitId)))
          .write(const HabitsCompanion(archived: Value(true)));

      // 2. Check the category of this habit
      final habit = await (_db.select(_db.habits)..where((h) => h.id.equals(habitId))).getSingle();
      if (habit.categoryId != null) {
        // Count remaining ACTIVE habits in this category
        final activeCountResult = await (_db.selectOnly(_db.habits)
              ..addColumns([_db.habits.id.count()])
              ..where(_db.habits.categoryId.equals(habit.categoryId!))
              ..where(_db.habits.archived.equals(false)))
            .getSingle();
            
        final activeCount = activeCountResult.read(_db.habits.id.count()) ?? 0;

        // If NO active habits remain, archive the category too
        if (activeCount == 0) {
           await (_db.update(_db.categories)..where((c) => c.id.equals(habit.categoryId!)))
              .write(const CategoriesCompanion(archived: Value(true)));
        }
      }
    });
  }

  // RULE 3 (Reverse): Unarchive habit -> Bring category back to life
  Future<void> unarchiveHabit(int habitId) async {
    return _db.transaction(() async {
      // 1. Unarchive Habit
      await (_db.update(_db.habits)..where((h) => h.id.equals(habitId)))
          .write(const HabitsCompanion(archived: Value(false)));

      // 2. Get Habit to find Category
      final habit = await (_db.select(_db.habits)..where((h) => h.id.equals(habitId))).getSingle();
      
      // 3. Ensure Category is Unarchived
      if (habit.categoryId != null) {
         await (_db.update(_db.categories)..where((c) => c.id.equals(habit.categoryId!)))
            .write(const CategoriesCompanion(archived: Value(false)));
      }
    });
  }

  Future<void> deleteHabit(int habitId) {
    return _db.transaction(() async {
      await (_db.delete(_db.logs)..where((l) => l.habitId.equals(habitId))).go();
      await (_db.delete(_db.enumOptions)..where((o) => o.habitId.equals(habitId))).go();
      await (_db.delete(_db.habits)..where((h) => h.id.equals(habitId))).go();
    });
  }

  // --- MODIFIERS (Categories) ---
  
  Future<int> createCategory(String name) async {
    final existing = await (_db.select(_db.categories)..where((c) => c.name.lower().equals(name.toLowerCase()))).getSingleOrNull();
    if (existing != null) {
       // If it exists but is archived, unarchive it
       if (existing.archived) {
         await (_db.update(_db.categories)..where((c) => c.id.equals(existing.id)))
            .write(const CategoriesCompanion(archived: Value(false)));
         return existing.id;
       }
       throw Exception('A category with this name already exists.');
    }
    final maxOrderResult = await (_db.selectOnly(_db.categories)..addColumns([_db.categories.orderIndex.max()])).getSingle();
    final maxOrder = maxOrderResult.read(_db.categories.orderIndex.max()) ?? 0;
    
    final companion = CategoriesCompanion.insert(name: name, orderIndex: Value(maxOrder + 1));
    return _db.into(_db.categories).insert(companion);
  }

  Future<bool> updateCategory(Category category) {
    return _db.update(_db.categories).replace(category);
  }

  Future<void> updateCategoryOrder(List<Category> categories) {
    return _db.transaction(() async {
      for (int i = 0; i < categories.length; i++) {
        final category = categories[i];
        final companion = category.copyWith(orderIndex: i);
        await (_db.update(_db.categories)..where((c) => c.id.equals(category.id))).write(companion);
      }
    });
  }

  // RULE 1: Archive Category -> Archive all habits inside
  Future<void> archiveCategory(int categoryId) {
    return _db.transaction(() async {
      // 1. Archive Category
      await (_db.update(_db.categories)..where((c) => c.id.equals(categoryId)))
          .write(const CategoriesCompanion(archived: Value(true)));
      
      // 2. Archive ALL habits inside it (Rule 1)
      await (_db.update(_db.habits)..where((h) => h.categoryId.equals(categoryId)))
          .write(const HabitsCompanion(archived: Value(true)));
    });
  }

  Future<void> unarchiveCategory(int categoryId) {
    return _db.transaction(() async {
       await (_db.update(_db.categories)..where((c) => c.id.equals(categoryId)))
          .write(const CategoriesCompanion(archived: Value(false)));
       // We DO NOT auto-unarchive habits.
    });
  }

  Future<void> deleteCategory(int categoryId, bool deleteHabits) {
    return _db.transaction(() async {
      if (deleteHabits) {
        final habitsToDelete = await (_db.select(_db.habits)..where((h) => h.categoryId.equals(categoryId))).get();
        for (final habit in habitsToDelete) {
          await deleteHabit(habit.id);
        }
      } else {
        final generalCat = await (_db.select(_db.categories)..where((c) => c.name.equals('General'))).getSingleOrNull();
        await (_db.update(_db.habits)..where((h) => h.categoryId.equals(categoryId)))
            .write(HabitsCompanion(categoryId: Value(generalCat?.id)));
      }
      await (_db.delete(_db.categories)..where((c) => c.id.equals(categoryId))).go();
    });
  }

  Future<void> moveHabitToCategory(Habit habit, int? newCategoryId, int newIndex) async {
    return _db.transaction(() async {
      final targetHabits = await (_db.select(_db.habits)
            ..where((t) => newCategoryId == null ? t.categoryId.isNull() : t.categoryId.equals(newCategoryId))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();

      final mutableList = List<Habit>.from(targetHabits);
      if (habit.categoryId == newCategoryId) {
         mutableList.removeWhere((h) => h.id == habit.id);
      }
      if (newIndex > mutableList.length) newIndex = mutableList.length;
      mutableList.insert(newIndex, habit);

      for (int i = 0; i < mutableList.length; i++) {
        final item = mutableList[i];
        await (_db.update(_db.habits)..where((h) => h.id.equals(item.id))).write(
          item.toCompanion(true).copyWith(
            orderIndex: Value(i),
            categoryId: Value(newCategoryId),
          ),
        );
      }
    });
  }
}
