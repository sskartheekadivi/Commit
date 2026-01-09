import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:commit/database/database.dart';
import 'package:commit/models/habit_type.dart';
import 'package:commit/providers/providers.dart';
import 'package:commit/repositories/habit_repository.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';

// --- DATA MODEL ---
class ArchivedGroup {
  final Category category;
  final List<Habit> habits;
  final bool isCategoryArchived;

  ArchivedGroup({
    required this.category,
    required this.habits,
    required this.isCategoryArchived,
  });
}

// --- INTERNAL STREAMS (To make the UI reactive) ---
final _archivedHabitsStream = StreamProvider<List<Habit>>((ref) {
  return ref.watch(habitRepositoryProvider).watchAllArchivedHabits();
});

final _allCategoriesStream = StreamProvider<List<Category>>((ref) {
  return ref.watch(habitRepositoryProvider).watchCategoriesIncludingArchived();
});

// --- COMPUTED PROVIDER ---
// This watches the streams above. When DB changes, this re-runs automatically.
final archivedDataModelProvider = Provider<AsyncValue<List<ArchivedGroup>>>((ref) {
  final habitsAsync = ref.watch(_archivedHabitsStream);
  final categoriesAsync = ref.watch(_allCategoriesStream);

  // If either stream is loading/error, bubble that state up
  if (habitsAsync.isLoading || categoriesAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (habitsAsync.hasError) {
    return AsyncValue.error(habitsAsync.error!, habitsAsync.stackTrace!);
  }
  if (categoriesAsync.hasError) {
    return AsyncValue.error(categoriesAsync.error!, categoriesAsync.stackTrace!);
  }

  // Combine data
  final archivedHabits = habitsAsync.requireValue;
  final allCategories = categoriesAsync.requireValue;
  final List<ArchivedGroup> groups = [];

  for (final cat in allCategories) {
    final habitsForCat = archivedHabits.where((h) => h.categoryId == cat.id).toList();
    
    // Show if Category is archived OR if it contains archived habits
    if (cat.archived || habitsForCat.isNotEmpty) {
      groups.add(ArchivedGroup(
        category: cat,
        habits: habitsForCat,
        isCategoryArchived: cat.archived,
      ));
    }
  }
  
  return AsyncValue.data(groups);
});


class ArchivedHabitsScreen extends ConsumerWidget {
  const ArchivedHabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(archivedDataModelProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Archived'),
        centerTitle: false,
      ),
      body: asyncData.when(
        data: (groups) {
          if (groups.isEmpty) {
            return const Center(child: Text("No archived items"));
          }

          return LayoutBuilder(builder: (context, constraints) {
             final double statusCellWidth = (constraints.maxWidth * 0.55) / 7;

             return CustomScrollView(
               slivers: [
                 SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: _HeaderRow(statusCellWidth: statusCellWidth),
                    ),
                 ),

                 SliverList(
                   delegate: SliverChildBuilderDelegate(
                     (context, index) {
                       final group = groups[index];
                       return Padding(
                         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                         child: _ArchivedGroupCard(
                           group: group, 
                           statusCellWidth: statusCellWidth
                         ),
                       );
                     },
                     childCount: groups.length,
                   ),
                 ),
                 
                 const SliverToBoxAdapter(child: SizedBox(height: 50)),
               ],
             );
          });
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _ArchivedGroupCard extends ConsumerWidget {
  final ArchivedGroup group;
  final double statusCellWidth;

  const _ArchivedGroupCard({required this.group, required this.statusCellWidth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // Visual style: Fade it out slightly to indicate "Archived" state
    final opacity = 0.85;

    return Opacity(
      opacity: opacity,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- HEADER ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Icon(
                    group.isCategoryArchived ? Icons.archive : Icons.folder_open, 
                    size: 18, 
                    color: group.isCategoryArchived ? Colors.orange : colorScheme.primary
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      group.category.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: colorScheme.onSurface,
                        decoration: group.isCategoryArchived ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  
                  // Restore Category Button
                  if (group.isCategoryArchived)
                    IconButton.filledTonal(
                      onPressed: () async {
                        await ref.read(habitRepositoryProvider).unarchiveCategory(group.category.id);
                        // No need to manually refresh; StreamProvider handles it automatically
                      },
                      icon: const Icon(Icons.restore_from_trash, size: 18),
                      tooltip: "Restore Category",
                    ),
                ],
              ),
            ),
            const Divider(height: 1),

            // --- HABITS ---
            if (group.habits.isEmpty)
              const Padding(
                 padding: EdgeInsets.all(16),
                 child: Text("Category is archived (Empty)", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: group.habits.length,
                padding: EdgeInsets.zero,
                separatorBuilder: (c, i) => Divider(height: 1, indent: 16, endIndent: 16, color: colorScheme.outlineVariant.withOpacity(0.3)),
                itemBuilder: (context, index) {
                  final habit = group.habits[index];
                  return _ArchivedHabitRow(
                    habit: habit, 
                    statusCellWidth: statusCellWidth
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ArchivedHabitRow extends ConsumerWidget {
  final Habit habit;
  final double statusCellWidth;

  const _ArchivedHabitRow({required this.habit, required this.statusCellWidth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Name + Restore Button
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      habit.name,
                      maxLines: 2,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.restore, size: 20, color: Colors.green),
                    tooltip: "Restore Habit",
                    onPressed: () async {
                       await ref.read(habitRepositoryProvider).unarchiveHabit(habit.id);
                       // No manual refresh needed
                    },
                  ),
                ],
              ),
            ),
          ),
          
          // Status Cells (Read Only visuals)
          ...List.generate(7, (index) {
            final date = DateTime.now().subtract(Duration(days: 6 - index));
            return SizedBox(
              width: statusCellWidth,
              child: _ReadOnlyStatusCell(habit: habit, date: date, size: statusCellWidth),
            );
          }),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.statusCellWidth});
  final double statusCellWidth;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Row(
      children: [
        const SizedBox(width: 16),
        const Expanded(
          flex: 3, 
          child: Text('HABIT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: Colors.grey))
        ),
        ...List.generate(7, (index) {
          final date = today.subtract(Duration(days: 6 - index));
          return SizedBox(
            width: statusCellWidth,
            child: Column(
              children: [
                Text(DateFormat.d().format(date), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                Text(DateFormat.E().format(date).substring(0, 1), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
              ],
            ),
          );
        }),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _ReadOnlyStatusCell extends ConsumerWidget {
  const _ReadOnlyStatusCell({required this.habit, required this.date, required this.size});
  final Habit habit;
  final DateTime date;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logAsync = ref.watch(logForHabitOnDateProvider(habit.id, date));
    final habitType = HabitType.fromString(habit.type);
    
    // Non-interactive, just visual
    return Opacity(
      opacity: 0.5, // Dimmed
      child: Container(
        alignment: Alignment.center,
        child: logAsync.when(
          data: (log) {
            final theme = Theme.of(context);
            
            // Time logic
            if (habitType == HabitType.time && log != null) {
               return Text(log.value, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold));
            }

            if (habitType == HabitType.measurable) {
              if (log == null) return Text('—', style: TextStyle(fontSize: 10, color: theme.colorScheme.outline));
              return Text(log.value, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold));
            }
            Color? fillColor;
            if (log != null) {
              if (habitType == HabitType.boolean || habitType == HabitType.description || habitType == HabitType.time) {
                fillColor = Color(habit.color ?? theme.colorScheme.primary.value);
              } else if (habitType == HabitType.enumType) {
                final enumOptions = ref.watch(enumOptionsProvider(habit.id)).valueOrNull ?? [];
                final option = enumOptions.firstWhereOrNull((opt) => opt.value == log.value);
                fillColor = option != null ? Color(option.color) : theme.colorScheme.primary;
              }
            }
            final circleSize = size * 0.6; 
            return Container(
              height: circleSize,
              width: circleSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fillColor,
                border: Border.all(color: fillColor ?? theme.colorScheme.outline.withOpacity(0.3)),
              ),
            );
          },
          loading: () => const SizedBox(),
          error: (e, s) => const SizedBox(), // Silent error for read-only
        ),
      ),
    );
  }
}
