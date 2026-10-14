import 'dart:io';

import 'package:test/test.dart';

/// Reads a file from the package root with line endings normalised, so the
/// Windows job (which checks out CRLF) sees the same text as Linux.
String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('pub.dev metadata', () {
    test('the folded pubspec description is 60-180 characters (#13)', () {
      // pub.dev deducts 10 points outside that range, and search results cut
      // a longer one off. 0.1.0 shipped at 203.
      final lines = _read('pubspec.yaml').split('\n');
      final start = lines.indexOf('description: >-');
      expect(start, isNot(-1),
          reason: 'expected a folded `description: >-` block');
      final folded = lines
          .skip(start + 1)
          .takeWhile((line) => line.startsWith('  '))
          .map((line) => line.trim())
          .join(' ');
      expect(folded.length, inInclusiveRange(60, 180), reason: folded);
    });

    test('example/README.md shows example/example.dart verbatim (#14)', () {
      // example.dart is analysed by CI; the README is what pub.dev shows on
      // the Example tab. Embedding one in the other keeps the shown snippet
      // compiling against the real API.
      final dart = _read('example/example.dart');
      final readme = _read('example/README.md');
      expect(readme, contains('```dart\n$dart```'));
    });
  });
}
