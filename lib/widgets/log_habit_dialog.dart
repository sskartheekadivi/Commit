import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:commit/database/database.dart';
import 'package:commit/models/habit_type.dart';
import 'package:commit/providers/providers.dart';

class LogHabitDialog extends ConsumerStatefulWidget {
  const LogHabitDialog({
    super.key,
    required this.habit,
    this.date,
    this.log,
  });
  final Habit habit;
  final DateTime? date; // Date to log for, defaults to today
  final Log? log; // Existing log if editing

  @override
  ConsumerState<LogHabitDialog> createState() => _LogHabitDialogState();
}

class _LogHabitDialogState extends ConsumerState<LogHabitDialog> {
  late final TextEditingController _valueController;
  final _formKey = GlobalKey<FormState>();
  String? _selectedEnumValue;
  TimeOfDay? _selectedTime;

  bool get _isEditing => widget.log != null;

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController(text: _isEditing ? widget.log!.value : null);
    final habitType = HabitType.fromString(widget.habit.type);
    if (_isEditing) {
      if (habitType == HabitType.enumType) {
        _selectedEnumValue = widget.log!.value;
      } else if (habitType == HabitType.time) {
        final parts = widget.log!.value.split(':');
        if (parts.length == 2) {
          _selectedTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
      }
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final habitType = HabitType.fromString(widget.habit.type);

    return AlertDialog(
      title: Text('${_isEditing ? 'Edit' : 'Log'} "${widget.habit.name}"'),
      content: Form(
        key: _formKey,
        child: _buildInputField(habitType),
      ),
      actions: [
        if (_isEditing)
          TextButton(
            onPressed: _deleteLog,
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        const SizedBox(width: 8), // Use sized box instead of spacer
        TextButton(
          onPressed: () => context.pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _logHabit,
          child: Text(_isEditing ? 'Update' : 'Log'),
        ),
      ],
    );
  }

  Widget _buildInputField(HabitType type) {
    // ... (rest of the method is unchanged)
    switch (type) {
      case HabitType.measurable:
        return TextFormField(
          controller: _valueController,
          decoration: InputDecoration(labelText: 'Value', suffixText: widget.habit.unit),
          keyboardType: TextInputType.number,
          validator: (value) => (value == null || value.isEmpty || double.tryParse(value) == null) ? 'Enter a valid number' : null,
        );
      case HabitType.enumType:
        final optionsAsync = ref.watch(enumOptionsProvider(widget.habit.id));
        return optionsAsync.when(
          data: (options) {
            // Ensure the initial value is valid
            if (options.isNotEmpty && !options.any((o) => o.value == _selectedEnumValue)) {
              _selectedEnumValue = null;
            }
            return DropdownButtonFormField<String>(
              value: _selectedEnumValue,
              decoration: const InputDecoration(labelText: 'Status'),
              items: options.map((opt) => DropdownMenuItem(value: opt.value, child: Text(opt.value))).toList(),
              onChanged: (value) => setState(() => _selectedEnumValue = value),
              validator: (value) => value == null ? 'Please select an option' : null,
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => Text('Error: $e'),
        );
      case HabitType.description:
        return TextFormField(
          controller: _valueController,
          decoration: const InputDecoration(labelText: 'Journal Entry / Description'),
          maxLines: 3,
          validator: (value) => (value == null || value.isEmpty) ? 'Please enter a value' : null,
        );
      case HabitType.time:
        return ListTile(
          title: const Text('Time'),
          subtitle: Text(_selectedTime?.format(context) ?? 'Select Time'),
          trailing: const Icon(Icons.access_time),
          onTap: () async {
            final TimeOfDay? picked = await showTimePicker(
              context: context,
              initialTime: _selectedTime ?? TimeOfDay.now(),
            );
            if (picked != null) {
              setState(() => _selectedTime = picked);
            }
          },
        );
      case HabitType.boolean:
        return const SizedBox.shrink(); // Should not be reachable
    }
  }

  Future<void> _deleteLog() async {
    final repo = ref.read(habitRepositoryProvider);
    final logDate = widget.date ?? DateTime.now();
    try {
      await repo.clearHabitLog(widget.habit.id, logDate);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete log: $e')),
        );
      }
    }
  }

  Future<void> _logHabit() async {
    if (!_formKey.currentState!.validate()) return;
    if (HabitType.fromString(widget.habit.type) == HabitType.time && _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a time.')));
      return;
    }

    final repo = ref.read(habitRepositoryProvider);
    final habitType = HabitType.fromString(widget.habit.type);
    final String value;
    switch (habitType) {
      case HabitType.enumType:
        value = _selectedEnumValue!;
        break;
      case HabitType.time:
        value = '${_selectedTime!.hour}:${_selectedTime!.minute}';
        break;
      default:
        value = _valueController.text;
    }
    final logDate = widget.date ?? DateTime.now();

    try {
      if (_isEditing) {
        await repo.updateLog(widget.log!, value);
      } else {
        await repo.createLog(widget.habit.id, logDate, value);
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: Could not save log. Please try again.')),
        );
      }
    }
  }
}
