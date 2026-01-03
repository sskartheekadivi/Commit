/// Returns a new [DateTime] instance with the time portion stripped out,
/// leaving only the year, month, and day.
DateTime stripTime(DateTime dateTime) {
  return DateTime(dateTime.year, dateTime.month, dateTime.day);
}
