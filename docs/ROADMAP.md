# PhotoFlow roadmap

## Prototype now in repository

- Shared Flutter UI for Android and Windows.
- Animated gallery cards and Hero / container-transform viewer transition.
- Local import by direct file copy, with a JSON library index.
- Search by filename, full-screen image viewing, zoom/pan, remove and share.
- Share original file paths through the platform sharing plugin.

## Next milestones

1. **Validate builds**: run Flutter analyze/tests and build Android + Windows on a machine with Flutter and the relevant SDKs installed.
2. **Android system sharing**: test the Android Sharesheet on physical devices. Quick Share is available only if Android/device services expose it.
3. **Windows sharing**: verify the selected share plugin's behavior on supported Windows versions; add a small native Windows plugin if needed.
4. **Direct transfer**: design pairing, receiver approval, encrypted local-network transport, progress, cancellation, integrity checks and duplicate handling. Do not silently accept incoming files.
5. **Library robustness**: transactional index writes, migration/versioning, corrupted-file handling, duplicate detection, thumbnail cache and storage management.
6. **Release packaging**: Android APK/AAB and signed Windows installer/package.

## Direct-transfer security requirements

- Require explicit receiver consent before accepting any files.
- Pair devices using a short-lived code or QR code.
- Encrypt transfer traffic and authenticate the peer; do not treat Wi-Fi membership as trust.
- Verify file hashes and reject unexpected paths / names.
- Bind the receiver service only while a transfer session is active, and stop it when the session ends.
- Show transfer progress, source device, filenames and total size before acceptance.

## Original preservation

Import uses file copying rather than image decode/re-encode. A future thumbnail cache must be separate from the originals and must never overwrite them.
