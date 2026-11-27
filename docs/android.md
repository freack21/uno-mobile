# Android app

The same Flutter code builds an Android app next to the PWA. In the app:

- Online play connects to `wss://uno.refandi.my.id/ws` and invite links point
  to `https://uno.refandi.my.id/#join=…` (friends without the app join from the
  browser). Build with `--dart-define=LC_HOST=other.host` for another server.
- Sound effects are the web sounds rendered to `assets/sfx/*.wav`
  (`tool/render_sfx.js`); re-render them after changing `web/sfx.js`.
- Settings (light/dark, sound, the room to come back to) are kept with
  `shared_preferences`; invites open the system share sheet.

## Release signing

Release builds are signed with your own upload key and **fail without it**;
they never fall back to the debug key. The key lives outside git
(`android/key.properties` and `*.jks` are ignored).

Create the key once and keep both files (and the password) somewhere safe,
such as a password manager. Every update of the app must be signed with the
same key: an APK signed with another key will not install over the old one.

```bash
keytool -genkeypair -keystore android/upload-keystore.jks -storetype PKCS12 \
  -keyalg RSA -keysize 4096 -validity 10000 -alias upload -dname "CN=Last Card"
```

Then write `android/key.properties`:

```properties
storeFile=upload-keystore.jks
storePassword=<the password you chose>
keyAlias=upload
keyPassword=<the same password>
```

For Google Play, enroll in Play App Signing: Google keeps the app signing
key, this key is only the upload key and can be reset through Play Console if
it is lost.

## Build

Needs the Android SDK (platform 36, build tools, NDK 28.2.13676358) and JDK 17+.

```bash
flutter build apk --release        # build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release  # build/app/outputs/bundle/release/app-release.aab (Play Store)
```

Install the APK on a phone with `adb install build/app/outputs/flutter-apk/app-release.apk`
or by opening the file on the phone (allow installs from that source).
