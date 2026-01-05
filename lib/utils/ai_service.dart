import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AIService {
  // Now using secured API key from .env
  static String get _apiKey {
    final key = dotenv.env['GEMINI_API_KEY'];
    if (key == null || key.isEmpty) {
      throw Exception('API Key not found. Please ensure assets/env file is present and GEMINI_API_KEY is set.');
    }
    return key;
  }

  final GenerativeModel _model;

  AIService() : _model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _apiKey);

  Future<String> getInsights({required String logs, required String goal}) async {
    final prompt = '''
You are a productivity expert. I will provide you with a log of my activities for a specific period and a goal I want to achieve.
Please analyze my schedule and provide specific, actionable suggestions on how I can better spend my time to achieve my goal.

GOAL: $goal

ACTIVITY LOGS:
$logs

Please keep the response concise, encouraging, and focused on the goal. 
Analyze the time gaps and activity choices.
Pay special attention to where my 'Actual' activity differed from my 'Planned' activity, and offer specific advice on how to stick to the plan better or adjust the plan to be more realistic.
''';

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      return response.text ?? 'No suggestions available at this time.';
    } catch (e) {
      return 'Failed to get insights: $e';
    }
    }

  /// Centralized logic to robustly detect new activities from AI response.
  /// It combines the AI's explicit 'newActivities' list with any activities found in 'schedule'
  /// that are not present in 'existingActivities' (and not 'Sleep').
  static List<String> detectNewActivities(Map<String, dynamic> aiResponseData, List<String> existingActivities) {
    final schedule = Map<String, String>.from(aiResponseData['schedule'] ?? {});
    final aiSuggestedNew = List<String>.from(aiResponseData['newActivities'] ?? []);
    final Set<String> detectedNew = {};

    // Add explicit AI suggestions
    detectedNew.addAll(aiSuggestedNew);

    // Scan schedule for any other unknown activities
    for (final act in schedule.values) {
      if (act.isNotEmpty && !existingActivities.contains(act) && act != 'Sleep') {
        detectedNew.add(act);
      }
    }
    return detectedNew.toList();
  }

  Future<String> getTemplateSuggestions({
    required String currentTemplate,
    required String goal,
    required List<String> existingActivities,
  }) async {
    final prompt = '''
You are a productivity expert assisting in creating a daily schedule template.
The user has a specific goal in mind and may have already filled in parts of the template.
Please analyze the current template (if any) and the goal, then provide specific, actionable suggestions.
If the template is empty, suggest a full schedule.
If the template is partially filled, suggest how to fill the gaps or optimize existing blocks to better achieve the goal.

GOAL: $goal

EXISTING ACTIVITIES (reuse these if possible):
${existingActivities.join(', ')}

CURRENT TEMPLATE DRAFT:
$currentTemplate

IMPORTANT: You must return the response in strict JSON format.
The JSON must have this structure:
{
  "schedule": {
    "08:00": "Activity Name",
    "09:30": "Activity Name"
  },
  "newActivities": ["New Activity 1", "New Activity 2"],
  "reasoning": "Explanation of the schedule..."
}
"schedule" keys must be "HH:mm" strings (24-hour format). 
"newActivities" should list any activities suggested that are NOT in the EXISTING ACTIVITIES list.
"reasoning" should be a concise summary of the plan.
Do not wrap the JSON in markdown code blocks. Just return the raw JSON string.
''';

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      var text = response.text ?? '{}';
      // simple cleanup if model wrapped it in markdown
      text = text.replaceAll('```json', '').replaceAll('```', '').trim();
      return text;
    } catch (e) {
      return '{"error": "$e"}';
    }
  }

  Future<String> getDayPlanSuggestions({
    required String currentPlan,
    required String goal,
    required List<String> existingActivities,
  }) async {
    final prompt = '''
You are a productivity expert assisting in planning a specific day.
The user has a specific goal for today and possibly some already planned activities.
Please analyze the current plan (if any) and the goal, then provide specific, actionable suggestions.
Optimize the schedule to achieve the goal while respecting existing hard commitments if they seem important (or suggest moving them if necessary).

GOAL: $goal

EXISTING ACTIVITIES (Strictly reuse these if they fit):
${existingActivities.map((e) => '"$e"').join(', ')}

CURRENT PLAN FOR TODAY:
$currentPlan

IMPORTANT: You must return the response in strict JSON format.
The JSON must have this structure:
{
  "schedule": {
    "08:00": "Activity Name",
    "09:30": "Activity Name"
  },
  "newActivities": ["New Activity 1", "New Activity 2"],
  "reasoning": "Explanation of the changes..."
}
"schedule" keys must be "HH:mm" strings (24-hour format). 
"newActivities" should list any activities suggested that are NOT in the EXISTING ACTIVITIES list.
"reasoning" should be a concise summary of the plan.
Do not wrap the JSON in markdown code blocks. Just return the raw JSON string.
''';

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      var text = response.text ?? '{}';
      text = text.replaceAll('```json', '').replaceAll('```', '').trim();
      return text;
    } catch (e) {
      return '{"error": "$e"}';
    }
  }
  // --- Interactive Chat & Refinement ---

  /// Creates a stateful chat session for continuous interaction (e.g. Analytics)
  ChatSession createChatSession() {
    return _model.startChat();
  }

  /// Sends a refinement request to the AI to modify an existing JSON schedule.
  /// [currentJson] is the full JSON string of the current plan.
  /// [userRequest] is the free-form text (e.g. "Make morning more relaxing").
  /// Returns updated JSON string.
  Future<String> refinePlanJSON({
    required String currentJson,
    required String userRequest,
    required List<String> existingActivities,
  }) async {
    final prompt = '''
You are a scheduling assistant. 
I will provide a JSON schedule and a user request to modify it.
Update the schedule based on the request.
Maintain the exact same JSON structure.
Do not lose existing valid activities unless asked to remove them.

CURRENT JSON:
$currentJson

USER REQUEST: 
"$userRequest"

EXISTING ACTIVITIES (reuse if relevant):
${existingActivities.map((e) => '"$e"').join(', ')}

IMPORTANT: Return ONLY valid JSON. No markdown.
Structure:
{
  "schedule": { "HH:mm": "Activity" },
  "newActivities": [...],
  "reasoning": "Brief explanation of changes"
}
''';

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      var text = response.text ?? '{}';
      text = text.replaceAll('```json', '').replaceAll('```', '').trim();
      return text;
    } catch (e) {
      return '{"error": "$e"}';
    }
  }
}
