import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:commit/database/database.dart';
import 'package:commit/repositories/habit_repository.dart';

part 'providers.g.dart';

@Riverpod(keepAlive: true)
AppDatabase appDatabase(AppDatabaseRef ref) {
  ref.onDispose(() => ref.state.close());
  return AppDatabase();
}

@Riverpod(keepAlive: true)
HabitRepository habitRepository(HabitRepositoryRef ref) {
  return HabitRepository(ref.watch(appDatabaseProvider));
}

@riverpod
Stream<List<Habit>> allHabits(AllHabitsRef ref) {
  return ref.watch(habitRepositoryProvider).watchAllHabits();
}

@riverpod
Stream<List<Habit>> allArchivedHabits(AllArchivedHabitsRef ref) {
  return ref.watch(habitRepositoryProvider).watchAllArchivedHabits();
}

@riverpod
Stream<Habit> habit(HabitRef ref, int id) {
  return ref.watch(habitRepositoryProvider).watchHabit(id);
}

@riverpod
Stream<List<Log>> logsForHabit(LogsForHabitRef ref, int habitId) {
  return ref.watch(habitRepositoryProvider).watchLogsForHabit(habitId);
}

@riverpod
Stream<Log?> logForHabitOnDate(LogForHabitOnDateRef ref, int habitId, DateTime date) {
  return ref.watch(habitRepositoryProvider).watchLogForHabitOnDate(habitId, date);
}

@riverpod
Stream<List<EnumOption>> enumOptions(EnumOptionsRef ref, int habitId) {
  return ref.watch(habitRepositoryProvider).watchEnumOptions(habitId);
}

@riverpod
Stream<List<Log>> logsForHabitLast7Days(LogsForHabitLast7DaysRef ref, int habitId) {
  return ref.watch(habitRepositoryProvider).watchLogsForHabitLast7Days(habitId, DateTime.now());
}