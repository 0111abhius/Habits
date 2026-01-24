class AIProposal {
  final String activity;
  final String reason;
  final bool isTask;
  final String? taskTitle;

  const AIProposal({required this.activity, required this.reason, this.isTask = false, this.taskTitle});
}
