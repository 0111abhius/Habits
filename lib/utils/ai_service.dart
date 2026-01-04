import 'package:google_generative_ai/google_generative_ai.dart';

class AIService {
  static const String _apiKey = 'AIzaSyBv2rachB-7SaruozBKSsai58sK1GxAY_k'; // Hardcoded for this session as requested

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
}
