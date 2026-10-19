# PhotoFlow

PhotoFlow is a local-first photo library for Android and Windows, built with Flutter.

## Goals

- Keep imported photo files byte-for-byte unchanged; previews are for display only.
- Provide a polished, animation-rich gallery and full-screen viewer.
- Use the Android system share sheet so users can choose Quick Share when available.
- Support direct device-to-device transfer as a separate feature, with explicit receiver approval and encrypted transport.
- Build Android APKs and Windows desktop releases from a shared Flutter UI.

## Current status

This repository starts with the Flutter application scaffold and local photo import/view/share prototype. It is not yet a finished application. Direct LAN transfer, Windows Quick Share integration, automated tests, and packaged builds remain future work.

## Requirements

- Flutter stable SDK (3.24 or newer recommended)
- Android SDK for Android builds
- Windows 10/11 with Visual Studio's **Desktop development with C++** workload for Windows builds

## Run

```sh
flutter pub get
flutter run
```

On Windows, run `flutter run -d windows`. On Android, enable developer options and USB debugging or use an Android emulator.

## Important behavior

- Imported images are copied into the app's private documents directory without decoding/re-encoding the original file.
- Android sharing opens the OS share sheet; Quick Share appears only when the device/OS provides it.
- The initial Windows share implementation uses the plugin's supported sharing mechanism. Native Quick Share invocation is not guaranteed.
- The initial prototype stores photos locally and does not upload them to a server.
