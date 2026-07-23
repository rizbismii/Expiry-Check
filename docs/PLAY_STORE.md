# Google Play — Expiry Check

Package ID: `com.expirycheck.expiry_check`

## 1. Save your upload keystore (one-time, critical)

You were given these private files (do **not** put them on GitHub):

- `upload-keystore.jks`
- `key.properties`

Copy them into this repo locally:

```text
android/keystore/upload-keystore.jks
android/key.properties
```

(`android/key.properties` and `android/keystore/` are gitignored.)

If you lose the keystore, you cannot publish updates under the same Play app signing setup without Google Play support.

## 2. Create the Play Console app

1. Open [Google Play Console](https://play.google.com/console) (Developer account required).
2. Create app → name **Expiry Check** → app type **App** → free/paid as you prefer.
3. Complete the dashboard checklist (privacy policy URL, content rating, target audience, etc.).

### Privacy policy

A starter policy lives at [`docs/privacy_policy.md`](../docs/privacy_policy.md). Host it as a public page (GitHub Pages, your website, etc.) and paste that URL into Play Console.

## 3. Build the Play upload file (AAB)

```bash
flutter pub get
flutter build appbundle --release
```

Output:

```text
build/app/outputs/bundle/release/app-release.aab
```

## 4. Upload to Internal testing

1. Play Console → your app → **Testing → Internal testing**
2. Create a release → upload `app-release.aab`
3. Add yourself (and testers) by email
4. Copy the internal testing link / opt-in URL onto the test phones

Internal testing is the fastest way to install from Play before production.

## 5. Versioning

Every Play upload needs a higher `versionCode`.

In `pubspec.yaml`:

```yaml
version: 1.2.5+25
#          ^name  ^code  (Android versionName + versionCode)
```

Bump `+25` → `+26` (etc.) for the next upload.

## Permissions Play will ask about

The app uses:

- Camera (label / barcode scan)
- Microphone (optional voice input)
- Notifications (expiry reminders)
- Internet (optional cloud sync)

Explain each use in the Play Console declarations.
