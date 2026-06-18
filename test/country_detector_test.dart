import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/services/country_detector.dart';

void main() {
  setUp(() {
    CountryDetector.resetForTesting();
  });

  group('fromLocaleString', () {
    test('parses underscore-separated locale identifiers', () {
      expect(CountryDetector.fromLocaleString('en_US'), 'US');
      expect(CountryDetector.fromLocaleString('sw_KE'), 'KE');
      expect(CountryDetector.fromLocaleString('en_GB'), 'GB');
    });

    test('parses hyphen-separated locale identifiers', () {
      expect(CountryDetector.fromLocaleString('en-US'), 'US');
      expect(CountryDetector.fromLocaleString('fr-FR'), 'FR');
    });

    test('uppercases the country segment', () {
      expect(CountryDetector.fromLocaleString('en_us'), 'US');
    });

    test('returns null when no country segment is present', () {
      expect(CountryDetector.fromLocaleString('en'), isNull);
      expect(CountryDetector.fromLocaleString(''), isNull);
      expect(CountryDetector.fromLocaleString('   '), isNull);
    });

    test('rejects non-2-letter country segments', () {
      expect(CountryDetector.fromLocaleString('en_USA'), isNull);
      expect(CountryDetector.fromLocaleString('en_1'), isNull);
    });
  });

  group('detect caching', () {
    test('cached getter is null before detect runs', () {
      expect(CountryDetector.cached, isNull);
    });
  });
}
