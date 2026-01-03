enum HabitType {
  boolean('Boolean'),
  measurable('Measurable'),
  enumType('Enum'),
  description('Description');

  const HabitType(this.value);
  final String value;

  static HabitType fromString(String value) {
    switch (value) {
      case 'Boolean':
        return HabitType.boolean;
      case 'Measurable':
        return HabitType.measurable;
      case 'Enum':
        return HabitType.enumType;
      case 'Description':
        return HabitType.description;
      default:
        throw ArgumentError('Invalid HabitType value: $value');
    }
  }
}
