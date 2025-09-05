# BTRelay

Cross-platform BLE relay for Android and iOS.

## Overview
- Receives BLE frames split across packets and reassembles them.
- Validates payloads with HMAC-SHA256 using a user-provided secret.
- Queues verified frames to local storage.
- Forwards queued frames over HTTP when network is available with rate limiting.
- Provides a simple settings UI to configure secret and throttling options.

## Building
### Android
1. Install the Android SDK (API level 33+).
2. Set `sdk.dir` in `android/local.properties` or define `ANDROID_HOME`.
3. From the `android` directory run `./gradlew assembleDebug`.

### iOS
Open `ios/Relay.xcodeproj` in Xcode and build the `Relay` target.

## Testing
Unit tests cover frame assembly, HMAC verification, and throttling logic.
Run Android tests with `./gradlew test` and iOS tests via the `RelayTests` scheme in Xcode.
