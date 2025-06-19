// New file with shared category constants and helpers
const List<String> kDefaultCategories = [
  'Sleep',
  'Work',
  'Exercise',
  'Study',
  'Social',
  'Meal',
  'Hobby',
  'Other',
];

const Map<String, String> kCategoryEmoji = {
  'Sleep': '😴',
  'Work': '💼',
  'Exercise': '🏋️',
  'Study': '📚',
  'Social': '🎉',
  'Meal': '🍽️',
  'Hobby': '🎨',
  'Other': '❓',
};

String displayCategory(String cat) {
  final emoji = kCategoryEmoji[cat];
  return emoji != null ? '$emoji $cat' : cat;
} 