# Android app

The same Flutter code builds an Android app next to the PWA. In the app:

- Online play connects to `wss://uno.refandi.my.id/ws` and invite links point
  to `https://uno.refandi.my.id/join/…`. With the app installed Android opens
  them in the app; friends without it join from the browser. Build with
  `--dart-define=LC_HOST=other.host` for another server.
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

## Builds in GitHub Actions

`.github/workflows/android.yml` builds signed APKs and the app bundle for
every `v*` tag (and on demand from the Actions tab) and attaches them to the
run as the `last-card-android` artifact. It needs two repository secrets
(Settings → Secrets and variables → Actions):

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 android/upload-keystore.jks` |
| `ANDROID_KEY_PASSWORD` | the keystore password from `android/key.properties` |

The workflow refuses to run without them and fails if the result is signed
with the debug key.

```bash
git tag v0.2.0 && git push origin v0.2.0
```

## Invite links (App Links)

Android only opens `https://uno.refandi.my.id/join/…` in the app when
`web/.well-known/assetlinks.json` lists the SHA-256 fingerprint of the
certificate the installed app is signed with. It holds the current upload
key's fingerprint. If you create a new key, or publish through Google Play
(Play App Signing re-signs the app with Google's key), add that fingerprint
too (Play Console → Setup → App signing shows it):

```bash
keytool -list -v -keystore android/upload-keystore.jks -alias upload | grep SHA256
```

Check the link handling on a phone with
`adb shell pm get-app-links com.freack21.uno_mobile` (the domain should be
`verified`).

