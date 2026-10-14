# imaji_binary_sdk — wrap a closed-source binary SDK (XCFramework, AAR) as a Flutter plugin

[![pub package](https://img.shields.io/pub/v/imaji_binary_sdk.svg)](https://pub.dev/packages/imaji_binary_sdk)
[![pub points](https://img.shields.io/pub/points/imaji_binary_sdk)](https://pub.dev/packages/imaji_binary_sdk/score)

Wrap a **closed-source binary SDK** — Swift Package Manager on iOS, a Gradle
module on Android — with the vendor binary kept out of version control and
*optional at build time*.

## Install

It is a command-line tool, published on
[pub.dev](https://pub.dev/packages/imaji_binary_sdk), so activate it globally
rather than adding it to an app's `pubspec.yaml`:

```bash
dart pub global activate imaji_binary_sdk '^0.1.0'
```

The constraint is optional; it keeps a CI job on the 0.1.x line. That puts
`imaji-binary-sdk` in `~/.pub-cache/bin`; add that directory to your `PATH`,
or call it as `dart pub global run imaji_binary_sdk`.

To track unreleased `main` instead of a published version, install from git:

```bash
dart pub global activate --source git \
  https://github.com/saimskywalker/flutter-imaji-binary-sdk.git
```

From a clone, `dart run bin/imaji_binary_sdk.dart` works with no install at
all.

**Renamed from `binary-sdk-bridge`.** A global install also puts the old
`binary-sdk-bridge` command on `PATH`, pointing at the same tool, so existing
scripts keep working.

Requires the Dart SDK (3.5 or newer). Generating needs nothing else — the
vendor binary is fetched later, by the generated `tool/fetch_*.sh`, and is
never required to build.

## Usage

Two flavours, same core:

```bash
# Flutter plugin: native wrappers + Dart API + plugin classes
imaji-binary-sdk \
  --name acme_ads --org com.example \
  --ios-framework AcmeSDK --android-aar AcmeSDK \
  --out packages

# Native only: an SPM package and a Gradle module, no Flutter anywhere
imaji-binary-sdk --flavor native \
  --name acme_sdk --org com.example \
  --ios-framework AcmeSDK --android-aar AcmeSDK \
  --out vendor
```

The native flavour is for a plain iOS or Android app — or any runtime that can
consume a Swift package and a Gradle module. It emits no pubspec, no Dart, and
no Flutter dependency at all.

## The problem

Plenty of vendor SDKs — ad mediation, analytics, payments, DRM — ship as a
prebuilt `.xcframework` behind a CocoaPods podspec and a bare `.aar`. Wiring
one into a Flutter app that uses **Swift Package Manager** runs into three
walls at once:

1. **SPM and CocoaPods have no shared resolver.** If the vendor pod and a
   pub.dev plugin both depend on the same underlying SDK, the version cannot be
   negotiated between them. The usual advice — "just use a CocoaPods wrapper" —
   quietly means *turn SPM off for the whole app*. That is a worse trade every
   month: **CocoaPods trunk goes permanently read-only on 2026-12-02.**

2. **The binary cannot be committed, but the build must still work without it.**
   Vendor binaries are proprietary, often issued per customer, and large. Yet a
   `.binaryTarget(path:)` pointing at a file that is not there fails the resolve
   of the **entire** SPM package graph — not just that target. So a fresh
   checkout without vendor credentials cannot build *anything*, and CI never
   can.

3. **A bare `.aar` carries no transitive dependency metadata.** Every SDK it
   expects at runtime has to be declared and version-managed by hand, and a
   missing one is a `ClassNotFoundException` at call time rather than a build
   error.

## What the generated package does about it

**The vendor binary is optional, and that is enforced by the build system, not
by convention.**

| | Probe | What it swaps |
|---|---|---|
| iOS | `Package.swift` checks `Frameworks/<Name>.xcframework` | declares the `binaryTarget` and defines a compilation condition |
| Android | `build.gradle.kts` checks `libs/<Name>.aar` | selects the `withSdk` or `noSdk` source set |

Without the binary, the plugin still compiles and still answers Dart — it just
reports `unavailable`. With it, the same call sites reach the real SDK. Nobody
needs vendor credentials to build the app, and CI stays green.

> ⚠️ SPM caches manifest evaluation by manifest **content**, not by filesystem
> state, so dropping the binary in afterwards does not by itself flip the
> branch. The generated fetch script clears the Flutter SPM cache for exactly
> this reason.

**Presence is decided by source sets on Android, not at runtime.** Kotlin has
no `#if`, so the module declares the same `VendorBridge` object twice, in a
`withSdk` and a `noSdk` source set, and `build.gradle.kts` compiles exactly one
of them. A generated test asserts the two bridges keep identical signatures,
since drift there compiles in one configuration and not the other.

That split does **not** yet give compile-time checking of the vendor API. The
`.aar` is declared `runtimeOnly(files(...))`, and a `runtimeOnly` dependency is
not on the compile classpath, so a vendor `import` in the generated
`src/withSdk/.../VendorBridge.kt` fails with *Unresolved reference*. As
generated, the bridge can only reach vendor classes by runtime lookup. Putting
the vendor API on the compile classpath is tracked in
[#19](https://github.com/saimskywalker/flutter-imaji-binary-sdk/issues/19).

**The native layers carry no Flutter import**, so one wrapper serves three
consumers:

| Consumer | Entry point |
|---|---|
| Flutter | `package:<name>/<name>.dart` |
| Plain iOS | the `<Name>Kit` SPM product |
| Plain Android | the generated Gradle module |

**Every degraded path fails closed.** Absent binary, unregistered plugin, native
throw, malformed payload — all resolve to `VendorState.unavailable(reason)` with
a machine-readable token. There is no `unknown` state to misread, and nothing on
the API throws at the call site.

**Downloads are checksum-pinned or refused.** The fetch scripts will not
trust-on-first-use: an artifact that links into a shipping app, behind a vendor
URL whose contents can change silently, is not something to accept sight-unseen.

## Generated layout

```
acme_ads/
├── pubspec.yaml
├── lib/
│   ├── acme_ads.dart              # probe() / initialize()
│   └── src/vendor_state.dart      # sealed ready | unavailable
├── ios/acme_ads/
│   ├── Package.swift              # the conditional binaryTarget
│   ├── Frameworks/                # gitignored — fetched
│   └── Sources/
│       ├── AcmeAdsKit/            # no Flutter import
│       └── acme_ads/              # the Flutter plugin
├── android/
│   ├── build.gradle.kts           # AGP 9 DSL
│   ├── libs/                      # gitignored — fetched
│   └── src/{main,noSdk,withSdk}/
├── test/
└── tool/fetch_{ios,android}_sdk.sh
```

Exactly one file per platform has a `TODO`: the bridge. That is the only place the vendor's
own API appears, which is the point — everything around it is already decided.

## Notes for the generated Android module

Written against the **AGP 9** DSL, which also works on AGP 8. Two forms are
avoided deliberately, because AGP 9.1 rejects them at *script compilation* —
failing the module before a single source file is read:

- `kotlinOptions` inside `android { }` → top-level `kotlin { compilerOptions { } }`
- `sourceSets { java.srcDir(...) }` → `java.directories.add(...)`

The first is the nastier one: it also drags the `android { }` accessor itself
into deprecation-as-error.

The module still applies the Kotlin Gradle Plugin
(`id("org.jetbrains.kotlin.android")`). AGP 9 turns on built-in Kotlin by
default and then refuses that plugin (*"The 'org.jetbrains.kotlin.android'
plugin is no longer required for Kotlin support since AGP 9.0"*), so on AGP 9
the generated module builds only while the host app sets
`android.builtInKotlin=false` in its `gradle.properties`. Apps created by
`flutter create` on Flutter 3.47 carry that line, and `flutter build` /
`flutter run` append it to an existing app's `gradle.properties` when the
property is missing. A plain
Android app (`--flavor native`) gets no such help and has to set it itself.
Dropping the plugin is tracked in
[#17](https://github.com/saimskywalker/flutter-imaji-binary-sdk/issues/17).

## Four traps this generator already walks around

Every one of these was hit in a production integration first. They are in the
generated code because finding them a second time is not free.

**A green build is not evidence the binary linked.** `flutter build` passes
`-quiet` to xcodebuild, which suppresses the `#warning` the bridge emits, so
its absence proves nothing. The fetch script prints the two checks that do
work: `swift package describe` reporting a `binary` target, and the framework
appearing in `Runner.app/Frameworks/`.

**SwiftPM caches manifest evaluation by CONTENT, in three places.** Dropping the
binary in afterwards does not flip the `Package.swift` probe, because the
manifest text is unchanged. Clearing only Flutter's ephemeral directory leaves
Xcode's cloned `SourcePackages` and SwiftPM's *global* manifest cache intact —
which produced three consecutive green builds with no SDK linked and nothing in
any log. The generated script clears all three.

**AGP refuses a library module with a direct local `.aar`.** `bundleDebugAar`
fails with *"Direct local .aar file dependencies are not supported when building
an AAR"*, because those classes would be dropped from the published artifact.
The generated module uses `runtimeOnly` and documents that `flutter build aar`
is unsupported while the binary is in place — the real fix is a Maven
coordinate from the vendor.

**A slot's hidden and shown states must be the SAME tree shape.** If they are
not, the moment the SDK reports success the widget's Element is disposed and
rebuilt, and the fresh `initState` fires a second request for something already
counted. In an ads context that is a doubled impression on your side of every
reconciliation. Not generator-enforced — it is a consumer-side pattern — but
the generated bridge's callback contract is shaped to make it easy to get
right.

## Host platforms

Generation works on macOS, Linux, and Windows. The generated `tool/fetch_*.sh`
scripts are bash (`#!/usr/bin/env bash`, `curl`, `shasum`, `unzip`) — on
Windows run them from WSL or Git Bash. Building the iOS `.xcframework` half
still needs macOS; Android generation and Gradle builds are fine on Windows.

## Options

| Flag | Default | |
|---|---|---|
| `--name`, `-n` | *required* | package/module name, `lower_snake_case` |
| `--flavor` | `flutter` | `flutter` (full plugin) or `native` (SPM + Gradle only) |
| `--org`, `-o` | *required* | reverse-DNS prefix, e.g. `com.example` |
| `--ios-framework` | — | `.xcframework` base name; omit to skip iOS |
| `--android-aar` | — | `.aar` base name; omit to skip Android |
| `--out` | `.` | directory to create the package in |
| `--description` | *generic* | `description:` for the generated pubspec (Flutter flavour only) |
| `--ios-target` | `15.0` | iOS deployment target |
| `--min-sdk` | `24` | Android `minSdk` |
| `--compile-sdk` | `36` | Android `compileSdk` |
| `--java` | `17` | Java / `jvmTarget` |
| `--dry-run` | | list the files without writing them |
| `--force` | | overwrite an existing package directory |

## Status

Early, but no longer theoretical. The structure this generates is running in a
production Flutter app against a real vendor SDK — the binary links, the
framework lands in the built `.app` beside a single copy of its shared
dependency, and the Android module compiles and reaches the app's runtime
classpath. The four traps above are what that integration cost, paid once.

Fresh output passes `flutter pub get`, `flutter analyze` and `flutter test`.

What it does **not** do is write the vendor calls for you; no generator can,
since that API is whatever the vendor shipped. Worth knowing that sometimes
there is no API at all — one SDK this was built against turned out to expose
no initialisation surface whatsoever, its adapters being instantiated by the
host SDK from a server response. The generated bridge starts as a runtime
presence check for exactly that reason: it is the one question worth answering
even when there is nothing to call.

## Contributing

Pull requests are welcome, including from forks — that is the normal path, and
nothing merges without a maintainer review. See
[CONTRIBUTING.md](CONTRIBUTING.md); the short version is that the **generated
output is the product**, so a template change should come with the output it
produces.

## Safety notes

Binary names are interpolated into generated shell scripts, so they are
validated against a strict character set — a name carrying a quote or a command
substitution is refused rather than written to disk. There are tests with real
injection payloads.

Nothing here downloads anything without a pinned SHA-256; the fetch scripts
refuse an unpinned URL rather than trusting it on first use.

## License

MIT
