import 'dart:convert';
import 'dart:math';

import 'package:html_unescape/html_unescape.dart';

class Question {
  const Question(this.text, this.correctAnswer, this.choices);
  final String text;
  final String correctAnswer;
  final List<String> choices;

  static List<Question> parseResponse(String body, {Random? random}) {
    final json = jsonDecode(body);
    if (json is! Map || json['response_code'] != 0) {
      throw const FormatException(
        'Question API did not return success (code 0).',
      );
    }
    final results = json['results'];
    if (results is! List || results.length != 10) {
      throw const FormatException('Exactly 10 questions are required.');
    }
    final decoder = HtmlUnescape();
    String decode(dynamic value) {
      if (value is! String) {
        throw const FormatException('Missing question text.');
      }
      final text = decoder.convert(value).trim();
      if (text.isEmpty) {
        throw const FormatException('Empty question or answer.');
      }
      return text;
    }

    return List.unmodifiable(
      results.map((row) {
        if (row is! Map ||
            row['category'] != 'General Knowledge' ||
            row['difficulty'] != 'easy' ||
            row['type'] != 'multiple') {
          throw const FormatException(
            'Unexpected category, difficulty, or type.',
          );
        }
        final incorrect = row['incorrect_answers'];
        if (incorrect is! List || incorrect.length != 3) {
          throw const FormatException('Three incorrect answers are required.');
        }
        final correct = decode(row['correct_answer']);
        final choices = [correct, ...incorrect.map(decode)];
        if (choices.toSet().length != 4) {
          throw const FormatException(
            'Answer choices must be distinct after decoding.',
          );
        }
        choices.shuffle(random);
        return Question(
          decode(row['question']),
          correct,
          List.unmodifiable(choices),
        );
      }),
    );
  }
}
