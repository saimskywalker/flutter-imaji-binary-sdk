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
