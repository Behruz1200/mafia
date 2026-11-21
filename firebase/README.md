# Firebase (push notifications and crash reports only)

Player data does not go to Firebase. Profiles, coins, rooms and video all
run on our own server in Uzbekistan (see `deploy/`). Firebase is used only
for:

- Firebase Cloud Messaging: push notifications ("your game is starting").
- Crashlytics: crash reports, without personal data.

Not set up yet. When the Firebase project exists, run `flutterfire configure`
in `app/` and keep the generated `firebase_options.dart`,
`google-services.json` and `GoogleService-Info.plist` out of git (already in
`.gitignore`); CI gets them from GitHub secrets.
