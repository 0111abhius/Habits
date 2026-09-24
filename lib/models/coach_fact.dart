class CoachFact {
  final String text;
  final String source;
  final FactCategory category;

  const CoachFact({
    required this.text,
    required this.source,
    required this.category,
  });
}

enum FactCategory {
  planning,
  retrospective,
  wellness,
  productivity,
}
