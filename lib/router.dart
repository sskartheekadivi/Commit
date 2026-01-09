import 'package:commit/screens/manage_categories_screen.dart';
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
        path: '/categories',
        builder: (context, state) => const ManageCategoriesScreen(),
      ),
      GoRoute(
        path: '/create',
        builder: (context, state) {
          final map = state.extra as Map<String, dynamic>?; 
          return CreateEditHabitScreen(
              preselectedType: map?['type'] as HabitType?,
              preselectedCategoryId: map?['categoryId'] as int?, // Pass the ID here
          );
          // final habitType = state.extra as HabitType?;
          // return CreateEditHabitScreen(preselectedType: habitType);
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
