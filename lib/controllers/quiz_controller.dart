import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/question.dart';
import '../services/attempt_repository.dart';
import '../services/trivia_service.dart';

enum QuizState {
  signedOut,
  loading,
  playing,
  readyToSubmit,
  submitting,
  verifying,
  cloudVerified,
  authError,
  requestError,
  saveUnknown,
  permissionDenied,
  verificationUnavailable,
}

enum SaveFault { none, lostAcknowledgement, unavailable, resourceExhausted }

class QuizController extends ChangeNotifier {
  QuizController(
    this.trivia,
    this.repository, {
    this.timeout = const Duration(seconds: 10),
  });
  final TriviaService trivia;
  final AttemptRepository repository;
  final Duration timeout;
  QuizState state = QuizState.signedOut;
  String? uid, roundId;
  String message = '';
  List<Question> questions = [];
  List<String?> selections = [];
  int index = 0;
  VerifiedAttempt? verified;
  Attempt? _frozen;
  bool _writeSettled = true, _mustReconcile = false, _busy = false;
  int _generation = 0;
  bool get busy => _busy;
  bool get canSubmit => _frozen != null && !unresolved && verified == null;
  bool get unresolved => _mustReconcile || !_writeSettled || _busy;
  int get score => List.generate(
    questions.length,
    (i) => selections[i] == questions[i].correctAnswer ? 1 : 0,
  ).fold(0, (a, b) => a + b);
  bool _current(String user, String? id, int generation) =>
      uid == user && roundId == id && _generation == generation;
  void _set(QuizState next, [String text = '']) {
    state = next;
    message = text;
    notifyListeners();
  }

  void authenticationFailed(String text) {
    if (uid == null) _set(QuizState.authError, text);
  }

  void authenticate(String? user) {
    if (uid == user) return;
    _generation++;
    uid = user;
    roundId = null;
    questions = [];
    selections = [];
    index = 0;
    _frozen = null;
    verified = null;
    _mustReconcile = false;
    _writeSettled = true;
    _busy = false;
    _set(
      user == null ? QuizState.signedOut : QuizState.readyToSubmit,
      user == null
          ? ''
          : 'Start a new General Knowledge round or retrieve a saved attempt.',
    );
  }

  Future<void> load({QuestionFault fault = QuestionFault.none}) async {
    if (uid == null || unresolved) return;
    final user = uid!;
    final generation = ++_generation;
    roundId = state == QuizState.requestError && roundId != null
        ? roundId
        : repository.newId(user);
    final id = roundId;
    _busy = true;
    questions = [];
    selections = [];
    index = 0;
    verified = null;
    _frozen = null;
    _set(QuizState.loading);
    try {
      final loaded = await trivia.load(fault: fault);
      if (!_current(user, id, generation)) return;
      questions = loaded;
      selections = List.filled(10, null);
      _set(QuizState.playing);
    } catch (e) {
      if (_current(user, id, generation)) {
        _set(
          QuizState.requestError,
          '${fault != QuestionFault.none ? 'INJECTED: ' : ''}Question request failed: $e',
        );
      }
    } finally {
      if (_current(user, id, generation)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  void answer(String choice) {
    if (state != QuizState.playing ||
        selections[index] != null ||
        !questions[index].choices.contains(choice)) {
      return;
    }
    selections[index] = choice;
    notifyListeners();
  }

  void next() {
    if (state != QuizState.playing || selections[index] == null) return;
    if (index == 9) {
      _frozen = Attempt(score);
      _set(QuizState.readyToSubmit);
    } else {
      index++;
      notifyListeners();
    }
  }

  Future<void> submit({SaveFault fault = SaveFault.none}) async {
    if (uid == null ||
        roundId == null ||
        _frozen == null ||
        unresolved ||
        verified != null) {
      return;
    }
    final user = uid!, id = roundId!, generation = _generation;
    final attempt = _frozen!;
    _busy = true;
    _writeSettled = false;
    _mustReconcile = true;
    _set(QuizState.submitting);
    // The observer stays attached after timeout. A Future timeout never cancels a commit.
    final operation = Future<void>.sync(() async {
      if (fault == SaveFault.unavailable ||
          fault == SaveFault.resourceExhausted) {
        throw CloudFailure(
          fault == SaveFault.unavailable ? 'unavailable' : 'resource-exhausted',
          'Injected repository error',
        );
      }
      await repository.commit(user, id, attempt);
    });
    final observed = operation.whenComplete(() {
      if (_current(user, id, generation)) {
        _writeSettled = true;
        notifyListeners();
      }
    });
    try {
      await observed.timeout(timeout);
      if (!_current(user, id, generation)) return;
      if (fault == SaveFault.lostAcknowledgement) {
        _set(
          QuizState.saveUnknown,
          'INJECTED: transaction completed; acknowledgement hidden. Reconcile the same round ID.',
        );
      } else {
        await _verify(user, id, generation, attempt);
      }
    } catch (e) {
      if (!_current(user, id, generation)) return;
      final denied = e is FirebaseException && e.code == 'permission-denied';
      _set(
        denied ? QuizState.permissionDenied : QuizState.saveUnknown,
        e is TimeoutException
            ? 'Save outcome unknown. The write may still commit. Reconcile before retrying.'
            : '${fault != SaveFault.none ? 'INJECTED: ' : ''}${cloudMessage(e)}',
      );
    } finally {
      if (_current(user, id, generation)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _verify(
    String user,
    String id,
    int generation,
    Attempt? expected,
  ) async {
    _set(QuizState.verifying);
    try {
      final result = await repository
          .read(user, id, expected: expected)
          .timeout(timeout);
      if (!_current(user, id, generation)) return;
      if (result == null) {
        if (_writeSettled) _mustReconcile = false;
        _set(
          QuizState.verificationUnavailable,
          _writeSettled
              ? 'Server confirms no document. Retry Submit with this same round ID, or start a new round.'
              : 'No document yet; transaction is still running. Reconcile again after it settles.',
        );
      } else {
        verified = result;
        // If an earlier transaction is still running, keep replay/sign-out locked until it settles.
        _mustReconcile = false;
        _set(
          QuizState.cloudVerified,
          'Cloud verified: exact server document, resolved timestamp, no pending writes.',
        );
      }
    } catch (e) {
      if (_current(user, id, generation)) {
        if (e is CloudFailure && e.code == 'collision' && _writeSettled) {
          // An authoritative read resolved the mismatch. Never resubmit this payload.
          _mustReconcile = false;
          _frozen = null;
          _set(
            QuizState.verificationUnavailable,
            'Server confirmed an ID collision. Original preserved. Start a new round.',
          );
        } else {
          _set(
            QuizState.verificationUnavailable,
            'Verification unavailable. ${cloudMessage(e)}',
          );
        }
      }
    }
  }

  Future<void> reconcile() async {
    if (uid == null || roundId == null || _busy) return;
    final user = uid!, id = roundId!, generation = _generation;
    _busy = true;
    await _verify(user, id, generation, _frozen);
    if (_current(user, id, generation)) {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> retrieve(String id) async {
    if (uid == null ||
        unresolved ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
      return;
    }
    roundId = id;
    _generation++;
    questions = [];
    selections = [];
    _frozen = null;
    verified = null;
    await reconcile();
  }
}
