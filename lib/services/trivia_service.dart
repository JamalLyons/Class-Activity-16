import 'package:http/http.dart' as http;

import '../models/question.dart';

enum QuestionFault { none, badJson, apiCode, nineResults }

class TriviaService {
  TriviaService({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _now = now ?? DateTime.now;
  final http.Client _client;
  final DateTime Function() _now;
  DateTime? _lastRequest;
  static final url = Uri.parse(
    'https://opentdb.com/api.php?amount=10&category=9&difficulty=easy&type=multiple',
  );

  Future<List<Question>> load({
    QuestionFault fault = QuestionFault.none,
  }) async {
    if (_lastRequest != null &&
        _now().difference(_lastRequest!) < const Duration(seconds: 5)) {
      throw const FormatException(
        'Wait at least five seconds between question requests.',
      );
    }
    _lastRequest = _now();
    if (fault == QuestionFault.badJson) return Question.parseResponse('{');
    if (fault == QuestionFault.apiCode) {
      return Question.parseResponse('{"response_code":1,"results":[]}');
    }
    if (fault == QuestionFault.nineResults) {
      return Question.parseResponse(
        '{"response_code":0,"results":[{},{},{},{},{},{},{},{},{}]}',
      );
    }
    final response = await _client
        .get(url)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw FormatException(
        'HTTP ${response.statusCode}. Please retry after five seconds.',
      );
    }
    return Question.parseResponse(response.body);
  }
}
