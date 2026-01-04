import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:commit/database/database.dart';
import 'package:commit/models/habit_type.dart';
import 'package:commit/providers/providers.dart';
import 'package:commit/repositories/habit_repository.dart';

// Top-level widget for the color palette
class CustomColorPalette extends StatefulWidget {
  final List<Color> colors;
  final Color selectedColor;
  final ValueChanged<Color> onColorSelected;
  final VoidCallback onCustomTap;

  const CustomColorPalette({
    super.key,
    required this.colors,
    required this.selectedColor,
    required this.onColorSelected,
    required this.onCustomTap,
  });

  @override
  _CustomColorPaletteState createState() => _CustomColorPaletteState();
}

class _CustomColorPaletteState extends State<CustomColorPalette> {
  late Color _currentColor;

  @override
  void initState() {
    super.initState();
    _currentColor = widget.selectedColor;
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true, // Allow the GridView to take only as much space as its children need
      physics: const NeverScrollableScrollPhysics(), // Disable GridView's own scrolling
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 14),
      itemCount: widget.colors.length,
      itemBuilder: (context, index) {
        final color = widget.colors[index];
        return GestureDetector(
          onTap: () {
            setState(() => _currentColor = color);
            widget.onColorSelected(color);
          },
          child: Container(
                   margin: const EdgeInsets.all(2), // Original margin for grid items
                   decoration: BoxDecoration(
                     color: color,
                     shape: BoxShape.circle,
                     border: Border.all(
                       color: _currentColor == color ? Colors.white : Colors.transparent,
                       width: 2,
                       ),
                     ),
                   ),
          );
      },
    );
  }
}


class _EnumOptionState {
  final TextEditingController controller;
  Color color;
  final Key key;
  _EnumOptionState({required this.controller, required this.color, required this.key});
}

class CreateEditHabitScreen extends ConsumerStatefulWidget {
  const CreateEditHabitScreen({super.key, this.habit, this.preselectedType});
  final Habit? habit;
  final HabitType? preselectedType;

  @override
  ConsumerState<CreateEditHabitScreen> createState() => _CreateEditHabitScreenState();
}

class _CreateEditHabitScreenState extends ConsumerState<CreateEditHabitScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late HabitType _selectedType;
  late Color _habitColor;
  late final TextEditingController _targetValueController;
  late final TextEditingController _unitController;
  late final TextEditingController _notificationTextController;
  final List<_EnumOptionState> _enumOptions = [];
  bool _isLoading = false;

  // Notification state
  bool _remindMe = false;
  TimeOfDay? _selectedTime;
  final Set<int> _selectedDays = {}; // 1-7 for Mon-Sun

  bool get _isEditing => widget.habit != null;
  bool get _isTypePreselected => widget.preselectedType != null;

  List<Color> _paletteColors = [];

  @override
  void initState() {
    super.initState();
    _selectedType = widget.preselectedType ?? (_isEditing ? HabitType.fromString(widget.habit!.type) : HabitType.boolean);
    _nameController = TextEditingController(text: widget.habit?.name);
    _habitColor = _isEditing && widget.habit!.color != null ? Color(widget.habit!.color!) : Colors.blue;
    _targetValueController = TextEditingController(text: widget.habit?.targetValue?.toString());
    _unitController = TextEditingController(text: widget.habit?.unit);
    _notificationTextController = TextEditingController(text: widget.habit?.notificationText);

    if (_isEditing) {
      if (widget.habit!.reminderHour != null && widget.habit!.reminderMinute != null) {
        _remindMe = true;
        _selectedTime = TimeOfDay(hour: widget.habit!.reminderHour!, minute: widget.habit!.reminderMinute!);
      }
      if (widget.habit!.reminderDays != null && widget.habit!.reminderDays!.isNotEmpty) {
        _selectedDays.addAll(widget.habit!.reminderDays!.split(',').map((e) => int.parse(e)));
      }
      if (_selectedType == HabitType.enumType) {
        _loadExistingEnumOptions();
      }
    }
    _loadPaletteColors();
  }

  void _loadExistingEnumOptions() async {
    setState(() => _isLoading = true);
    final options = await ref.read(habitRepositoryProvider).getEnumOptionsForHabit(widget.habit!.id);
    for (final option in options) {
      _enumOptions.add(_EnumOptionState(
        controller: TextEditingController(text: option.value),
        color: Color(option.color),
        key: UniqueKey(),
      ));
    }
    setState(() => _isLoading = false);
  }

  void _loadPaletteColors() async {
    try {
      final colorsHex = await DefaultAssetBundle.of(context).loadString('assets/colors.txt');
      setState(() {
        _paletteColors = colorsHex
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .map((s) => Color(int.parse(s.substring(1), radix: 16) + 0xFF000000))
            .toList();
      });
    } catch (e) {
      print("Failed to load colors.txt: $e");
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetValueController.dispose();
    _unitController.dispose();
    _notificationTextController.dispose();
    for (final option in _enumOptions) {
      option.controller.dispose();
    }
    super.dispose();
  }

  void _pickColor(Function(Color) onColorPicked, Color initialColor) {
    Color pickerColor = initialColor; // Make pickerColor mutable within this scope

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Allow the bottom sheet to be full screen
      builder: (context) {
        return StatefulBuilder( // Use StatefulBuilder to update pickerColor reactively within bottom sheet
          builder: (BuildContext context, StateSetter setModalState) {
            return SingleChildScrollView( // Ensure content is scrollable if it exceeds screen height
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom), // Adjust for keyboard
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min, // Take minimum space vertically
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Pick a color', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9), // Max 90% of screen width
                      child: CustomColorPalette(
                        colors: _paletteColors,
                        selectedColor: pickerColor,
                        onColorSelected: (color) {
                          setModalState(() => pickerColor = color); // Update local state for selection indicator
                        },
                        onCustomTap: () {
                          Navigator.of(context).pop(); // Close bottom sheet
                          _showColorWheel(onColorPicked, pickerColor); // Open custom color picker
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          child: const Text('Cancel'),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        TextButton( // The Custom Color button
                          child: const Text('Custom Color'),
                          onPressed: () {
                            Navigator.of(context).pop(); // Close bottom sheet
                            _showColorWheel(onColorPicked, pickerColor); // Open custom color picker
                          },
                        ),
                        ElevatedButton(
                          child: const Text('Select'),
                          onPressed: () {
                            onColorPicked(pickerColor);
                            Navigator.of(context).pop(); // Close bottom sheet
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showColorWheel(Function(Color) onColorPicked, Color initialColor) {
    Color pickerColor = initialColor;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick a custom color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (color) => pickerColor = color,
          ),
        ),
        actions: <Widget>[
          ElevatedButton(
            child: const Text('Select'),
            onPressed: () {
              onColorPicked(pickerColor);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  void _pickColorForOption(Key key) {
    final optionIndex = _enumOptions.indexWhere((opt) => opt.key == key);
    if (optionIndex == -1) return;

    _pickColor((color) => setState(() => _enumOptions[optionIndex].color = color), _enumOptions[optionIndex].color);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Habit' : 'Create Habit'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildNameAndColorRow(),
                    const SizedBox(height: 20),
                    if (_isTypePreselected)
                      Text('Type: ${_selectedType.value}', style: Theme.of(context).textTheme.titleMedium)
                    else if (!_isEditing) ...[
                      DropdownButtonFormField<HabitType>(
                        value: _selectedType,
                        decoration: const InputDecoration(labelText: 'Habit Type'),
                        items: HabitType.values.map((type) => DropdownMenuItem(value: type, child: Text(type.value))).toList(),
                        onChanged: (HabitType? newValue) {
                          if (newValue != null) setState(() => _selectedType = newValue);
                        },
                      ),
                    ],
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _notificationTextController,
                      decoration: const InputDecoration(
                        labelText: 'Notification Text (Optional)',
                        hintText: 'e.g., Time to drink water!',
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildReminderSection(),
                    if (_selectedType == HabitType.measurable) _buildMeasurableFields(),
                    if (_selectedType == HabitType.enumType) _buildEnumFields(),
                    const SizedBox(height: 32),
                    ElevatedButton(onPressed: _saveHabit, child: const Text('Save')),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildReminderSection() {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Remind me'),
          value: _remindMe,
          onChanged: (bool value) async {
            if (value) {
              // Request permissions when the switch is turned on
              await ref.read(notificationServiceProvider).requestPermissions();
            }
            setState(() {
              _remindMe = value;
              if (!value) {
                _selectedTime = null;
                _selectedDays.clear();
              }
            });
          },
        ),
        if (_remindMe) ...[
          ListTile(
            title: const Text('Reminder Time'),
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
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Wrap(
              spacing: 8.0,
              children: List.generate(7, (index) {
                final day = index + 1; // 1 = Monday, 7 = Sunday
                final dayInitial = ['M', 'T', 'W', 'T', 'F', 'S', 'S'][index];
                final isSelected = _selectedDays.contains(day);
                return ChoiceChip(
                  label: Text(dayInitial),
                  selected: isSelected,
                  onSelected: (bool selected) {
                    setState(() {
                      if (selected) {
                        _selectedDays.add(day);
                      } else {
                        _selectedDays.remove(day);
                      }
                    });
                  },
                );
              }),
            ),
          )
        ],
      ],
    );
  }

  Widget _buildNameAndColorRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Habit Name'),
            validator: (value) => (value == null || value.isEmpty) ? 'Please enter a name' : null,
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () => _pickColor((color) => setState(() => _habitColor = color), _habitColor),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: _habitColor, borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _buildMeasurableFields() {
    return Column(
      children: [
        const SizedBox(height: 20),
        TextFormField(
          controller: _targetValueController,
          decoration: const InputDecoration(labelText: 'Target Value'),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _unitController,
          decoration: const InputDecoration(labelText: 'Unit (e.g., km, pages)'),
        ),
      ],
    );
  }

  Widget _buildEnumFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text('Enum Options', style: Theme.of(context).textTheme.titleMedium),
        ..._enumOptions.map((option) => _buildEnumOptionRow(option)).toList(),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add Option'),
          onPressed: _addEnumOption,
        ),
      ],
    );
  }

  void _addEnumOption() {
    final randomColor = Colors.primaries[Random().nextInt(Colors.primaries.length)];
    setState(() {
      _enumOptions.add(_EnumOptionState(
        controller: TextEditingController(),
        color: randomColor,
        key: UniqueKey(),
      ));
    });
  }

  void _removeEnumOption(Key key) {
    setState(() {
      final optionIndex = _enumOptions.indexWhere((opt) => opt.key == key);
      if (optionIndex != -1) {
        _enumOptions[optionIndex].controller.dispose();
        _enumOptions.removeAt(optionIndex);
      }
    });
  }

  Widget _buildEnumOptionRow(_EnumOptionState option) {
    return Row(
      key: option.key,
      children: [
        GestureDetector(
          onTap: () => _pickColorForOption(option.key),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: option.color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: option.controller,
            decoration: const InputDecoration(labelText: 'Value'),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Cannot be empty';
              final otherValues = _enumOptions
                  .where((opt) => opt.key != option.key)
                  .map((opt) => opt.controller.text.trim().toLowerCase());
              if (otherValues.contains(value.trim().toLowerCase())) return 'Duplicate value';
              return null;
            },
          ),
        ),
        IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _removeEnumOption(option.key)),
      ],
    );
  }

  Future<void> _saveHabit() async {
    if (!_formKey.currentState!.validate()) return;
     if (_selectedType == HabitType.enumType && _enumOptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add at least one enum option.')));
      return;
    }

    final repo = ref.read(habitRepositoryProvider);
    final name = _nameController.text;
    final notificationText = _notificationTextController.text;
    final targetValue = _targetValueController.text.isNotEmpty ? double.tryParse(_targetValueController.text) : null;
    final unit = _unitController.text.isNotEmpty ? _unitController.text : null;
    final enumOptionsData = _enumOptions.map((opt) => EnumOptionData(value: opt.controller.text, color: opt.color.value,)).toList();

    // Notification data
    final int? reminderHour = _remindMe ? _selectedTime?.hour : null;
    final int? reminderMinute = _remindMe ? _selectedTime?.minute : null;
    final String? reminderDays = _remindMe && _selectedDays.isNotEmpty 
      ? (_selectedDays.toList()..sort()).join(',') 
      : null;

    try {
      if (_isEditing) {
        final companion = HabitsCompanion(
          id: Value(widget.habit!.id),
          name: Value(name),
          type: Value(_selectedType.value),
          color: Value(_habitColor.value),
          notificationText: Value(notificationText),
          targetValue: Value(targetValue),
          unit: Value(unit),
          reminderHour: Value(reminderHour),
          reminderMinute: Value(reminderMinute),
          reminderDays: Value(reminderDays),
        );
        await repo.updateHabit(
          companion: companion,
          enumOptions: enumOptionsData,
        );
      } else {
        await repo.createHabit(
          name: name,
          type: _selectedType,
          color: _habitColor.value,
          notificationText: notificationText,
          targetValue: targetValue,
          unit: unit,
          enumOptions: enumOptionsData,
          reminderHour: reminderHour,
          reminderMinute: reminderMinute,
          reminderDays: reminderDays,
        );
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save habit: ${e.toString()}')));
      }
    }
  }

  Future<void> _archiveHabit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive Habit?'),
        content: const Text('Are you sure? This will hide the habit from your main list.'),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => context.pop(true), child: const Text('Archive')),
        ],
      ),
    );

    if (confirmed == true && widget.habit != null) {
      await ref.read(habitRepositoryProvider).archiveHabit(widget.habit!.id);
      if (mounted) context.go('/');
    }
  }
}
