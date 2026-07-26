import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neoforma/features/ledger/ledger_data.dart';

void main() {
  group('ClientInfo.fromMap', () {
    test('mappe les champs du DTO API', () {
      final c = ClientInfo.fromMap({
        'id': 'abc-123',
        'nom': 'Awa Traoré',
        'telephone': '+22670000000',
      });
      expect(c.id, 'abc-123');
      expect(c.nom, 'Awa Traoré');
      expect(c.telephone, '+22670000000');
    });

    test('tolère nom manquant et téléphone null', () {
      final c = ClientInfo.fromMap({'id': 42, 'telephone': null});
      expect(c.id, '42'); // converti en String
      expect(c.nom, 'Client'); // valeur de repli
      expect(c.telephone, isNull);
    });
  });

  group('ledgerRevisionProvider', () {
    test('démarre à 0 et signale un changement par incrément', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(ledgerRevisionProvider), 0);
      container.read(ledgerRevisionProvider.notifier).state++;
      expect(container.read(ledgerRevisionProvider), 1);
    });
  });
}
