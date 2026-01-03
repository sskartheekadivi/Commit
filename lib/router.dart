import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:commit/database/database.dart';
import 'package:commit/models/habit_type.dart';
import 'package:commit/screens/archived_habits_screen.dart';
import 'package:commit/screens/create_edit_habit_screen.dart';
import 'package:commit/screens/home_screen.dart';
import 'package:commit/screens/habit_details_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/archived',
        builder: (context, state) => const ArchivedHabitsScreen(),
      ),
      GoRoute(
        path: '/create',
        builder: (context, state) {
          final habitType = state.extra as HabitType?;
          return CreateEditHabitScreen(preselectedType: habitType);
        },
      ),
      GoRoute(
        path: '/edit',
        builder: (context, state) {
          final habit = state.extra as Habit;
          return CreateEditHabitScreen(habit: habit);
        },
      ),
      GoRoute(
        path: '/details/:id',
        builder: (context, state) {
          final habitId = int.parse(state.pathParameters['id']!);
          return HabitDetailsScreen(habitId: habitId);
        },
      ),
    ],
  );
});