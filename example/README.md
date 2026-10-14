# imaji_binary_sdk example

A walk-through with a fictional vendor SDK, `AcmeSDK`, shipped as
`AcmeSDK.xcframework` for iOS and `AcmeSDK.aar` for Android. No vendor binary
is needed for any step except the fetch.

## 1. Install the command

```bash
dart pub global activate imaji_binary_sdk '^0.1.0'
```

## 2. Generate a wrapper

A Flutter plugin package:

```bash
imaji-binary-sdk \
  --name acme_ads --org com.example \
  --ios-framework AcmeSDK --android-aar AcmeSDK \
  --out /tmp/flutter
```

Or the native flavour, a Swift package and a Gradle module with no Flutter
dependency:

```bash
imaji-binary-sdk --flavor native \
  --name acme_sdk --org com.example \
  --ios-framework AcmeSDK --android-aar AcmeSDK \
  --out /tmp/native
```

Add `--dry-run` to either command to list the files without writing them.

## 3. What you get

The Flutter flavour, trimmed to one line per directory:

```
/tmp/flutter/acme_ads/
├── pubspec.yaml
├── lib/acme_ads.dart                  # AcmeAds.probe() / AcmeAds.initialize()
├── lib/src/vendor_state.dart          # sealed VendorReady | VendorUnavailable
├── ios/acme_ads/Package.swift         # binaryTarget only when the xcframework exists
├── ios/acme_ads/Frameworks/           # gitignored; the fetch script fills it
├── ios/acme_ads/Sources/AcmeAdsKit/   # Swift wrapper, no Flutter import
├── ios/acme_ads/Sources/acme_ads/     # the Flutter plugin class
├── android/build.gradle.kts           # picks src/withSdk or src/noSdk
├── android/libs/                      # gitignored; the fetch script fills it
├── android/src/{main,noSdk,withSdk}/  # the bridge, twice, plus the plugin
├── test/acme_ads_test.dart
└── tool/fetch_{ios,android}_sdk.sh
```

The native flavour has the same `ios/`, `android/` and `tool/` trees, and no
`pubspec.yaml`, `lib/` or plugin classes.

## 4. Build without the binary

Add the package to an app with a path dependency
(`acme_ads: {path: /tmp/flutter/acme_ads}`) and build. Nothing vendor-related
is present, so the build compiles the no-SDK branch on both platforms, and the
Dart API answers instead of throwing:

```dart
final state = await AcmeAds.probe();
// VendorState.unavailable(sdk_not_bundled)
```

## 5. Fetch the binary

The fetch scripts refuse a download without a pinned SHA-256. Create
`tool/sdk_source.env` in the generated package (it is gitignored):

```bash
VENDOR_URL=https://vendor.example.com/AcmeSDK.xcframework.zip
VENDOR_SHA256=<sha256 of that zip>
VENDOR_AAR_URL=https://vendor.example.com/AcmeSDK.aar
VENDOR_AAR_SHA256=<sha256 of that file>
```

then run `tool/fetch_ios_sdk.sh` and `tool/fetch_android_sdk.sh`, or pass
either script a local path to a binary you already have. After that, `probe()`
reports `unavailable(bridge_not_implemented)` until you fill in the one `TODO`
per platform: the bridge that calls the vendor API.

## Using the generator from Dart

The CLI is a thin front end over a small library. This is
[`example.dart`](example.dart):

```dart
import 'package:imaji_binary_sdk/imaji_binary_sdk.dart';

/// Lists the files `imaji-binary-sdk` would generate for a fictional vendor
/// SDK, without writing anything. Same as the CLI's `--dry-run`.
void main() {
  final spec = BridgeSpec(
    pluginName: 'acme_ads',
    organization: 'com.example',
    iosFrameworkName: 'AcmeSDK',
    androidAarName: 'AcmeSDK',
  );

  // The constructor validates the spec and throws on an illegal name.
  final generator = BridgeGenerator(spec);

  for (final file in generator.plan()) {
    print(file.relativePath);
  }

  // `generator.write('packages')` would create packages/acme_ads/ on disk.
}
```
