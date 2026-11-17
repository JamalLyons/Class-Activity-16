# ICA16 Class A Cloud Quiz

Jamal Lyons · Undergraduate

Assignment: https://codd.cs.gsu.edu/~lhenry23/mad/ica/act16/V1/index.html

Ten easy General Knowledge questions from OpenTDB, one answer per question, full review, Firebase email/password sign-in, immutable owner-scoped attempts, and server-only verification. Retries retain the same round ID; unresolved submissions lock replay and sign-out.

## Submission files

- `deliverables/ICA16_A_JamalLyons.apk`: signed Android release.
- `deliverables/ICA16_A_JamalLyons_Source.zip`: minimal source and supporting evidence, excluding credentials, signing material, caches, and Git internals.
- `deliverables/ICA16_A_JamalLyons.docx`: evidence draft; review and complete the remaining personal responses and screenshots before submitting.
- `lib/`, `android/`, `web/`, dependency files, and Firebase configuration: runnable source and deployed rules.
- `docs/`: supporting test records and redacted cloud evidence cited in the evidence document. Test programs and development helper scripts were removed; recorded results describe the original verification runs. Development history remains in local Git.

The repository remains local at the student's request. The assignment's public repository URL requirement remains pending. Run `git rev-parse HEAD` for the final local commit.

## Run

Flutter 3.50 / Dart 3.14. Android and web are configured for Firebase project `my-product-app-e359e`.

```sh
flutter pub get
flutter run -d <device-id>
```

Sign in with an Email/Password user created in Firebase Console → Authentication → Users. Share grader access through the instructor-approved private channel. No passwords or signing keys are included in the submission. iOS is not included; Android is the assignment target.

To reproduce restart retrieval, sign in as the original user and enter the full saved round ID under “Retrieve a saved attempt.” The verified native record has suffix `cj7Ar0`, score 10/10, and timestamp `2026-11-16T23:36:15.390Z`. An authorized owner can locate the full ID in Firestore Console under `users/{uid}/attempts`. See the redacted screenshot in `docs/screenshots/`.

## Firebase setup

The existing project has Email/Password Authentication enabled and a Standard edition Native mode `(default)` Firestore database. The deployed `firestore.rules` allow owners to read and create only exact six-field attempts; updates, deletes, and unrelated paths are denied. Firebase client configuration identifies the project; it contains no administrator credentials.

For a separate project, create the same database and authentication provider, create test users, register the Android app, then regenerate the client configuration and deploy the included rules:

```sh
flutterfire configure --project=YOUR_PROJECT --platforms=android,web --android-package-name=edu.gsu.ica16.cloud_quiz
firebase deploy --only firestore:rules --project YOUR_PROJECT
```

Fully rebuild after native configuration changes.

## Build Android release

The supplied APK is already signed. Rebuilding a release requires your own private keystore and an ignored `android/key.properties` file. Debug runs do not require release credentials.

Create a key outside the source folder; `keytool` prompts for passwords:

```sh
keytool -genkeypair -v -keystore /absolute/private/path/ica16-release.jks -alias ica16 -keyalg RSA -keysize 2048 -validity 10000
```

Set these properties locally, replacing placeholders; never submit this file or the keystore:

```properties
storeFile=/absolute/private/path/ica16-release.jks
storePassword=YOUR_PRIVATE_PASSWORD
keyPassword=YOUR_PRIVATE_PASSWORD
keyAlias=ica16
```

```sh
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`.

## Required failure demonstrations

The assignment requires development-only fault injection; it remains available for the instructor walkthrough:

```sh
flutter run --dart-define=ENABLE_DIAGNOSTICS=true
```

Debug controls inject invalid API data, lost acknowledgement after a real transaction, unavailable, and quota exhaustion. Injections are labeled; they never simulate success. Reconcile reads the original document from the server. Question requests have a 10-second timeout and a five-second gate; retries are user-triggered. Normal release builds hide the controls.

AI disclosure: OpenAI Codex assisted application implementation, verification, rules, documentation, and the evidence draft on November 16, 2026. Review the six responses, complete missing evidence, and be ready to explain the implementation and reproduce a failure.
