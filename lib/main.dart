import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'controllers/quiz_controller.dart';
import 'firebase_options.dart';
import 'services/attempt_repository.dart';
import 'services/trivia_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? error;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
  } catch (_) {
    error = 'Firebase is not configured. Follow README.md, configure this platform, then fully rebuild.';
  }
  runApp(CloudQuizApp(setupError: error));
}

class CloudQuizApp extends StatelessWidget {
  const CloudQuizApp({super.key, this.setupError});
  final String? setupError;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Cloud Quiz · ICA 16',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff5633c9)),
      scaffoldBackgroundColor: const Color(0xfff6f4fc),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
    ),
    home: setupError == null
        ? const QuizScreen()
        : Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(setupError!),
              ),
            ),
          ),
  );
}

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late final QuizController quiz;
  StreamSubscription<User?>? subscription;
  final email = TextEditingController(),
      password = TextEditingController(),
      savedId = TextEditingController();
  String? authError;
  bool signingIn = false;
  QuestionFault questionFault = QuestionFault.none;
  SaveFault saveFault = SaveFault.none;
  bool get diagnostics =>
      kDebugMode && const bool.fromEnvironment('ENABLE_DIAGNOSTICS');
  @override
  void initState() {
    super.initState();
    quiz = QuizController(
      TriviaService(),
      FirestoreAttemptRepository(FirebaseFirestore.instance),
    );
    quiz.addListener(refresh);
    subscription = FirebaseAuth.instance.authStateChanges().listen(
      (user) => quiz.authenticate(user?.uid),
    );
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    subscription?.cancel();
    quiz.removeListener(refresh);
    // Outstanding cloud futures retain their controller until settlement.
    email.dispose();
    password.dispose();
    savedId.dispose();
    super.dispose();
  }

  Future<void> signIn() async {
    if (signingIn) return;
    setState(() {
      signingIn = true;
      authError = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text,
      );
      password.clear();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        authError =
            'Authentication error (${e.code}). Check your email and password.';
        quiz.authenticationFailed(authError!);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              authError = 'Authentication unavailable. Check your connection.',
        );
      }
    } finally {
      if (mounted) setState(() => signingIn = false);
    }
  }

  Widget panel(Widget child) => Card(
    child: Padding(padding: const EdgeInsets.all(24), child: child),
  );
  Widget heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      text,
      style: Theme.of(context).textTheme.headlineSmall
          ?.copyWith(fontWeight: FontWeight.bold),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Cloud Quiz'),
      actions: [
        if (quiz.uid != null)
          TextButton.icon(
            onPressed: quiz.unresolved
                ? null
                : () async {
                    try {
                      await FirebaseAuth.instance.signOut();
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => authError = 'Sign-out unavailable. Try again.',
                        );
                      }
                    }
                  },
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'ICA 16 / CLASS A',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A little knowledge.\nCloud-level confidence.',
                style: Theme.of(context).textTheme.headlineLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              const Text(
                '10 easy General Knowledge questions. One answer each. A score you can verify.',
              ),
              const SizedBox(height: 24),
              if (quiz.uid == null)
                signInPanel()
              else ...[
                SelectableText(
                  'Signed in: ${quiz.uid}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                statusPanel(),
                const SizedBox(height: 16),
                if (quiz.state == QuizState.playing) questionPanel(),
                if (quiz.questions.isNotEmpty &&
                    quiz.state != QuizState.playing)
                  reviewPanel(),
                if (!quiz.busy && quiz.state != QuizState.playing) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (quiz.questions.length == 10 && quiz.verified == null)
                        FilledButton.icon(
                          onPressed: !quiz.canSubmit
                              ? null
                              : () => quiz.submit(
                                  fault: diagnostics
                                      ? saveFault
                                      : SaveFault.none,
                                ),
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text('Submit score'),
                        ),
                      if (quiz.roundId != null)
                        OutlinedButton.icon(
                          onPressed: quiz.busy ? null : quiz.reconcile,
                          icon: const Icon(Icons.sync),
                          label: const Text('Reconcile from server'),
                        ),
                      OutlinedButton.icon(
                        onPressed: quiz.unresolved
                            ? null
                            : () => quiz.load(
                                fault: diagnostics
                                    ? questionFault
                                    : QuestionFault.none,
                              ),
                        icon: const Icon(Icons.replay),
                        label: Text(
                          quiz.questions.isEmpty
                              ? 'Start quiz / retry'
                              : 'Replay',
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                retrievePanel(),
                if (diagnostics) ...[
                  const SizedBox(height: 20),
                  diagnosticsPanel(),
                ],
              ],
              if (authError != null && quiz.uid != null) Text(authError!),
              const SizedBox(height: 28),
              const Text(
                'Open Trivia Database supplies questions. Firebase stores your completed score.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget signInPanel() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('Sign in to your quiz account'),
        const Text(
          'Use a test account created in this project’s Firebase Authentication console.',
        ),
        const SizedBox(height: 20),
        TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.username],
          decoration: const InputDecoration(labelText: 'Email'),
          enabled: !signingIn,
        ),
        const SizedBox(height: 14),
        TextField(
          controller: password,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(labelText: 'Password'),
          enabled: !signingIn,
          onSubmitted: (_) => signIn(),
        ),
        if (authError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(authError!, style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: signingIn ? null : signIn,
          child: Text(signingIn ? 'Signing in…' : 'Sign in'),
        ),
      ],
    ),
  );
  Widget statusPanel() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              quiz.state == QuizState.cloudVerified
                  ? Icons.verified
                  : quiz.unresolved
                  ? Icons.cloud_sync
                  : Icons.info_outline,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                quiz.state.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        if (quiz.busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: LinearProgressIndicator(),
          ),
        if (quiz.message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(quiz.message),
          ),
        if (quiz.roundId != null) ...[
          const SizedBox(height: 12),
          SelectableText('users/${quiz.uid}/attempts/${quiz.roundId}'),
          TextButton.icon(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: quiz.roundId!)),
            icon: const Icon(Icons.copy),
            label: const Text('Copy round ID'),
          ),
        ],
        if (quiz.verified case final result?) ...[
          Text('Score: ${result.attempt.correctCount}/10'),
          Text('submittedAt: ${result.submittedAt.toUtc().toIso8601String()}'),
          const Text(
            'schemaVersion: 1 · variant: A · categoryId: 9 · questionCount: 10',
          ),
          const Text('Read source: server · pending writes: false'),
        ],
        if (quiz.unresolved)
          const Text(
            'Replay and sign-out locked until the cloud operation is resolved.',
          ),
      ],
    ),
  );
  Widget questionPanel() {
    final question = quiz.questions[quiz.index],
        selected = quiz.selections[quiz.index];
    return panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'QUESTION ${quiz.index + 1} OF 10 · SCORE ${quiz.score}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: (quiz.index + 1) / 10),
          const SizedBox(height: 24),
          heading(question.text),
          ...question.choices.map((choice) {
            final correct = choice == question.correctAnswer;
            final chosen = choice == selected;
            final color = selected == null
                ? null
                : correct
                ? Colors.green.shade100
                : chosen
                ? Colors.red.shade100
                : null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  backgroundColor: color,
                  disabledForegroundColor: Colors.black87,
                  padding: const EdgeInsets.all(18),
                  alignment: Alignment.centerLeft,
                ),
                onPressed: selected == null ? () => quiz.answer(choice) : null,
                child: Text(
                  '${selected != null && correct
                      ? '✓ Correct: '
                      : chosen
                      ? '✗ Selected: '
                      : ''}$choice',
                ),
              ),
            );
          }),
          if (selected != null)
            Text(
              selected == question.correctAnswer
                  ? 'Correct! One point earned.'
                  : 'Incorrect. Correct answer: ${question.correctAnswer}',
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: selected == null ? null : quiz.next,
            child: Text(
              quiz.index == 9 ? 'Review all answers' : 'Next question',
            ),
          ),
        ],
      ),
    );
  }

  Widget reviewPanel() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading('Round complete · ${quiz.score}/10'),
        ...List.generate(quiz.questions.length, (i) {
          final q = quiz.questions[i], selected = quiz.selections[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}. ${q.text}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${selected == q.correctAnswer ? '✓ Correct' : '✗ Incorrect'} · Your answer: $selected',
                ),
                Text('Correct answer: ${q.correctAnswer}'),
              ],
            ),
          );
        }),
      ],
    ),
  );
  Widget retrievePanel() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('Retrieve a saved attempt'),
        const Text(
          'After restarting, sign in as the same user and paste the original round ID. This always reads the server.',
        ),
        const SizedBox(height: 14),
        TextField(
          controller: savedId,
          enabled: !quiz.unresolved,
          decoration: const InputDecoration(labelText: 'Saved round ID'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: quiz.unresolved
              ? null
              : () {
                  final id = savedId.text.trim();
                  if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter a valid round ID.')),
                    );
                  } else {
                    quiz.retrieve(id);
                  }
                },
          child: const Text('Retrieve from server'),
        ),
      ],
    ),
  );
  Widget diagnosticsPanel() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('Development fault injection'),
        const Text(
          'INJECTED cases are labeled. Lost acknowledgement still performs a real cloud transaction.',
        ),
        DropdownButton<QuestionFault>(
          value: questionFault,
          isExpanded: true,
          items: QuestionFault.values
              .map(
                (v) => DropdownMenuItem(
                  value: v,
                  child: Text('Question: ${v.name}'),
                ),
              )
              .toList(),
          onChanged: quiz.unresolved
              ? null
              : (v) => setState(() => questionFault = v!),
        ),
        DropdownButton<SaveFault>(
          value: saveFault,
          isExpanded: true,
          items: SaveFault.values
              .map(
                (v) =>
                    DropdownMenuItem(value: v, child: Text('Save: ${v.name}')),
              )
              .toList(),
          onChanged: quiz.unresolved
              ? null
              : (v) => setState(() => saveFault = v!),
        ),
      ],
    ),
  );
}
