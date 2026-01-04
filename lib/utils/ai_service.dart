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

Please keep the response concise, encouraging, and focused on the goal. Analyze the time gaps and activity choices.
''';

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      return response.text ?? 'No suggestions available at this time.';
    } catch (e) {
      return 'Failed to get insights: $e';
    }
  }
}
