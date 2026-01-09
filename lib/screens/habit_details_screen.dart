import 'package:flutter/material.dart';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:commit/database/database.dart';
import 'package:commit/models/habit_type.dart';
import 'package:commit/providers/providers.dart';
import 'package:commit/repositories/habit_repository.dart';
import 'package:commit/utils/date_utils.dart';
import 'package:commit/widgets/log_habit_dialog.dart';
import 'package:intl/intl.dart';

class HabitDetailsScreen extends ConsumerStatefulWidget {
  const HabitDetailsScreen({super.key, required this.habitId});
  final int habitId;

  @override
  ConsumerState<HabitDetailsScreen> createState() => _HabitDetailsScreenState();
}

class _HabitDetailsScreenState extends ConsumerState<HabitDetailsScreen> {
  bool _isEditMode = false;

  void _handleDateClick({required Habit habit, required DateTime date, Log? log}) async {
    final habitType = HabitType.fromString(habit.type);
    final repo = ref.read(habitRepositoryProvider);

    if (habitType == HabitType.boolean) {
      try {
        log == null
            ? await repo.createLog(habit.id, date, 'TRUE')
            : await repo.clearHabitLog(habit.id, date);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(log == null ? 'Logged for ${DateFormat.yMMMd().format(date)}' : 'Log cleared for ${DateFormat.yMMMd().format(date)}'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: Could not update log.')),
          );
        }
      }
    } else {
      showDialog(
        context: context,
        builder: (context) => LogHabitDialog(habit: habit, date: date, log: log),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final habitAsync = ref.watch(habitProvider(widget.habitId));

    return Scaffold(
      body: habitAsync.when(
        data: (habit) => CustomScrollView(
          slivers: [
            SliverAppBar(
              title: Text(habit.name),
              pinned: true,
              actions: [
                IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => context.push('/edit', extra: habit)),
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    switch (value) {
                      case 'archive':
                        await ref.read(habitRepositoryProvider).archiveHabit(habit.id);
                        if (mounted) context.pop();
                        break;
                      case 'unarchive':
                        await ref.read(habitRepositoryProvider).unarchiveHabit(habit.id);
                        break;
                      case 'delete':
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Habit?'),
                            content: const Text('This action is permanent and cannot be undone.'),
                            actions: [
                              TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
                              TextButton(onPressed: () => context.pop(true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await ref.read(habitRepositoryProvider).deleteHabit(habit.id);
                          if (mounted) context.go('/');
                        }
                        break;
                    }
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    if (habit.archived)
                      const PopupMenuItem<String>(value: 'unarchive', child: Text('Unarchive'))
                    else
                      const PopupMenuItem<String>(value: 'archive', child: Text('Archive')),
                    const PopupMenuItem<String>(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                  ],
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16.0),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  [
                    _HeaderStats(habit: habit),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Activity Heatmap', style: Theme.of(context).textTheme.titleLarge),
                        IconButton(
                          icon: Icon(_isEditMode ? Icons.edit_calendar : Icons.edit_calendar_outlined),
                          tooltip: 'Toggle Calendar Edit Mode',
                          onPressed: () => setState(() => _isEditMode = !_isEditMode),
                        ),
                      ],
                    ),
                    if (_isEditMode)
                      const Text('Edit mode is on. Tap a date to log or edit.', style: TextStyle(color: Colors.amber)),
                    const SizedBox(height: 8),
                    ActivityHeatmap(
                      habit: habit,
                      isEditMode: _isEditMode,
                      onDateClick: (date, log) => _handleDateClick(habit: habit, date: date, log: log),
                    ),
                    const SizedBox(height: 24),
                    Text('Log History', style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
              ),
            ),
            LogHistoryList(habit: habit),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _HeaderStats extends ConsumerWidget {
  const _HeaderStats({required this.habit});
  final Habit habit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(logsForHabitProvider(habit.id));
    return logsAsync.when(
      data: (logs) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  Text('Total', style: Theme.of(context).textTheme.bodySmall),
                  Text('${logs.length}', style: Theme.of(context).textTheme.headlineMedium),
                ],
              ),
            ],
          ),
        ),
      ),
      loading: () => const SizedBox.shrink(),
      error: (e, s) => const SizedBox.shrink(),
    );
  }
}

class ActivityHeatmap extends ConsumerWidget {
  const ActivityHeatmap({
    super.key, 
    required this.habit, 
    required this.isEditMode, 
    required this.onDateClick
  });

  final Habit habit;
  final bool isEditMode;
  final void Function(DateTime date, Log? log) onDateClick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. REMOVED: The block that hid the heatmap for Time type.
    
    final logsAsync = ref.watch(logsForHabitProvider(habit.id));
    final enumOptionsAsync = ref.watch(enumOptionsProvider(habit.id));
    final habitType = HabitType.fromString(habit.type);

    if (habitType == HabitType.enumType) {
      return enumOptionsAsync.when(
        data: (options) => _buildHeatmap(context, logsAsync, habitType, options),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Text('Error: $e'),
      );
    }
    return _buildHeatmap(context, logsAsync, habitType, []);
  }

  Widget _buildHeatmap(BuildContext context, AsyncValue<List<Log>> logsAsync, HabitType habitType, List<EnumOption> enumOptions) {
    return logsAsync.when(
      data: (logs) {
        final logMap = {for (var log in logs) stripTime(log.date): log};
        
        final datasets = _transformLogsToHeatmapDatasets(logs, habitType, enumOptions);
        final colorsets = _buildHeatmapColorsets(context, habitType, enumOptions);

        return HeatMap(
          datasets: datasets,
          colorMode: ColorMode.opacity,
          colorsets: colorsets,
          scrollable: true,
          startDate: DateTime.now().subtract(const Duration(days: 90)),
          endDate: DateTime.now(),
          showColorTip: false,
          size: 20,
          fontSize: 10,
          defaultColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          textColor: Theme.of(context).colorScheme.onSurface,
          onClick: isEditMode
              ? (date) {
                  if (date.isAfter(DateTime.now())) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Cannot edit future dates.')),
                    );
                  } else {
                    onDateClick(date, logMap[date]);
                  }
                }
              : null,
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Text('Error loading heatmap: $e'),
    );
  }

  // --- COLORS ---
  Map<int, Color> _buildHeatmapColorsets(BuildContext context, HabitType type, List<EnumOption> enumOptions) {
    // Enum: Specific colors
    if (type == HabitType.enumType) {
      return {for (var i = 0; i < enumOptions.length; i++) i + 1: Color(enumOptions[i].color)};
    }

    // Measurable OR Time: Generate 10 shades (Gradient)
    if (type == HabitType.measurable || type == HabitType.time) {
      final baseColor = habit.color != null 
          ? Color(habit.color!) 
          : Theme.of(context).colorScheme.primary;
      
      // Generate 10 steps of opacity
      return {
        1: baseColor.withOpacity(0.1),
        2: baseColor.withOpacity(0.2),
        3: baseColor.withOpacity(0.3),
        4: baseColor.withOpacity(0.4),
        5: baseColor.withOpacity(0.5),
        6: baseColor.withOpacity(0.6),
        7: baseColor.withOpacity(0.7),
        8: baseColor.withOpacity(0.8),
        9: baseColor.withOpacity(0.9),
        10: baseColor.withOpacity(1.0),
      };
    }

    // Boolean / Description: Single solid color
    return {
      1: habit.color != null 
          ? Color(habit.color!) 
          : Theme.of(context).colorScheme.primary
    };
  }

  // --- DATA ---
  Map<DateTime, int> _transformLogsToHeatmapDatasets(List<Log> logs, HabitType type, List<EnumOption> enumOptions) {
    final Map<DateTime, int> data = {};
    
    // For Measurable scaling
    double maxValue = 1.0;
    if (type == HabitType.measurable) {
      if (habit.targetValue != null && habit.targetValue! > 0) {
        maxValue = habit.targetValue!;
      } else {
        for (var log in logs) {
          final val = double.tryParse(log.value) ?? 0.0;
          if (val > maxValue) maxValue = val;
        }
      }
    }

    for (final log in logs) {
      final date = stripTime(log.date);
      int intensity = 0;

      switch (type) {
        case HabitType.boolean:
        case HabitType.description:
          intensity = 1;
          break;
          
        case HabitType.measurable:
          final value = double.tryParse(log.value) ?? 0.0;
          if (value <= 0) {
            intensity = 0;
          } else {
            double percentage = (value / maxValue);
            intensity = (percentage * 10).ceil().clamp(1, 10);
          }
          break;
          
        case HabitType.enumType:
          final index = enumOptions.indexWhere((opt) => opt.value == log.value);
          intensity = index != -1 ? index + 1 : 0;
          break;
          
        case HabitType.time:
          // Parse "HH:mm" -> Minutes -> Intensity (1-10)
          // 00:00 (0 min) -> 1 (Lightest)
          // 12:00 (720 min) -> 5
          // 23:59 (1439 min) -> 10 (Darkest)
          final parts = log.value.split(':');
          if (parts.length == 2) {
            final hour = int.tryParse(parts[0]) ?? 0;
            final minute = int.tryParse(parts[1]) ?? 0;
            final totalMinutes = (hour * 60) + minute;
            final maxMinutes = 24 * 60;
            
            // Map 0..1440 to 1..10
            double percentage = totalMinutes / maxMinutes;
            intensity = (percentage * 10).ceil().clamp(1, 10);
            
            // Ensure 00:00 still shows up as at least 1
            if (intensity == 0) intensity = 1;
          } else {
            intensity = 1; // Fallback
          }
          break;
      }

      if (intensity > 0) {
        data[date] = intensity;
      }
    }
    return data;
  }
}

class LogHistoryList extends ConsumerWidget {
  const LogHistoryList({super.key, required this.habit});
  final Habit habit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(logsForHabitProvider(habit.id));
    final habitType = HabitType.fromString(habit.type);

    return logsAsync.when(
      data: (logs) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final log = logs[index];
              if (habitType == HabitType.description) {
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(DateFormat.yMMMMEEEEd().format(log.date), style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: 8),
                        Text(log.value, style: Theme.of(context).textTheme.bodyLarge),
                      ],
                    ),
                  ),
                );
              }
              String trailingText = log.value;
              if (habitType == HabitType.time) {
                final parts = log.value.split(':');
                if (parts.length == 2) {
                  final time = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
                  trailingText = time.format(context);
                }
              }
              return ListTile(
                title: Text(DateFormat.yMMMd().format(log.date)),
                trailing: Text(trailingText, style: Theme.of(context).textTheme.bodyLarge),
              );
            },
            childCount: logs.length,
          ),
        ),
      ),
      loading: () => const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator())),
      error: (e, s) => SliverToBoxAdapter(child: Center(child: Text('Error: $e'))),
    );
  }
}
