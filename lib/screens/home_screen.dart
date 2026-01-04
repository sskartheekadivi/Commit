import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:commit/database/database.dart';
import 'package:commit/models/habit_type.dart';
import 'package:commit/providers/providers.dart';
import 'package:commit/repositories/habit_repository.dart';
import 'package:commit/utils/date_utils.dart';
import 'package:commit/widgets/log_habit_dialog.dart';
import 'package:intl/intl.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(allHabitsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Commit'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: 'Archived Habits',
            onPressed: () => context.push('/archived'),
          ),
        ],
      ),
      body: habitsAsync.when(
        data: (habits) {
          if (habits.isEmpty) {
            return const Center(child: Text('No habits yet. Tap "+" to add one!', style: TextStyle(fontSize: 18)));
          }
          return LayoutBuilder(builder: (context, constraints) {
            final double statusCellWidth = (constraints.maxWidth * 0.7) / 7;

            return Column(
              children: [
                HeaderRow(statusCellWidth: statusCellWidth),
                Expanded(
                  child: ReorderableListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (int i = 0; i < habits.length; i++)
                        HabitRow(
                          key: ValueKey(habits[i].id),
                          habit: habits[i],
                          statusCellWidth: statusCellWidth,
                        ),
                    ],
                    onReorder: (oldIndex, newIndex) {
                      if (oldIndex < newIndex) {
                        newIndex -= 1;
                      }
                      final updatedHabits = List<Habit>.from(habits);
                      final item = updatedHabits.removeAt(oldIndex);
                      updatedHabits.insert(newIndex, item);
                      ref.read(habitRepositoryProvider).updateHabitOrder(updatedHabits);
                    },
                  ),
                ),
              ],
            );
          });
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => const Center(child: Text('Error: Failed to load habits.')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddHabitOptions(context),
        child: const Icon(Icons.add),
      ),
    );
  }
  
  void _showAddHabitOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Wrap(
        children: HabitType.values.map((type) => ListTile(
          leading: Icon(_getIconForHabitType(type)),
          title: Text(type.value),
          onTap: () {
            Navigator.of(context).pop();
            context.push('/create', extra: type);
          },
        )).toList(),
      ),
    );
  }

  IconData _getIconForHabitType(HabitType type) {
    switch (type) {
      case HabitType.boolean: return Icons.check_box_outlined;
      case HabitType.measurable: return Icons.straighten;
      case HabitType.enumType: return Icons.format_list_bulleted;
      case HabitType.description: return Icons.notes;
    }
  }
}

class HeaderRow extends StatelessWidget {
  const HeaderRow({super.key, required this.statusCellWidth});
  final double statusCellWidth;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const Expanded(flex: 3, child: Text('Habit', style: TextStyle(fontWeight: FontWeight.bold))),
          ...List.generate(7, (index) {
            final date = today.subtract(Duration(days: 6 - index));
            return SizedBox(
              width: statusCellWidth,
              child: Column(
                children: [
                  Text(DateFormat.d().format(date), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  Text(DateFormat.E().format(date).substring(0, 1), style: const TextStyle(fontSize: 10)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class HabitRow extends StatelessWidget {
  const HabitRow({super.key, required this.habit, required this.statusCellWidth});
  final Habit habit;
  final double statusCellWidth;
  
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: GestureDetector(
                onTap: () => context.push('/details/${habit.id}'),
                child: Container(
                  padding: const EdgeInsets.all(8.0),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    habit.name,
                    style: TextStyle(color: habit.color != null ? Color(habit.color!) : null, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            ...List.generate(7, (index) {
              final date = DateTime.now().subtract(Duration(days: 6 - index));
              return SizedBox(
                width: statusCellWidth,
                child: StatusCell(habit: habit, date: date, size: statusCellWidth),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class StatusCell extends ConsumerWidget {
  const StatusCell({super.key, required this.habit, required this.date, required this.size});
  final Habit habit;
  final DateTime date;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logAsync = ref.watch(logForHabitOnDateProvider(habit.id, date));
    final habitType = HabitType.fromString(habit.type);
    
    final today = DateTime.now();
    final isFutureDate = date.isAfter(today.copyWith(hour: 23, minute: 59, second: 59));

    return GestureDetector(
      onTap: isFutureDate ? null : () async { // Disable onTap for future dates
        try {
          final repo = ref.read(habitRepositoryProvider);
          if (habitType == HabitType.boolean) {
            logAsync.valueOrNull == null
                ? await repo.createLog(habit.id, date, 'TRUE')
                : await repo.clearHabitLog(habit.id, date);
          } else {
            showDialog(
              context: context,
              builder: (context) => LogHabitDialog(habit: habit, date: date, log: logAsync.valueOrNull),
            );
          }
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Could not update log.')));
        }
      },
      child: Opacity( // Apply opacity for visual disabling
        opacity: isFutureDate ? 0.4 : 1.0,
        child: Container(
          color: Colors.transparent,
          alignment: Alignment.center,
          child: logAsync.when(
            data: (log) {
              final theme = Theme.of(context);
              if (habitType == HabitType.measurable) {
                if (log == null) return Text('—', style: TextStyle(fontSize: 12, color: Colors.grey.shade600));
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(log.value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    if (habit.unit != null) Text(habit.unit!, style: const TextStyle(fontSize: 9, color: Colors.grey)),
                  ],
                );
              }
              Color? fillColor;
              if (log != null) {
                if (habitType == HabitType.boolean || habitType == HabitType.description) {
                  fillColor = Color(habit.color ?? Colors.green.value);
                } else if (habitType == HabitType.enumType) {
                  final enumOptions = ref.watch(enumOptionsProvider(habit.id)).valueOrNull ?? [];
                  final option = enumOptions.firstWhereOrNull((opt) => opt.value == log.value);
                  fillColor = option != null ? Color(option.color) : theme.colorScheme.primary;
                }
              }
              return Container(
                height: size * 0.6,
                width: size * 0.6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fillColor,
                                    border: Border.all(color: fillColor ?? Colors.grey.shade700, width: 1.5),
                                  ),
                                );
                              },
                              loading: () => SizedBox(height: size * 0.5, width: size * 0.5, child: const CircularProgressIndicator(strokeWidth: 1.5)),
                              error: (e, s) => Icon(Icons.error_outline, color: Colors.yellow, size: size * 0.6),
                            ),
                          ),
                        ),
                      );
                    }
                  }
                  
                  extension IterableExt<T> on Iterable<T> {
                    T? firstWhereOrNull(bool Function(T) test) {
                      for (var element in this) {
                        if (test(element)) return element;
                      }
                      return null;
                    }
                  }