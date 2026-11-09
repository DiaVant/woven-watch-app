# Woven Watch

A teacher app for classrooms with neurodivergent students. Each student wears a small
watch that senses movement and reports, every 2.5 seconds, whether they are calm, lightly
fidgeting, or fidgeting a lot. The app shows the whole class live and alerts the teacher
when a student's fidgeting keeps going, so they can check in early.

**Try it:** https://fir-98546.web.app (sign up with any email)

## What it does

- **Live class view.** Every student's current state (calm, low, high), their recent
  readings, and how long the current stretch has lasted.
- **Alerts after sustained fidgeting.** An alert fires after a set number of fidget
  readings in a row and repeats while it continues. Tap the alert to open that student.
- **Student page.** A session timeline showing each period and how long it lasted, time in
  each state, the longest fidget, alert count, and signal quality.
- **Three sensitivity controls per student:** readings in a row (1–4), how often an alert
  repeats (10 s to 2 min), and a minimum watch confidence. A built-in explainer walks
  through a worked example, reading by reading, so it's clear how an alert is decided.
  Each student's alert log shows how many high and low readings triggered every alert.
- **Quiet mode.** Mute a student's alerts while still recording them.
- **Classes and watches.** Create classes, assign watches, name students per class. The
  same watch can be used in two classes by different students.
- **Bluetooth.** Scan for watches, connect, and reconnect with one tap.

## Running it

| Platform | Bluetooth to watches |
|---|---|
| Chrome or Edge (desktop, Android) | Yes |
| iOS and Android app | Yes |
| Safari, Firefox, iPhone browsers | No (Web Bluetooth isn't supported). Everything else works. |

Without a watch you can still sign up, create classes and explore the screens.

### Locally

Requires [Flutter](https://docs.flutter.dev/get-started/install) (stable channel).

```bash
flutter pub get
flutter run -d chrome
```

Run the tests:

```bash
flutter test
```

### With your own Firebase project

The app uses Firebase Authentication (email and password) and the Realtime Database.

1. Create a Firebase project. Enable **Email/Password** sign-in and a **Realtime Database**.
2. Point the app at it: `dart pub global activate flutterfire_cli`, then
   `flutterfire configure`. This rewrites `lib/firebase_options.dart`.
3. Publish the database rules and the web app:
   ```bash
   flutter build web --release
   firebase deploy --only hosting,database
   ```
   Update `.firebaserc` with your project id first.

## Data and privacy

The students are minors, so the app keeps as little as possible in the cloud.

- **In Firebase**, under each teacher's own account only: class names and colours, which
  watches are in each class, optional student names, alert settings and quiet mode. The
  rules in `database.rules.json` let a signed-in teacher read and write only their own data.
- **On the device only**: session history (readings and alerts), kept for up to 2 hours
  and the last 10 sessions. It is never uploaded and is erased on sign-out.
- Deleting an account removes all of that teacher's data from Firebase.

## How a watch talks to the app

Each watch advertises over Bluetooth LE as `wwWatch-XXXX` and sends one line every 2.5 s
over the Nordic UART service:

```
pred,<label>,<votes>
```

`label` is `not_fidgeting`, `low_fidgeting` or `high_fidgeting`. `votes` is how many of
the watch's 5 nearest-neighbour matches agreed (3–5). Classification happens on the
watch; all alert logic and settings live in the app.

## Project layout

```
lib/
  services/   alert engine, Bluetooth, Firebase services, on-device storage
  screens/    home, class page, student detail, alerts, sensitivity, devices
  pages/      sign-in, sign-up, onboarding, account
  widgets/    shared tiles and dialogs
  models/     classes and watches
test/         unit and widget tests
database.rules.json   Realtime Database security rules
```
