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
import 'package:drift/drift.dart' hide Column;
import 'package:collection/collection.dart';

// --- MODELS ---
class CategoryData {
  final Category category;
  final List<Habit> habits;
  CategoryData({required this.category, required this.habits});
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Commit', 
          style: TextStyle(
            fontWeight: FontWeight.w800, 
            letterSpacing: -0.5,
            color: Theme.of(context).colorScheme.onSurface,
          )
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: 'Archived Habits',
            onPressed: () => context.push('/archived'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton.filledTonal(
              icon: const Icon(Icons.add),
              tooltip: 'New General Habit',
              onPressed: () => _showAddHabitOptions(context, null),
            ),
          ),
        ],
      ),
      body: Consumer(
        builder: (context, ref, child) {
          final categoriesAsync = ref.watch(allCategoriesProvider);
          final allHabitsAsync = ref.watch(streamAllHabitsProvider);

          return categoriesAsync.when(
            data: (categories) {
              return allHabitsAsync.when(
                data: (allHabits) {
                  final List<CategoryData> categoryCards = [];

                  List<Habit> getHabits(int catId) => 
                      allHabits.where((h) => h.categoryId == catId).toList()
                      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

                  for (final cat in categories) {
                    categoryCards.add(CategoryData(category: cat, habits: getHabits(cat.id)));
                  }

                  return LayoutBuilder(builder: (context, constraints) {
                    final double statusCellWidth = (constraints.maxWidth * 0.55) / 7;
                    
                    return CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: HeaderRow(statusCellWidth: statusCellWidth),
                          ),
                        ),

                        SliverReorderableList(
                          itemCount: categoryCards.length,
                          onReorder: (oldIndex, newIndex) {
                            if (oldIndex < newIndex) newIndex -= 1;
                            final updatedCategories = List<Category>.from(categories);
                            final item = updatedCategories.removeAt(oldIndex);
                            updatedCategories.insert(newIndex, item);
                            ref.read(habitRepositoryProvider).updateCategoryOrder(updatedCategories);
                          },
                          itemBuilder: (context, index) {
                            final cardData = categoryCards[index];
                            return Padding(
                              key: ValueKey(cardData.category.id),
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                              child: ReorderableDragStartListener(
                                index: index,
                                child: _CategoryCard(
                                  data: cardData,
                                  statusCellWidth: statusCellWidth,
                                ),
                              ),
                            );
                          },
                        ),
                        
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Center(
                              child: TextButton.icon(
                                onPressed: () => _showAddCategoryDialog(context, ref),
                                icon: const Icon(Icons.create_new_folder_outlined),
                                label: const Text("Create New Category"),
                                style: TextButton.styleFrom(foregroundColor: Colors.grey),
                              ),
                            ),
                          ),
                        ),
                        
                        const SliverToBoxAdapter(child: SizedBox(height: 100)),
                      ],
                    );
                  });
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, s) => Center(child: Text('Error: $e')),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => const Center(child: Text('Error loading categories')),
          );
        },
      ),
    );
  }

  void _showAddCategoryDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Category'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Name', border: OutlineInputBorder()),
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                try {
                  await ref.read(habitRepositoryProvider).createCategory(controller.text.trim());
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  // Ignore duplication error
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

void _showAddHabitOptions(BuildContext context, int? categoryId) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Wrap(
        children: HabitType.values.map((type) => ListTile(
          leading: Icon(_getIconForHabitType(type)),
          title: Text(type.value),
          onTap: () {
            Navigator.of(context).pop();
            GoRouter.of(context).push('/create', extra: {'type': type, 'categoryId': categoryId});
          },
        )).toList(),
      ),
    ),
  );
}

IconData _getIconForHabitType(HabitType type) {
  switch (type) {
    case HabitType.boolean: return Icons.check_box_outlined;
    case HabitType.measurable: return Icons.straighten;
    case HabitType.enumType: return Icons.format_list_bulleted;
    case HabitType.description: return Icons.notes;
    case HabitType.time: return Icons.access_time;
  }
}

class _CategoryCard extends ConsumerWidget {
  final CategoryData data;
  final double statusCellWidth;

  const _CategoryCard({required this.data, required this.statusCellWidth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isGeneral = data.category.name == 'General';

    return DragTarget<Habit>(
      onAcceptWithDetails: (details) {
        final habit = details.data;
        if (habit.categoryId == data.category.id) return;
        ref.read(habitRepositoryProvider).moveHabitToCategory(habit, data.category.id, data.habits.length);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isHovering ? colorScheme.primaryContainer.withOpacity(0.3) : colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: isHovering 
                ? Border.all(color: colorScheme.primary, width: 2) 
                : Border.all(color: Colors.transparent, width: 2),
            boxShadow: [
              if (!isHovering)
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
            ]
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(
                  children: [
                    Icon(Icons.drag_indicator, size: 16, color: colorScheme.onSurfaceVariant.withOpacity(0.3)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        data.category.name, 
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                      ),
                    ),
                    _buildCountBadge(context, data.habits.length),
                    _buildMenu(context, ref, data.category, isGeneral),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 0.5),
              
              // List
              if (data.habits.isEmpty)
                 Padding(
                   padding: const EdgeInsets.all(12.0),
                   child: Center(
                     child: Text("Drop habits here", style: TextStyle(color: colorScheme.outline, fontSize: 12)),
                   ),
                 )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: data.habits.length,
                  itemBuilder: (context, index) {
                    return _DraggableHabitRow(
                      habit: data.habits[index], 
                      index: index, 
                      categoryId: data.category.id,
                      statusCellWidth: statusCellWidth
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCountBadge(BuildContext context, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text("$count", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
    );
  }

  Widget _buildMenu(BuildContext context, WidgetRef ref, Category category, bool isGeneral) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      padding: EdgeInsets.zero,
      onSelected: (value) {
         if (value == 'add') _showAddHabitOptions(context, category.id);
         if (value == 'rename') _showRenameDialog(context, ref, category);
         if (value == 'archive') ref.read(habitRepositoryProvider).archiveCategory(category.id);
         if (value == 'delete') ref.read(habitRepositoryProvider).deleteCategory(category.id, false);
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'add', height: 32, child: Text('Add Habit', style: TextStyle(fontSize: 13))),
        const PopupMenuItem(value: 'rename', height: 32, child: Text('Rename', style: TextStyle(fontSize: 13))),
        const PopupMenuItem(value: 'archive', height: 32, child: Text('Archive', style: TextStyle(fontSize: 13))),
        if (!isGeneral) const PopupMenuItem(value: 'delete', height: 32, child: Text('Delete', style: TextStyle(fontSize: 13, color: Colors.red))),
      ],
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, Category category) {
    final controller = TextEditingController(text: category.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: controller, autofocus: true, textCapitalization: TextCapitalization.sentences),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                ref.read(habitRepositoryProvider).updateCategory(category.copyWith(name: controller.text.trim()));
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _DraggableHabitRow extends ConsumerWidget {
  final Habit habit;
  final int index;
  final int categoryId;
  final double statusCellWidth;

  const _DraggableHabitRow({
    required this.habit,
    required this.index,
    required this.categoryId,
    required this.statusCellWidth,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DragTarget<Habit>(
      onWillAcceptWithDetails: (details) => details.data.id != habit.id,
      onAcceptWithDetails: (details) => ref.read(habitRepositoryProvider).moveHabitToCategory(details.data, categoryId, index),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return Column(
          children: [
            if (isHovering) Container(height: 2, color: Theme.of(context).colorScheme.primary, margin: const EdgeInsets.symmetric(vertical: 2)),
            LongPressDraggable<Habit>(
              data: habit,
              feedback: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.9,
                  child: Card(elevation: 6, child: Padding(padding: const EdgeInsets.all(2), child: HabitRow(habit: habit, statusCellWidth: statusCellWidth))),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.3, child: SizedBox(height: 40)),
              child: Card(
                elevation: 0, 
                color: Theme.of(context).colorScheme.surface,
                margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: HabitRow(habit: habit, statusCellWidth: statusCellWidth),
              ),
            ),
          ],
        );
      },
    );
  }
}

class HeaderRow extends StatelessWidget {
  const HeaderRow({super.key, required this.statusCellWidth});
  final double statusCellWidth;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Row(
      children: [
        const SizedBox(width: 12),
        const Expanded(flex: 3, child: Text('HABIT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: Colors.grey))),
        ...List.generate(7, (index) {
          final date = today.subtract(Duration(days: 6 - index));
          final isToday = index == 6; 
          return SizedBox(
            width: statusCellWidth,
            child: Column(
              children: [
                Text(DateFormat.d().format(date), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isToday ? Theme.of(context).colorScheme.primary : null)),
                Text(DateFormat.E().format(date).substring(0, 1), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isToday ? Theme.of(context).colorScheme.primary : Colors.grey)),
              ],
            ),
          );
        }),
        const SizedBox(width: 6),
      ],
    );
  }
}

class HabitRow extends StatelessWidget {
  const HabitRow({super.key, required this.habit, required this.statusCellWidth});
  final Habit habit;
  final double statusCellWidth;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: () => context.push('/details/${habit.id}'),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 12.0),
                alignment: Alignment.centerLeft,
                child: Text(
                  habit.name,
                  maxLines: 2, 
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: habit.color != null ? Color(habit.color!) : null, fontWeight: FontWeight.w600, fontSize: 13, height: 1.1),
                ),
              ),
            ),
          ),
          ...List.generate(7, (index) {
            final date = DateTime.now().subtract(Duration(days: 6 - index));
            return SizedBox(width: statusCellWidth, child: StatusCell(habit: habit, date: date, size: statusCellWidth));
          }),
        ],
      ),
    );
  }
}

// --- FIXED STATUS CELL WITH LOCAL LOCK AND DIRECT TIME PICKER ---
class StatusCell extends ConsumerStatefulWidget {
  const StatusCell({super.key, required this.habit, required this.date, required this.size});
  final Habit habit;
  final DateTime date;
  final double size;

  @override
  ConsumerState<StatusCell> createState() => _StatusCellState();
}

class _StatusCellState extends ConsumerState<StatusCell> {
  bool _isProcessing = false; // Local lock

  @override
  Widget build(BuildContext context) {
    final logAsync = ref.watch(logForHabitOnDateProvider(widget.habit.id, widget.date));
    final habitType = HabitType.fromString(widget.habit.type);
    
    final today = DateTime.now();
    final isFutureDate = widget.date.isAfter(today.copyWith(hour: 23, minute: 59, second: 59));

    return GestureDetector(
      onTap: (isFutureDate || _isProcessing) ? null : () => _handleTap(context, habitType, logAsync),
      child: Opacity(
        opacity: isFutureDate ? 0.3 : 1.0,
        child: Container(
          color: Colors.transparent,
          alignment: Alignment.center,
          child: logAsync.when(
            skipLoadingOnReload: true,
            data: (log) => _buildContent(log, habitType),
            loading: () => const SizedBox(),
            error: (e, s) => Icon(Icons.error, color: Colors.red, size: widget.size * 0.5),
          ),
        ),
      ),
    );
  }

  Future<void> _handleTap(BuildContext context, HabitType type, AsyncValue<Log?> logAsync) async {
    setState(() => _isProcessing = true); // Lock UI
    final repo = ref.read(habitRepositoryProvider);
    final currentLog = logAsync.valueOrNull;

    try {
      if (type == HabitType.boolean) {
        if (currentLog == null) {
           await repo.createLog(widget.habit.id, widget.date, 'TRUE');
        } else {
           await repo.clearHabitLog(widget.habit.id, widget.date);
        }
      } else if (type == HabitType.time) {
        // DIRECT TIME PICKER - No Dialog
        if (currentLog == null) {
          final now = TimeOfDay.now();
          final time = await showTimePicker(context: context, initialTime: now);
          if (time != null) {
             final formatted = '${time.hour.toString().padLeft(2,'0')}:${time.minute.toString().padLeft(2,'0')}';
             await repo.createLog(widget.habit.id, widget.date, formatted);
          }
        } else {
          // If already logged, show dialog to edit/clear
          if (mounted) {
             await showDialog(
              context: context,
              builder: (context) => LogHabitDialog(habit: widget.habit, date: widget.date, log: currentLog),
            );
          }
        }
      } else {
        // Measurable / Enum / Description
        if (mounted) {
          await showDialog(
            context: context,
            builder: (context) => LogHabitDialog(habit: widget.habit, date: widget.date, log: currentLog),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Update failed')));
    } finally {
      if (mounted) setState(() => _isProcessing = false); // Unlock UI
    }
  }

  Widget _buildContent(Log? log, HabitType type) {
    final theme = Theme.of(context);
    final circleSize = widget.size * 0.65;

    // Time text
    if (type == HabitType.time && log != null) {
       return Text(log.value, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold));
    }

    // Measurable text
    if (type == HabitType.measurable) {
      if (log == null) return Text('—', style: TextStyle(fontSize: 10, color: theme.colorScheme.outline.withOpacity(0.5)));
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(log.value, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
          if (widget.habit.unit != null) Text(widget.habit.unit!, style: TextStyle(fontSize: 7, color: theme.colorScheme.outline)),
        ],
      );
    }

    // Colored Circle (Boolean / Enum / Time placeholder)
    Color? fillColor;
    if (log != null) {
      if (type == HabitType.boolean || type == HabitType.description || type == HabitType.time) {
        fillColor = Color(widget.habit.color ?? theme.colorScheme.primary.value);
      } else if (type == HabitType.enumType) {
        final enumOptions = ref.read(enumOptionsProvider(widget.habit.id)).valueOrNull ?? [];
        final option = enumOptions.firstWhereOrNull((opt) => opt.value == log.value);
        fillColor = option != null ? Color(option.color) : theme.colorScheme.primary;
      }
    }

    return Container(
      height: circleSize,
      width: circleSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fillColor,
        border: Border.all(
          color: fillColor ?? theme.colorScheme.outline.withOpacity(0.3),
          width: 1
        ),
      ),
      child: _isProcessing ? const Padding(padding: EdgeInsets.all(4), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : null,
    );
  }
}
