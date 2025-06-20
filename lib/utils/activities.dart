// New utilities for activities naming
const List<String> kDefaultActivities = [
  'Sleep',
  'Work',
  'Exercise',
  'Study',
  'Social',
  'Meal',
  'Hobby',
  'Other',
];

const Map<String, String> kActivityEmoji = {
  'Sleep': '😴',
  'Work': '💼',
  'Exercise': '🏋️',
  'Study': '📚',
  'Social': '🎉',
  'Meal': '🍽️',
  'Hobby': '🎨',
  'Other': '❓',
};

String displayActivity(String act) {
  final emoji = kActivityEmoji[act];
  return emoji != null ? '$emoji $act' : act;
} 