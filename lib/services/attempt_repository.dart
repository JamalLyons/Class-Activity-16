import 'package:cloud_firestore/cloud_firestore.dart';

class Attempt {
  const Attempt(this.correctCount);
  final int correctCount;
  Map<String, dynamic> get fixedFields => {
    'schemaVersion': 1,
    'variant': 'A',
    'categoryId': 9,
    'questionCount': 10,
    'correctCount': correctCount,
  };
  Map<String, dynamic> get payload => {
    ...fixedFields,
    'submittedAt': FieldValue.serverTimestamp(),
  };
  bool matches(Map<String, dynamic> data) =>
      data.length == 6 &&
      fixedFields.entries.every(
        (e) =>
            data[e.key] == e.value && (e.value is! int || data[e.key] is int),
      ) &&
      data['submittedAt'] is Timestamp;
}

class CloudFailure implements Exception {
  const CloudFailure(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

class VerifiedAttempt {
  const VerifiedAttempt(this.path, this.attempt, this.submittedAt);
  final String path;
  final Attempt attempt;
  final DateTime submittedAt;
}

abstract class AttemptRepository {
  String newId(String uid);
  Future<void> commit(String uid, String id, Attempt attempt);
  Future<VerifiedAttempt?> read(String uid, String id, {Attempt? expected});
}

class FirestoreAttemptRepository implements AttemptRepository {
  FirestoreAttemptRepository(this.db);
  final FirebaseFirestore db;
  DocumentReference<Map<String, dynamic>> _ref(String uid, String id) =>
      db.collection('users').doc(uid).collection('attempts').doc(id);
  @override
  String newId(String uid) =>
      db.collection('users').doc(uid).collection('attempts').doc().id;
  @override
  Future<void> commit(String uid, String id, Attempt attempt) async {
    final ref = _ref(uid, id);
    final payload = attempt.payload;
    await db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (snapshot.exists) {
        if (!attempt.matches(snapshot.data()!)) {
          throw const CloudFailure(
            'collision',
            'Round ID collision: existing attempt differs. Original preserved.',
          );
        }
      } else {
        transaction.set(ref, payload);
      }
    });
  }

  @override
  Future<VerifiedAttempt?> read(
    String uid,
    String id, {
    Attempt? expected,
  }) async {
    final snapshot = await _ref(
      uid,
      id,
    ).get(const GetOptions(source: Source.server));
    if (!snapshot.exists) return null;
    final data = snapshot.data()!;
    final score = data['correctCount'];
    if (snapshot.metadata.isFromCache ||
        snapshot.metadata.hasPendingWrites ||
        score is! int ||
        score < 0 ||
        score > 10 ||
        !(expected ?? Attempt(score)).matches(data)) {
      throw const CloudFailure(
        'collision',
        'Server document does not match the exact attempt schema or score.',
      );
    }
    return VerifiedAttempt(
      snapshot.reference.path,
      Attempt(score),
      (data['submittedAt'] as Timestamp).toDate(),
    );
  }
}

String cloudMessage(Object error) {
  final code = error is FirebaseException
      ? error.code
      : error is CloudFailure
      ? error.code
      : 'unknown';
  return switch (code) {
    'permission-denied' =>
      'Permission denied. Check signed-in ownership and deployed rules.',
    'unauthenticated' =>
      'Authentication expired. Sign in again before recovery.',
    'unavailable' =>
      'Cloud unavailable. Reconnect, then reconcile this same round ID.',
    'resource-exhausted' => 'Cloud quota exhausted. Wait for quota recovery; do not repeatedly retry.',
    _ =>
      error is CloudFailure
          ? error.message
          : 'Cloud response unavailable. Reconcile before retrying.',
  };
}
