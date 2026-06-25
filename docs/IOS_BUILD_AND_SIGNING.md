# iOS Build And Signing

GitHub Actions builds the app on a macOS runner and uploads:

- `maxgravity-unsigned-ipa`
- `maxgravity-simulator-app`

The unsigned IPA is suitable for tooling such as Sideloadly when the user supplies their Apple ID and device trust locally. The repository does not store Apple credentials, provisioning profiles, signing certificates, APNs keys, or team secrets.

## Local Build

Requirements:

- macOS
- Xcode with iOS 17+ SDK
- Swift package resolution network access

Command:

```bash
xcodebuild \
  -project Maxgravity.xcodeproj \
  -scheme Maxgravity \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Signing For Device Distribution

External setup required:

- Apple Developer account.
- App identifier for `com.maxgravity.app`.
- Signing certificate.
- Provisioning profile.
- Optional App Groups / Keychain Sharing if later added.
- APNs key if background Live Activity updates are enabled.
