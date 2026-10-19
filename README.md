# PhotoFlow

PhotoFlow is a local-first photo library prototype for Android and Windows, built with Flutter.

## What is implemented

- Animated, responsive photo grid and expanding photo viewer.
- Import multiple images using the native file picker.
- Copy originals into app-private storage without decoding/re-encoding them.
- Local JSON library index, filename search, zoom/pan, remove, and share.
- Android/Windows shared UI codebase.

## Current limitations

This is an early prototype, **not a finished release**. Direct device-to-device transfer is not implemented yet. Android sharing uses the system share sheet; Quick Share appears only when the device exposes it. Windows sharing and Quick Share behavior still need testing on a real Windows installation. There are no cloud uploads.

The Git repository starts with shared Dart source rather than generated Android/Windows runner folders. Run the setup command below once to generate platform scaffolding locally.

## Requirements

- Flutter stable SDK (Dart 3.3+)
- Android SDK for Android builds
- Windows 10/11 and Visual Studio with the **Desktop development with C++** workload for Windows builds

## Setup on Windows

Clone the repository, open PowerShell in the project folder, then run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\tool\setup.ps1
```

To launch on Windows:

```powershell
flutter run -d windows
```

To launch on a connected Android device (USB debugging enabled):

```powershell
flutter run -d android
```

## Data handling

- Imported images are copied into the app's private documents directory.
- The original file bytes are not re-encoded during import.
- The prototype stores its library index and photo copies locally. Uninstalling the app or clearing its data may remove those copies.
- Share actions send the original copied file, not a generated thumbnail.

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md) for native sharing validation, secure direct transfer, tests, thumbnail cache and packaging milestones.
