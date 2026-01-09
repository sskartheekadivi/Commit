enum HabitType {
  boolean('Boolean'),
  measurable('Measurable'),
  enumType('Enum'),
  description('Description'),
  time('Time');

  const HabitType(this.value);
  final String value;

  static HabitType fromString(String value) {
    for (final type in HabitType.values) {
      if (type.value == value) {
        return type;
      }
    }
    throw ArgumentError('Invalid HabitType value: $value');
  }
}

