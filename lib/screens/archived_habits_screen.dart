import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:commit/providers/providers.dart';

class ArchivedHabitsScreen extends ConsumerWidget {
  const ArchivedHabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archivedHabitsAsync = ref.watch(allArchivedHabitsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Archived Habits'),
      ),
      body: archivedHabitsAsync.when(
        data: (habits) {
          if (habits.isEmpty) {
            return const Center(
              child: Text('No archived habits.'),
            );
          }
          return ListView.builder(
            itemCount: habits.length,
            itemBuilder: (context, index) {
              final habit = habits[index];
              return ListTile(
                title: Text(habit.name),
                trailing: const Icon(Icons.unarchive),
                onTap: () => context.push('/details/${habit.id}'),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => const Center(child: Text('Could not load archived habits.')),
      ),
    );
  }
}