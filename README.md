# Woven Watch

Woven Watch is a wearable classroom system that helps teachers notice when a
neurodivergent student may need support. A wrist-worn sensor recognizes sustained
changes in movement, while a companion app gives the teacher a private, real-time view
of the class and sends an alert when elevated movement continues.

Woven Watch is designed to support an educator's judgment, not replace it. Its goal is
simple: help teachers notice a quiet signal before discomfort escalates.

> **Project status:** Woven Watch is now available on the
> [App Store](https://apps.apple.com/us/app/wovenwatch/id6787783832). The currently
> published version uses the V1 interface; an updated public-facing UI is coming soon.

## Screenshots

| Live classroom view | Student timeline | Alert settings |
|:---:|:---:|:---:|
| _V1 UI screenshot coming soon_ | _V1 UI screenshot coming soon_ | _V1 UI screenshot coming soon_ |

<!-- Replace the cells above with screenshots when the updated public UI is ready. -->

## How it works

1. The watch's six-axis accelerometer and gyroscope measure wrist movement.
2. A machine-learning classifier runs directly on the watch and classifies movement as
   calm, low fidgeting, or high fidgeting.
3. Every 2.5 seconds, the watch sends only the classification and a confidence score to
   the teacher's device over Bluetooth. Raw motion data never leaves the watch.
4. The app updates the classroom dashboard and alerts the teacher when elevated readings
   continue long enough to meet that student's settings.
5. The teacher can open the student's timeline to see when movement changed, how long
   each period lasted, and why an alert was sent.

Because every student expresses discomfort differently, teachers can adjust three alert
controls for each student: the required confidence, the number of consecutive readings,
and how frequently an alert repeats. The same watch can also be assigned to different
students in different class periods, reducing the amount of hardware a classroom needs.

## What the app includes

- A live classroom dashboard showing every student's current movement state
- Private alerts after sustained elevated movement
- Individual timelines, session statistics, alert history, and signal quality
- Per-student sensitivity and repeat-frequency controls
- Quiet mode, which pauses notifications without stopping session recording
- Custom classes, color coding, student rosters, and reusable watch assignments
- Bluetooth scanning, connection, and one-tap reconnection

## Privacy by design

Woven Watch was built for classrooms, where student privacy matters.

- Movement classification happens on the watch. Raw motion data is not transmitted.
- Firebase stores only a teacher's account configuration: classes, optional student
  names, watch assignments, alert settings, and quiet-mode preferences.
- Session readings and alert history remain on the teacher's device. They are retained
  for up to two hours and the ten most recent sessions, then erased on sign-out.
- Firebase security rules restrict each signed-in teacher to their own data. Deleting an
  account also deletes that teacher's cloud data.

## Download and run

### Install on iPhone or iPad

Download [Woven Watch from the App Store](https://apps.apple.com/us/app/wovenwatch/id6787783832).

> **UI note:** The current published app uses the V1 interface. An updated public-facing
> UI is coming soon.

### Download and run locally

You will need [Git](https://git-scm.com/downloads) and the stable version of
[Flutter](https://docs.flutter.dev/get-started/install).

1. Download the project and enter its folder:

```bash
git clone https://github.com/DiaVant/woven-watch-app.git
cd woven-watch-app
```

2. Install the app's packages and run it:

```bash
flutter pub get
flutter run
```

When Flutter asks you to select a target, choose an available iOS or Android device or
simulator. Once the app opens, click **Sign Up** to create an account, then log in and
you are all set. The app can be explored without a watch.

The repository is already connected to Woven Watch's Firebase project. After launching
the app, no additional Firebase setup is required. Each account can access only its own
data.

## Technical design

The watch uses an ESP32-S3 microcontroller and a k-nearest neighbors classifier written
in CircuitPython. Every 2.5 seconds, it extracts 28 features from the previous five
seconds of motion. The original training set contained approximately 1,300 labeled
movement windows collected with parental consent. To fit the model within the watch's
memory, a balanced subset of 135 examples is packaged into a binary file for the
firmware.

The app is written in Dart and Flutter. Firebase provides authentication and stores
teacher configuration, while session data remains on-device.

Each watch advertises over Bluetooth Low Energy as `wwWatch-XXXX` and sends one line over
the Nordic UART service:

```text
pred,<label>,<votes>
```

`label` is `not_fidgeting`, `low_fidgeting`, or `high_fidgeting`. `votes` records how
many of the model's five nearest matches agreed with the classification, from 3 to 5.

## Project structure

```text
lib/
  services/   alert engine, Bluetooth, Firebase services, and on-device storage
  screens/    home, class view, student details, alerts, sensitivity, and devices
  pages/      sign-in, sign-up, onboarding, and account
  widgets/    shared tiles and dialogs
  models/     classes and watches
test/         unit and widget tests
database.rules.json   Firebase Realtime Database security rules
```
