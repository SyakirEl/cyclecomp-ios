# CycleComp

Flutter iPhone app prototype for cycling GPS tracking and manually drawn routes.

## Current features

- Record distance, duration and live speed using iPhone GPS.
- Keep an active ride recording when the screen is locked.
- Draw a route by tapping points on Apple Maps.
- Import and export GPX files through the iOS file picker and share sheet.
- Keep saved GPX files in the app's local Documents/Activities folder.

Routes are straight lines between tapped points; this prototype does not snap
routes to roads. Activities are stored locally and shared as GPX; there is no
account or cloud upload yet. Apple Maps does not need a third-party API key.

## Requirements for local development

- macOS with Xcode 16 or newer.
- iOS 17 or newer; iPhone 11 can run supported iOS versions.
- Flutter stable and VS Code with the Flutter and Dart extensions.

## Build and install from Windows

The `Build unsigned iOS IPA` GitHub Actions workflow builds the app on a
GitHub-hosted Mac, so a Mac is not needed on your desk. Push the project to
GitHub, then run the workflow from the repository's Actions tab or push to
`main`/`master`. Download `CycleComp-unsigned-IPA` from the completed workflow
run. Pushing a version tag such as `v1.0.0` also attaches the `.ipa` to a GitHub
Release.

The `.ipa` is unsigned and cannot be installed directly. For personal testing
without paid Apple Developer Program membership, install AltStore via AltServer
on Windows, then use AltStore on the iPhone to open the downloaded `.ipa` and
sign it with a free Apple ID. Free provisioning requires refreshing the app
about every 7 days and limits how many apps can be active. TestFlight and
distribution to other people require paid Apple Developer Program membership.

The MapKit plugin requires iOS 17. Install Xcode on the Mac, open it once to
complete setup, accept its license, and then run:

```sh
sudo xcodebuild -license accept
flutter doctor
```

Open this project on the Mac, connect the iPhone, trust the Mac on the phone,
and enable Developer Mode under Settings > Privacy & Security. In Xcode, sign
in with an Apple ID and select a development team for the Runner target.

Run on the connected iPhone:

```sh
flutter pub get
flutter run
```

CycleComp asks for Always location access when starting a ride so GPS can
continue while the app is in the background. The active ride is not uploaded
to a server; after finishing, the GPX is saved on the iPhone and the share
sheet opens.
