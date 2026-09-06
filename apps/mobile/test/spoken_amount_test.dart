import 'package:flutter_test/flutter_test.dart';
import 'package:neoforma/core/voice/spoken_amount.dart';

void main() {
  group('parseSpokenAmount — chiffres', () {
    test('null / vide', () {
      expect(parseSpokenAmount(null), isNull);
      expect(parseSpokenAmount(''), isNull);
      expect(parseSpokenAmount('   '), isNull);
    });

    test('chiffres bruts et séparateurs FR', () {
      expect(parseSpokenAmount('5000'), 5000);
      expect(parseSpokenAmount('5 000'), 5000);
      expect(parseSpokenAmount('5.000 francs'), 5000);
      expect(parseSpokenAmount('20 000 FCFA'), 20000);
    });
  });

  group('parseSpokenAmount — français', () {
    test('unités et dizaines', () {
      expect(parseSpokenAmount('cinq'), 5);
      expect(parseSpokenAmount('vingt cinq'), 25);
      expect(parseSpokenAmount('vingt-cinq'), 25);
    });

    test('centaines et milliers', () {
      expect(parseSpokenAmount('cent'), 100);
      expect(parseSpokenAmount('deux cent cinquante'), 250);
      expect(parseSpokenAmount('mille'), 1000);
      expect(parseSpokenAmount('cinq mille'), 5000);
      expect(parseSpokenAmount('deux mille cinq cents'), 2500);
      expect(parseSpokenAmount('cinquante mille francs'), 50000);
    });

    test('soixante-dix et quatre-vingts', () {
      expect(parseSpokenAmount('soixante-dix'), 70);
      expect(parseSpokenAmount('soixante dix sept'), 77);
      expect(parseSpokenAmount('quatre-vingt'), 80);
      expect(parseSpokenAmount('quatre-vingt-dix'), 90);
      expect(parseSpokenAmount('quatre-vingt-onze'), 91);
    });
  });

  group('parseSpokenAmount — mooré (et STT phonétique FR)', () {
    test('unités et dix', () {
      expect(parseSpokenAmount('yembre'), 1);
      expect(parseSpokenAmount('yiibu'), 2);
      expect(parseSpokenAmount('piiga'), 10);
      expect(parseSpokenAmount('piga'), 10);
      expect(parseSpokenAmount('piiga la yembre'), 11);
    });

    test('milliers (tusa nu = 5000)', () {
      expect(parseSpokenAmount('tusa'), 1000);
      expect(parseSpokenAmount('tusa nu'), 5000);
      expect(parseSpokenAmount('toussa nous'), 5000);
      expect(parseSpokenAmount('nu tusa'), 5000);
    });

    test('dizaines composées et STT phonétique FR', () {
      expect(parseSpokenAmount('pis nu'), 50);
      expect(parseSpokenAmount('koabga nu'), 500);
      expect(parseSpokenAmount('pika', lang: 'mr'), 10);
      expect(parseSpokenAmount('tout ca nous', lang: 'mr'), 5000);
      expect(parseSpokenAmount('tout ça nous', lang: 'mr'), 5000);
      expect(parseSpokenAmount('yembere', lang: 'mr'), 1);
      expect(parseSpokenAmount('nasse', lang: 'mr'), 4);
      expect(
        parseSpokenAmount('blabla', lang: 'mr', alternates: ['tusa nu']),
        5000,
      );
      expect(
        parseSpokenAmount('blabla', lang: 'mr', alternates: ['cinq mille']),
        5000,
      );
    });
  });
}
